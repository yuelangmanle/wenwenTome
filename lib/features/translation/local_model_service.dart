import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../app/runtime_platform.dart';
import '../../core/downloads/download_task_store.dart';
import '../../core/downloads/single_connection_resumable_downloader.dart';
import '../../core/storage/app_storage_paths.dart';
import 'android_local_translation_executor.dart';
import '../logging/app_run_log_service.dart';
import 'local_translation_executor.dart';

class LocalModelState {
  const LocalModelState({
    this.isDownloading = false,
    this.downloadProgress = 0,
    this.isDownloaded = false,
    this.isRunning = false,
    this.modelSize = '未知',
    this.statusText = '未下载',
  });

  final bool isDownloading;
  final double downloadProgress;
  final bool isDownloaded;
  final bool isRunning;
  final String modelSize;
  final String statusText;

  LocalModelState copyWith({
    bool? isDownloading,
    double? downloadProgress,
    bool? isDownloaded,
    bool? isRunning,
    String? modelSize,
    String? statusText,
  }) {
    return LocalModelState(
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isRunning: isRunning ?? this.isRunning,
      modelSize: modelSize ?? this.modelSize,
      statusText: statusText ?? this.statusText,
    );
  }
}

class LocalModelCheckResult {
  const LocalModelCheckResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class LocalModelNotifier extends Notifier<LocalModelState> {
  LocalModelNotifier({
    Future<Directory> Function()? appSupportDirProvider,
    LocalRuntimePlatform Function()? platformResolver,
    LocalTranslationExecutor? localExecutor,
    DownloadTaskStore? downloadTaskStore,
    SingleConnectionResumableDownloader? downloader,
    List<String> Function({required bool useMirror})? downloadCandidatesBuilder,
    Future<String> Function()? serverDownloadUrlResolver,
    Duration androidPrepareTimeout = const Duration(seconds: 40),
  }) : _appSupportDirProvider =
           appSupportDirProvider ?? getSafeApplicationSupportDirectory,
       _platformResolver = platformResolver ?? detectLocalRuntimePlatform,
       _localExecutor = localExecutor,
       _androidPrepareTimeout = androidPrepareTimeout,
       _downloadTaskStore = _resolveDownloadTaskStore(
         downloadTaskStore: downloadTaskStore,
         appSupportDirProvider: appSupportDirProvider,
       ),
       _downloader =
           downloader ??
           SingleConnectionResumableDownloader(
             downloadTaskStore: _resolveDownloadTaskStore(
               downloadTaskStore: downloadTaskStore,
               appSupportDirProvider: appSupportDirProvider,
             ),
           ),
       _downloadCandidatesBuilder =
           downloadCandidatesBuilder ?? LocalModelNotifier.downloadCandidates,
       _serverDownloadUrlResolver =
           serverDownloadUrlResolver ??
           LocalModelNotifier._resolveServerDownloadUrl;

  static const modelFileName = 'HY-MT1.5-1.8B-Q4_K_M.gguf';
  static const savedModelFileName = 'hy-mt.gguf';
  static const taskModelId = 'hy-mt';
  static const modelUrlOfficial =
      'https://huggingface.co/Tencent/HY-MT1.5-1.8B-GGUF/resolve/main/HY-MT1.5-1.8B-Q4_K_M.gguf';
  static const modelUrlMirror =
      'https://hf-mirror.com/Tencent/HY-MT1.5-1.8B-GGUF/resolve/main/HY-MT1.5-1.8B-Q4_K_M.gguf';
  static const fallbackServerUrl =
      'https://github.com/ggml-org/llama.cpp/releases/download/b8209/llama-b8209-bin-win-cpu-x64.zip';
  static const runtimeTaskModelId = 'llama-server-win-cpu-x64';
  static const runtimeArchiveFileName = 'llama-server.zip';
  static const runtimeExecutableFileName = 'llama-server.exe';

  final Future<Directory> Function() _appSupportDirProvider;
  final LocalRuntimePlatform Function() _platformResolver;
  final LocalTranslationExecutor? _localExecutor;
  final Duration _androidPrepareTimeout;
  final DownloadTaskStore _downloadTaskStore;
  final SingleConnectionResumableDownloader _downloader;
  final List<String> Function({required bool useMirror})
  _downloadCandidatesBuilder;
  final Future<String> Function() _serverDownloadUrlResolver;

  static DownloadTaskStore _resolveDownloadTaskStore({
    required DownloadTaskStore? downloadTaskStore,
    required Future<Directory> Function()? appSupportDirProvider,
  }) {
    if (downloadTaskStore != null) {
      return downloadTaskStore;
    }
    if (appSupportDirProvider == null) {
      return DownloadTaskStore.instance;
    }
    return DownloadTaskStore(appSupportDirProvider: appSupportDirProvider);
  }

  Process? _serverProcess;
  String _modelDir = '';
  StreamSubscription<List<DownloadTaskRecord>>? _taskSubscription;
  Future<void>? _startServerOperation;
  Timer? _refreshDebounce;
  DateTime? _lastProgressStateAt;
  double _lastProgressValue = -1;

  String get modelDirectoryPath => _modelDir;

  LocalTranslationExecutor? get _effectiveLocalExecutor {
    if (_localExecutor != null) {
      return _localExecutor;
    }
    if (_platformResolver() == LocalRuntimePlatform.android) {
      return AndroidLocalTranslationExecutor(
        appSupportDirProvider: _appSupportDirProvider,
        platformResolver: _platformResolver,
        modelFileName: savedModelFileName,
      );
    }
    return null;
  }

  static List<String> downloadCandidates({required bool useMirror}) {
    final ordered = <String>[
      useMirror ? modelUrlMirror : modelUrlOfficial,
      useMirror ? modelUrlOfficial : modelUrlMirror,
    ];
    final seen = <String>{};
    return ordered.where(seen.add).toList();
  }

  @override
  LocalModelState build() {
    ref.onDispose(() {
      unawaited(_taskSubscription?.cancel());
      _refreshDebounce?.cancel();
    });
    unawaited(_initialize());
    return const LocalModelState();
  }

  Future<void> _initialize() async {
    await _downloadTaskStore.ensureInitialized();
    await _downloadTaskStore.markStaleActiveTasksAsFailed();
    _taskSubscription ??= _downloadTaskStore.watch().listen((_) {
      if (!ref.mounted) {
        return;
      }
      _scheduleRefreshState();
    });
    await _refreshState();
  }

  void _scheduleRefreshState() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!ref.mounted) {
        return;
      }
      unawaited(_refreshState());
    });
  }

  bool _shouldPublishProgress(double progress) {
    final now = DateTime.now();
    final lastAt = _lastProgressStateAt;
    if (lastAt != null &&
        now.difference(lastAt) < const Duration(milliseconds: 180) &&
        (progress - _lastProgressValue).abs() < 0.01 &&
        progress < 1.0) {
      return false;
    }
    _lastProgressStateAt = now;
    _lastProgressValue = progress;
    return true;
  }

  Future<String> ensureInitialized() async {
    if (_modelDir.isNotEmpty) {
      return _modelDir;
    }
    final dir = await _appSupportDirProvider();
    _modelDir = p.join(dir.path, 'models', 'hy-mt');
    return _modelDir;
  }

  Future<void> _refreshState() async {
    await ensureInitialized();
    if (!ref.mounted) {
      return;
    }
    final modelFile = File(p.join(_modelDir, savedModelFileName));
    final exeFile = File(p.join(_modelDir, runtimeExecutableFileName));
    await _promoteStagedModelIfPossible(modelFile);
    if (!ref.mounted) {
      return;
    }

    final task = await _downloadTaskStore.getTask(
      DownloadTaskKind.translationModel,
      taskModelId,
    );
    final modelReady = await modelFile.exists();
    final runtimeReady = _platformResolver() == LocalRuntimePlatform.windows
        ? await exeFile.exists()
        : true;

    if (modelReady && runtimeReady) {
      final sizeBytes = await modelFile.length();
      if (!ref.mounted) {
        return;
      }
      state = state.copyWith(
        isDownloading: false,
        downloadProgress: 1,
        isDownloaded: true,
        modelSize: _formatSize(sizeBytes),
        statusText: _platformResolver() == LocalRuntimePlatform.windows
            ? '模型与运行时已就绪'
            : '模型文件已下载',
      );
      return;
    }

    if (task != null) {
      switch (task.status) {
        case DownloadTaskStatus.queued:
        case DownloadTaskStatus.downloading:
          state = state.copyWith(
            isDownloading: true,
            downloadProgress: task.progress,
            isDownloaded: false,
            modelSize: task.totalBytes > 0
                ? _formatSize(task.totalBytes)
                : state.modelSize,
            statusText: '正在下载翻译模型 ${(task.progress * 100).toStringAsFixed(1)}%',
          );
          return;
        case DownloadTaskStatus.staged:
          state = state.copyWith(
            isDownloading: false,
            downloadProgress: 1,
            isDownloaded: false,
            statusText: task.error?.isNotEmpty == true
                ? task.error!
                : '下载已完成，等待切换',
          );
          return;
        case DownloadTaskStatus.failed:
          state = state.copyWith(
            isDownloading: false,
            isDownloaded: false,
            downloadProgress: task.progress,
            modelSize: task.totalBytes > 0
                ? _formatSize(task.totalBytes)
                : state.modelSize,
            statusText: task.downloadedBytes > 0
                ? task.totalBytes > 0
                      ? '下载中断，已保留 ${_formatSize(task.downloadedBytes)} / ${_formatSize(task.totalBytes)}，可重试继续'
                      : '下载中断，已保留 ${_formatSize(task.downloadedBytes)}，可重试继续'
                : '下载失败，可重试切换线路',
          );
          return;
        case DownloadTaskStatus.completed:
          break;
      }
    }

    state = state.copyWith(
      isDownloading: false,
      downloadProgress: 0,
      isDownloaded: false,
      modelSize: '未知',
      statusText: '未下载',
    );
  }

  Future<void> _promoteStagedModelIfPossible(File modelFile) async {
    final task = await _downloadTaskStore.getTask(
      DownloadTaskKind.translationModel,
      taskModelId,
    );
    if (task == null || task.status != DownloadTaskStatus.staged) {
      return;
    }

    final stagedPath = task.tempPath;
    if (stagedPath.isEmpty) {
      await _downloadTaskStore.markFailed(
        kind: DownloadTaskKind.translationModel,
        modelId: taskModelId,
        source: task.source,
        tempPath: stagedPath,
        finalPath: modelFile.path,
        error: '暂存文件缺失，请重新下载',
      );
      return;
    }

    final stagedFile = File(stagedPath);
    if (await modelFile.exists()) {
      if (await stagedFile.exists()) {
        await _safeDelete(stagedFile);
      }
      await _downloadTaskStore.markCompleted(
        kind: DownloadTaskKind.translationModel,
        modelId: taskModelId,
        source: task.source,
        finalPath: modelFile.path,
      );
      return;
    }

    if (!await stagedFile.exists()) {
      await _downloadTaskStore.markFailed(
        kind: DownloadTaskKind.translationModel,
        modelId: taskModelId,
        source: task.source,
        tempPath: stagedPath,
        finalPath: modelFile.path,
        error: '暂存文件丢失，请重新下载',
      );
      return;
    }

    /*
    {
      try {
        final downloadResult = await _downloader.download(
          kind: DownloadTaskKind.translationModel,
          modelId: taskModelId,
          candidates: _downloadCandidatesBuilder(useMirror: useMirror),
          tempFile: partFile,
          finalPath: modelFile.path,
          onStatus: (message) {
            state = state.copyWith(isDownloading: true, statusText: message);
            unawaited(
              AppRunLogService.instance.logInfo('翻译模型下载状态: $message'),
            );
          },
          onProgress: (progress) {
            if (!_shouldPublishProgress(progress.progress)) {
              return;
            }
            state = state.copyWith(
              isDownloading: true,
              downloadProgress: progress.progress,
              modelSize: progress.totalBytes > 0
                  ? _formatSize(progress.totalBytes)
                  : state.modelSize,
              statusText: progress.totalBytes > 0
                  ? '下载翻译模型 ${_formatSize(progress.downloadedBytes)} / ${_formatSize(progress.totalBytes)}'
                  : '下载翻译模型 ${_formatSize(progress.downloadedBytes)}',
            );
          },
        );
        await _finalizeDownloadedModel(
          source: downloadResult.source,
          partFile: partFile,
          finalFile: modelFile,
        );
        await AppRunLogService.instance.logInfo('翻译模型下载流程完成');
        await _refreshState();
      } catch (error) {
        await AppRunLogService.instance.logError('翻译模型下载异常: $error');
        await _refreshState();
        state = state.copyWith(
          isDownloading: false,
          statusText: '下载失败: $error',
        );
      }
      return;
    }

    */
    try {
      await _replaceFile(stagedFile, modelFile);
      await _downloadTaskStore.markCompleted(
        kind: DownloadTaskKind.translationModel,
        modelId: taskModelId,
        source: task.source,
        finalPath: modelFile.path,
      );
      await AppRunLogService.instance.logInfo('已将翻译模型暂存文件切换为正式文件');
    } catch (error) {
      await AppRunLogService.instance.logError('翻译模型暂存切换失败：$error');
    }
  }

  Future<LocalModelCheckResult> checkAvailability() async {
    try {
      await _refreshState();
      if (!state.isDownloaded) {
        return const LocalModelCheckResult(
          success: false,
          message: '翻译模型尚未下载。',
        );
      }

      final platform = _platformResolver();
      final executor = _effectiveLocalExecutor;
      if (platform == LocalRuntimePlatform.android && executor != null) {
        final result = await executor.checkAvailability();
        return LocalModelCheckResult(
          success: result.success,
          message: result.message,
        );
      }

      if (platform != LocalRuntimePlatform.windows) {
        return const LocalModelCheckResult(success: true, message: '模型文件已下载。');
      }

      final exeFile = File(p.join(_modelDir, 'llama-server.exe'));
      if (!await exeFile.exists()) {
        return const LocalModelCheckResult(
          success: false,
          message: 'llama-server 缺失，无法启动本地翻译服务。',
        );
      }

      return const LocalModelCheckResult(
        success: true,
        message: '翻译模型文件完整，可启动本地翻译服务。',
      );
    } catch (error) {
      await AppRunLogService.instance.logError('检查翻译模型可用性失败: $error');
      return LocalModelCheckResult(success: false, message: '检查失败：$error');
    }
  }

  Future<void> downloadModel({bool useMirror = false}) async {
    return _downloadModelWithResumableDownloader(useMirror: useMirror);
  }

  Future<void> _downloadModelWithResumableDownloader({
    bool useMirror = false,
  }) async {
    if (state.isDownloading) {
      return;
    }
    try {
      await ensureInitialized();

      final dir = Directory(_modelDir);
      await dir.create(recursive: true);

      if (_platformResolver() == LocalRuntimePlatform.windows) {
        await _prepareWindowsRuntime();
      }

      final modelFile = File(p.join(_modelDir, savedModelFileName));
      final partFile = File('${modelFile.path}.part');
      if (await modelFile.exists()) {
        await _downloadTaskStore.markCompleted(
          kind: DownloadTaskKind.translationModel,
          modelId: taskModelId,
          source: 'local',
          finalPath: modelFile.path,
        );
        await _refreshState();
        return;
      }

      state = state.copyWith(
        isDownloading: true,
        downloadProgress: 0,
        statusText: 'Preparing translation model download...',
      );
      await AppRunLogService.instance.logInfo(
        'Starting translation model download; preferred source: ${useMirror ? 'mirror' : 'official'}',
      );

      try {
        final downloadResult = await _downloader.download(
          kind: DownloadTaskKind.translationModel,
          modelId: taskModelId,
          candidates: _downloadCandidatesBuilder(useMirror: useMirror),
          tempFile: partFile,
          finalPath: modelFile.path,
          onStatus: (message) {
            state = state.copyWith(isDownloading: true, statusText: message);
            unawaited(
              AppRunLogService.instance.logInfo(
                'Translation model download status: $message',
              ),
            );
          },
          onProgress: (progress) {
            if (!_shouldPublishProgress(progress.progress)) {
              return;
            }
            state = state.copyWith(
              isDownloading: true,
              downloadProgress: progress.progress,
              modelSize: progress.totalBytes > 0
                  ? _formatSize(progress.totalBytes)
                  : state.modelSize,
              statusText: progress.totalBytes > 0
                  ? 'Downloading translation model ${_formatSize(progress.downloadedBytes)} / ${_formatSize(progress.totalBytes)}'
                  : 'Downloading translation model ${_formatSize(progress.downloadedBytes)}',
            );
          },
        );
        await _finalizeDownloadedModel(
          source: downloadResult.source,
          partFile: partFile,
          finalFile: modelFile,
        );
        await AppRunLogService.instance.logInfo(
          'Translation model download pipeline finished.',
        );
        await _refreshState();
      } catch (error) {
        await AppRunLogService.instance.logError(
          'Translation model download failed: $error',
        );
        try {
          await _refreshState();
        } catch (_) {}
        state = state.copyWith(
          isDownloading: false,
          statusText: 'Download failed: $error',
        );
      }
    } catch (error) {
      await AppRunLogService.instance.logError(
        'Translation model download setup failed: $error',
      );
      state = state.copyWith(
        isDownloading: false,
        statusText: 'Download failed: $error',
      );
    }
  }

  // ignore: unused_element
  Future<void> _downloadModelWithResume({bool useMirror = false}) async {
    if (state.isDownloading) {
      return;
    }
    await ensureInitialized();

    final dir = Directory(_modelDir);
    await dir.create(recursive: true);

    if (_platformResolver() == LocalRuntimePlatform.windows) {
      await _prepareWindowsRuntime();
    }

    final modelFile = File(p.join(_modelDir, savedModelFileName));
    final partFile = File('${modelFile.path}.part');
    if (await modelFile.exists()) {
      await _downloadTaskStore.markCompleted(
        kind: DownloadTaskKind.translationModel,
        modelId: taskModelId,
        source: 'local',
        finalPath: modelFile.path,
      );
      await _refreshState();
      return;
    }

    state = state.copyWith(
      isDownloading: true,
      downloadProgress: 0,
      statusText: '准备下载翻译模型…',
    );
    await AppRunLogService.instance.logInfo(
      '开始下载翻译模型，优先源=${useMirror ? '镜像' : '官方'}',
    );

    try {
      final source = await _downloadFileWithFallback(
        candidates: downloadCandidates(useMirror: useMirror),
        tempFile: partFile,
        finalFile: modelFile,
        progressLabel: '下载翻译模型',
      );
      await _finalizeDownloadedModel(
        source: source,
        partFile: partFile,
        finalFile: modelFile,
      );
      await AppRunLogService.instance.logInfo('翻译模型下载流程完成');
      await _refreshState();
    } catch (error) {
      await _downloadTaskStore.markFailed(
        kind: DownloadTaskKind.translationModel,
        modelId: taskModelId,
        source: useMirror ? 'mirror' : 'official',
        tempPath: partFile.path,
        finalPath: modelFile.path,
        error: error.toString(),
      );
      await _safeDelete(partFile);
      await AppRunLogService.instance.logError('翻译模型下载异常：$error');
      state = state.copyWith(isDownloading: false, statusText: '下载失败：$error');
    }
  }

  Future<void> _finalizeDownloadedModel({
    required String source,
    required File partFile,
    required File finalFile,
  }) async {
    try {
      await _replaceFile(partFile, finalFile);
      await _downloadTaskStore.markCompleted(
        kind: DownloadTaskKind.translationModel,
        modelId: taskModelId,
        source: source,
        finalPath: finalFile.path,
      );
    } catch (error) {
      await _downloadTaskStore.markStaged(
        kind: DownloadTaskKind.translationModel,
        modelId: taskModelId,
        source: source,
        stagedPath: partFile.path,
        finalPath: finalFile.path,
        error: '下载已完成，等待切换：$error',
      );
    }
  }

  Future<void> _prepareWindowsRuntime() async {
    state = state.copyWith(statusText: '准备 llama-server…');
    final exeFile = File(p.join(_modelDir, runtimeExecutableFileName));
    if (await exeFile.exists()) {
      return;
    }

    final archiveFile = File(p.join(_modelDir, runtimeArchiveFileName));
    final archivePartFile = File('${archiveFile.path}.part');
    const downloadUrl = 'runtime';
    await AppRunLogService.instance.logInfo('下载 llama-server：$downloadUrl');

    if (await archiveFile.exists()) {
      await _extractWindowsRuntimeArchive(
        archiveFile: archiveFile,
        exeFile: exeFile,
      );
      if (await exeFile.exists()) {
        await _downloadTaskStore.markCompleted(
          kind: DownloadTaskKind.translationModel,
          modelId: runtimeTaskModelId,
          source: 'local',
          finalPath: exeFile.path,
        );
        return;
      }
    }

    final resolvedUrl = await _serverDownloadUrlResolver();
    final candidates = <String>[
      resolvedUrl,
      if (resolvedUrl != fallbackServerUrl) fallbackServerUrl,
    ];
    await AppRunLogService.instance.logInfo(
      '下载 llama-server: ${candidates.join(', ')}',
    );
    final result = await _downloader.download(
      kind: DownloadTaskKind.translationModel,
      modelId: runtimeTaskModelId,
      candidates: candidates,
      tempFile: archivePartFile,
      finalPath: exeFile.path,
      onStatus: (message) {
        state = state.copyWith(isDownloading: true, statusText: message);
        unawaited(
          AppRunLogService.instance.logInfo('llama-server 下载: $message'),
        );
      },
      onProgress: (progress) {
        if (!_shouldPublishProgress(progress.progress)) {
          return;
        }
        state = state.copyWith(
          isDownloading: true,
          downloadProgress: progress.progress,
          modelSize: progress.totalBytes > 0
              ? _formatSize(progress.totalBytes)
              : state.modelSize,
          statusText: progress.totalBytes > 0
              ? '下载 llama-server ${_formatSize(progress.downloadedBytes)} / ${_formatSize(progress.totalBytes)}'
              : '下载 llama-server ${_formatSize(progress.downloadedBytes)}',
        );
      },
    );
    await _replaceFile(archivePartFile, archiveFile);

    await _extractWindowsRuntimeArchive(
      archiveFile: archiveFile,
      exeFile: exeFile,
    );
    await _downloadTaskStore.markCompleted(
      kind: DownloadTaskKind.translationModel,
      modelId: runtimeTaskModelId,
      source: result.source,
      finalPath: exeFile.path,
    );

    if (!await exeFile.exists()) {
      throw Exception('下载包内未找到 llama-server.exe');
    }

    if (await archiveFile.exists()) {
      await archiveFile.delete();
    }
  }

  static Future<String> _resolveServerDownloadUrl() async {
    const apiUrl =
        'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest';
    try {
      final response = await http.get(
        Uri.parse(apiUrl),
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'WenwenTome/1.0',
        },
      );
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final assets = json['assets'] as List<dynamic>? ?? const <dynamic>[];
        for (final asset in assets) {
          final item = Map<String, dynamic>.from(asset as Map);
          final name = item['name'] as String? ?? '';
          if (name.contains('bin-win-cpu-x64')) {
            final url = item['browser_download_url'] as String?;
            if (url != null && url.isNotEmpty) {
              return url;
            }
          }
        }
      }
    } catch (error) {
      await AppRunLogService.instance.logError('解析 llama.cpp 最新发布失败：$error');
    }
    return fallbackServerUrl;
  }

  Future<String> _downloadFileWithFallback({
    required List<String> candidates,
    required File tempFile,
    required File finalFile,
    required String progressLabel,
  }) async {
    Object? lastError;
    for (final url in candidates) {
      final client = http.Client();
      IOSink? sink;
      var downloaded = 0;
      var totalBytes = 0;
      try {
        await _safeDelete(tempFile);
        await _downloadTaskStore.markQueued(
          kind: DownloadTaskKind.translationModel,
          modelId: taskModelId,
          source: url,
          tempPath: tempFile.path,
          finalPath: finalFile.path,
        );
        await AppRunLogService.instance.logInfo('尝试下载地址：$url');
        final response = await client.send(
          http.Request('GET', Uri.parse(url))
            ..headers['User-Agent'] = 'WenwenTome/1.0',
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('HTTP ${response.statusCode}');
        }

        totalBytes = response.contentLength ?? 0;
        sink = tempFile.openWrite();
        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloaded += chunk.length;
          await _downloadTaskStore.markProgress(
            kind: DownloadTaskKind.translationModel,
            modelId: taskModelId,
            source: url,
            tempPath: tempFile.path,
            finalPath: finalFile.path,
            downloadedBytes: downloaded,
            totalBytes: totalBytes,
          );
          state = state.copyWith(
            isDownloading: true,
            downloadProgress: totalBytes > 0
                ? downloaded / totalBytes
                : state.downloadProgress,
            statusText: totalBytes > 0
                ? '$progressLabel ${_formatSize(downloaded)} / ${_formatSize(totalBytes)}'
                : '$progressLabel ${_formatSize(downloaded)}',
          );
        }
        await sink.close();
        sink = null;
        await AppRunLogService.instance.logInfo('下载成功：$url');
        return url;
      } catch (error) {
        lastError = error;
        await AppRunLogService.instance.logError('下载失败：$url; $error');
        await sink?.close();
        await _downloadTaskStore.markFailed(
          kind: DownloadTaskKind.translationModel,
          modelId: taskModelId,
          source: url,
          tempPath: tempFile.path,
          finalPath: finalFile.path,
          error: error.toString(),
          downloadedBytes: downloaded,
          totalBytes: totalBytes,
        );
        await _safeDelete(tempFile);
      } finally {
        client.close();
      }
    }

    throw Exception('所有下载地址都失败了：$lastError');
  }

  Future<void> startServer() async {
    await ensureInitialized();
    if (state.isRunning || !state.isDownloaded) {
      return;
    }

    final activeOperation = _startServerOperation;
    if (activeOperation != null) {
      await activeOperation;
      return;
    }

    final completer = Completer<void>();
    _startServerOperation = completer.future;

    try {
      final platform = _platformResolver();
      final executor = _effectiveLocalExecutor;
      if (platform == LocalRuntimePlatform.android && executor != null) {
        state = state.copyWith(statusText: '正在预热 Android 本地翻译模型…');
        try {
          final result = await executor.prepare().timeout(
            _androidPrepareTimeout,
          );
          state = state.copyWith(
            isRunning: result.success,
            statusText: result.message,
          );
        } on TimeoutException {
          await AppRunLogService.instance.logError('Android 本地翻译模型预热超时');
          state = state.copyWith(
            isRunning: false,
            statusText: 'Android 本地翻译模型预热超时，请稍后重试',
          );
        } catch (error) {
          await AppRunLogService.instance.logError(
            'Android 本地翻译模型预热失败: $error',
          );
          state = state.copyWith(
            isRunning: false,
            statusText: 'Android 本地翻译模型加载失败: $error',
          );
        }
        return;
      }

      if (platform != LocalRuntimePlatform.windows) {
        state = state.copyWith(statusText: '当前平台不支持本地翻译服务启动');
        await AppRunLogService.instance.logInfo('移动端跳过本地翻译服务启动');
        return;
      }

      state = state.copyWith(statusText: '正在启动翻译服务…');
      await AppRunLogService.instance.logInfo('开始启动翻译模型推理服务');

      try {
        _serverProcess = await Process.start(
          p.join(_modelDir, 'llama-server.exe'),
          [
            '-m',
            p.join(_modelDir, savedModelFileName),
            '--port',
            '11434',
            '-c',
            '4096',
          ],
          runInShell: true,
        );

        _serverProcess!.stdout.transform(utf8.decoder).listen((data) {
          if (data.contains('HTTP server listening')) {
            AppRunLogService.instance.logInfo('翻译模型服务启动成功，端口 11434');
            state = state.copyWith(isRunning: true, statusText: '服务运行中（11434）');
          }
        });

        _serverProcess!.stderr.transform(utf8.decoder).listen((data) {
          if (data.contains('llama_new_context_with_model')) {
            AppRunLogService.instance.logInfo('翻译模型服务加载完成');
            state = state.copyWith(isRunning: true, statusText: '服务运行中（11434）');
          }
        });
      } catch (error) {
        await AppRunLogService.instance.logError('翻译模型服务启动失败：$error');
        state = state.copyWith(statusText: '启动失败：$error');
      }
    } finally {
      if (!completer.isCompleted) {
        completer.complete();
      }
      if (identical(_startServerOperation, completer.future)) {
        _startServerOperation = null;
      }
    }
  }

  Future<void> stopServer() async {
    if (_serverProcess != null) {
      _serverProcess!.kill();
      _serverProcess = null;
      await AppRunLogService.instance.logInfo('翻译模型服务已停止');
      state = state.copyWith(isRunning: false, statusText: '已停止');
      return;
    }

    final executor = _effectiveLocalExecutor;
    if (_platformResolver() == LocalRuntimePlatform.android &&
        executor != null) {
      await executor.dispose();
      await AppRunLogService.instance.logInfo('Android 本地翻译模型已卸载');
      state = state.copyWith(isRunning: false, statusText: '已停止');
    }
  }

  Future<void> deleteFiles() async {
    await ensureInitialized();
    await stopServer();
    final dir = Directory(_modelDir);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await _downloadTaskStore.remove(
      DownloadTaskKind.translationModel,
      taskModelId,
    );
    await _downloadTaskStore.remove(
      DownloadTaskKind.translationModel,
      runtimeTaskModelId,
    );
    await AppRunLogService.instance.logInfo('翻译模型文件已删除');
    state = const LocalModelState(
      isDownloaded: false,
      isRunning: false,
      modelSize: '未知',
      downloadProgress: 0,
      statusText: '已删除',
    );
  }

  Future<void> _extractWindowsRuntimeArchive({
    required File archiveFile,
    required File exeFile,
  }) async {
    final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
    for (final file in archive) {
      if (!file.isFile) {
        continue;
      }
      final fileName = p.basename(file.name).toLowerCase();
      if (fileName == runtimeExecutableFileName) {
        await exeFile.writeAsBytes(file.content as List<int>, flush: true);
        break;
      }
    }

    if (!await exeFile.exists()) {
      throw Exception('下载包内未找到 $runtimeExecutableFileName');
    }
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) {
      return '未知';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _replaceFile(File source, File destination) async {
    await destination.parent.create(recursive: true);
    final backup = File('${destination.path}.bak');
    var movedExistingToBackup = false;

    if (await backup.exists()) {
      await _safeDelete(backup);
    }
    if (await destination.exists()) {
      await destination.rename(backup.path);
      movedExistingToBackup = true;
    }
    try {
      await source.rename(destination.path);
    } on FileSystemException {
      try {
        await source.copy(destination.path);
        await source.delete();
      } catch (_) {
        if (movedExistingToBackup &&
            !await destination.exists() &&
            await backup.exists()) {
          await backup.rename(destination.path);
        }
        rethrow;
      }
    } catch (_) {
      if (movedExistingToBackup &&
          !await destination.exists() &&
          await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }

    if (await backup.exists()) {
      await _safeDelete(backup);
    }
  }

  Future<void> _safeDelete(File file) async {
    if (!await file.exists()) {
      return;
    }
    try {
      await file.delete();
    } catch (_) {
      // Keep staged/temporary files for the next retry or promotion attempt.
    }
  }
}

final localModelProvider =
    NotifierProvider<LocalModelNotifier, LocalModelState>(
      LocalModelNotifier.new,
    );
