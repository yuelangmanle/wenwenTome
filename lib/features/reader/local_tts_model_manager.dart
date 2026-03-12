import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart' as archive_io;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../app/runtime_platform.dart';
import '../../core/downloads/download_task_store.dart';
import '../../core/downloads/single_connection_resumable_downloader.dart';
import '../../core/storage/app_storage_paths.dart';
import '../logging/app_run_log_service.dart';

enum SherpaTtsModelKind { vits, kokoro }

class TtsParamDef {
  const TtsParamDef({
    required this.key,
    required this.label,
    required this.type,
    required this.defaultValue,
    required this.min,
    required this.max,
    this.divisions = 10,
    this.precision = 2,
  });

  final String key;
  final String label;
  final String type;
  final double defaultValue;
  final double min;
  final double max;
  final int divisions;
  final int precision;
}

class SherpaPackageDownloadPlan {
  const SherpaPackageDownloadPlan({
    required this.directoryName,
    required this.officialPackageUrl,
    required this.mirrorPackageUrls,
  });

  final String directoryName;
  final String officialPackageUrl;
  final List<String> mirrorPackageUrls;

  List<String> candidates({required bool preferMirror}) {
    final ordered = <String>[
      if (preferMirror) ...mirrorPackageUrls,
      officialPackageUrl,
      if (!preferMirror) ...mirrorPackageUrls,
    ];
    final seen = <String>{};
    return ordered.where(seen.add).toList();
  }
}

class SherpaTtsModelManifest {
  const SherpaTtsModelManifest({
    required this.kind,
    required this.directoryName,
    required this.officialPackageUrl,
    required this.mirrorPackageUrls,
    required this.modelFileName,
    this.bundledAssetPrefix,
    this.tokensFileName = 'tokens.txt',
    this.lexiconFileNames = const <String>[],
    this.dataDirName,
    this.voicesFileName,
    this.ruleFstFiles = const <String>[],
    this.defaultSpeakerId = 0,
    this.maxSpeakerId = 0,
    this.languageCode = '',
  });

  final SherpaTtsModelKind kind;
  final String directoryName;
  final String officialPackageUrl;
  final List<String> mirrorPackageUrls;
  final String modelFileName;
  final String? bundledAssetPrefix;
  final String tokensFileName;
  final List<String> lexiconFileNames;
  final String? dataDirName;
  final String? voicesFileName;
  final List<String> ruleFstFiles;
  final int defaultSpeakerId;
  final int maxSpeakerId;
  final String languageCode;

  SherpaPackageDownloadPlan toDownloadPlan() {
    return SherpaPackageDownloadPlan(
      directoryName: directoryName,
      officialPackageUrl: officialPackageUrl,
      mirrorPackageUrls: mirrorPackageUrls,
    );
  }

  List<String> get requiredPaths => <String>[
    modelFileName,
    tokensFileName,
    ...lexiconFileNames,
    ...?voicesFileName == null ? null : <String>[voicesFileName!],
    ...?dataDirName == null ? null : <String>[dataDirName!],
    ...ruleFstFiles,
  ];
}

class TtsModelConfig {
  const TtsModelConfig({
    required this.id,
    required this.name,
    required this.size,
    required this.description,
    required this.sherpaManifest,
    this.isBuiltIn = false,
    this.paramDefs = const <TtsParamDef>[],
    this.supportedPlatforms = const <LocalRuntimePlatform>[
      LocalRuntimePlatform.windows,
      LocalRuntimePlatform.android,
    ],
  });

  final String id;
  final String name;
  final String size;
  final String description;
  final bool isBuiltIn;
  final List<TtsParamDef> paramDefs;
  final List<LocalRuntimePlatform> supportedPlatforms;
  final SherpaTtsModelManifest sherpaManifest;

  bool supportsPlatform(LocalRuntimePlatform platform) {
    return supportedPlatforms.contains(platform);
  }
}

class TtsModelCheckResult {
  const TtsModelCheckResult({required this.success, required this.message});

  final bool success;
  final String message;
}

class LocalTtsModelManager {
  LocalTtsModelManager({
    DownloadTaskStore? downloadTaskStore,
    Future<Directory> Function()? appSupportDirProvider,
    SingleConnectionResumableDownloader? downloader,
  }) : _downloadTaskStore = _resolveDownloadTaskStore(
         downloadTaskStore: downloadTaskStore,
         appSupportDirProvider: appSupportDirProvider,
       ),
       _appSupportDirProvider =
           appSupportDirProvider ?? getSafeApplicationSupportDirectory,
       _downloader =
           downloader ??
           SingleConnectionResumableDownloader(
             downloadTaskStore: _resolveDownloadTaskStore(
               downloadTaskStore: downloadTaskStore,
               appSupportDirProvider: appSupportDirProvider,
             ),
           );

  static const piperModelId = 'piper_zh';
  static const kokoroModelId = 'kokoro_zh_en';
  static const aishell3ModelId = 'aishell3_zh';
  static const meloModelId = 'melo_zh_en';

  static const _piperParams = <TtsParamDef>[
    TtsParamDef(
      key: 'speed',
      label: '语速',
      type: 'slider',
      defaultValue: 1.0,
      min: 0.7,
      max: 1.5,
      divisions: 16,
    ),
    TtsParamDef(
      key: 'noiseScale',
      label: '情感浮动',
      type: 'slider',
      defaultValue: 0.67,
      min: 0.3,
      max: 1.2,
      divisions: 18,
    ),
    TtsParamDef(
      key: 'noiseW',
      label: '音素扰动',
      type: 'slider',
      defaultValue: 0.8,
      min: 0.1,
      max: 1.0,
      divisions: 18,
    ),
    TtsParamDef(
      key: 'sentenceSilence',
      label: '句间停顿',
      type: 'slider',
      defaultValue: 0.2,
      min: 0.0,
      max: 1.0,
      divisions: 20,
    ),
  ];

  static const _kokoroParams = <TtsParamDef>[
    TtsParamDef(
      key: 'speed',
      label: '语速',
      type: 'slider',
      defaultValue: 1.0,
      min: 0.6,
      max: 1.4,
      divisions: 16,
    ),
    TtsParamDef(
      key: 'sentenceSilence',
      label: '句间停顿',
      type: 'slider',
      defaultValue: 0.15,
      min: 0.0,
      max: 0.8,
      divisions: 16,
    ),
    TtsParamDef(
      key: 'speakerId',
      label: '音色编号',
      type: 'slider',
      defaultValue: 42,
      min: 0,
      max: 102,
      divisions: 102,
      precision: 0,
    ),
  ];

  static const _aishell3Params = <TtsParamDef>[
    TtsParamDef(
      key: 'speed',
      label: '语速',
      type: 'slider',
      defaultValue: 1.0,
      min: 0.6,
      max: 1.5,
      divisions: 18,
    ),
    TtsParamDef(
      key: 'sentenceSilence',
      label: '句间停顿',
      type: 'slider',
      defaultValue: 0.2,
      min: 0.0,
      max: 0.8,
      divisions: 16,
    ),
    TtsParamDef(
      key: 'speakerId',
      label: '音色编号',
      type: 'slider',
      defaultValue: 10,
      min: 0,
      max: 173,
      divisions: 173,
      precision: 0,
    ),
  ];

  static const _meloParams = <TtsParamDef>[
    TtsParamDef(
      key: 'speed',
      label: '语速',
      type: 'slider',
      defaultValue: 1.0,
      min: 0.7,
      max: 1.4,
      divisions: 14,
    ),
    TtsParamDef(
      key: 'sentenceSilence',
      label: '句间停顿',
      type: 'slider',
      defaultValue: 0.15,
      min: 0.0,
      max: 0.8,
      divisions: 16,
    ),
  ];

  static const List<TtsModelConfig> availableModels = <TtsModelConfig>[
    TtsModelConfig(
      id: piperModelId,
      name: 'Piper 中文标准',
      size: '63.2 MB（内置）',
      description: '内置离线旁白模型，启动最快，适合长时间后台听书。',
      isBuiltIn: true,
      paramDefs: _piperParams,
      sherpaManifest: SherpaTtsModelManifest(
        kind: SherpaTtsModelKind.vits,
        directoryName: 'vits-piper-zh_CN-huayan-medium',
        officialPackageUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-huayan-medium.tar.bz2',
        mirrorPackageUrls: <String>[
          'https://mirror.ghproxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-zh_CN-huayan-medium.tar.bz2',
        ],
        bundledAssetPrefix: 'assets/local_tts/vits-piper-zh_CN-huayan-medium',
        modelFileName: 'zh_CN-huayan-medium.onnx',
        tokensFileName: 'tokens.txt',
        dataDirName: 'espeak-ng-data',
      ),
    ),
    TtsModelConfig(
      id: kokoroModelId,
      name: 'Kokoro 中英多音色',
      size: '约 180 MB',
      description: '103 个中英双语音色，适合追求更高质感和多角色切换。',
      isBuiltIn: false,
      paramDefs: _kokoroParams,
      sherpaManifest: SherpaTtsModelManifest(
        kind: SherpaTtsModelKind.kokoro,
        directoryName: 'kokoro-int8-multi-lang-v1_1',
        officialPackageUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_1.tar.bz2',
        mirrorPackageUrls: <String>[
          'https://mirror.ghproxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-multi-lang-v1_1.tar.bz2',
        ],
        bundledAssetPrefix: 'assets/local_tts/kokoro-int8-multi-lang-v1_1',
        modelFileName: 'model.int8.onnx',
        tokensFileName: 'tokens.txt',
        voicesFileName: 'voices.bin',
        lexiconFileNames: <String>['lexicon-us-en.txt', 'lexicon-zh.txt'],
        dataDirName: 'espeak-ng-data',
        ruleFstFiles: <String>['phone-zh.fst', 'date-zh.fst', 'number-zh.fst'],
        defaultSpeakerId: 42,
        maxSpeakerId: 102,
      ),
    ),
    TtsModelConfig(
      id: aishell3ModelId,
      name: 'Aishell3 中文多音色',
      size: '约 35 MB',
      description: '174 个中文说话人，适合多角色和群像朗读。',
      isBuiltIn: false,
      paramDefs: _aishell3Params,
      sherpaManifest: SherpaTtsModelManifest(
        kind: SherpaTtsModelKind.vits,
        directoryName: 'vits-icefall-zh-aishell3',
        officialPackageUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-icefall-zh-aishell3.tar.bz2',
        mirrorPackageUrls: <String>[
          'https://mirror.ghproxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-icefall-zh-aishell3.tar.bz2',
        ],
        bundledAssetPrefix: 'assets/local_tts/vits-icefall-zh-aishell3',
        modelFileName: 'model.onnx',
        tokensFileName: 'tokens.txt',
        lexiconFileNames: <String>['lexicon.txt'],
        ruleFstFiles: <String>['phone.fst', 'date.fst', 'number.fst'],
        defaultSpeakerId: 10,
        maxSpeakerId: 173,
      ),
    ),
    TtsModelConfig(
      id: meloModelId,
      name: 'MeloTTS 中英混读',
      size: '绾?170 MB',
      description: '中英混读更稳，适合书里夹杂英文名词和术语的场景。',
      paramDefs: _meloParams,
      sherpaManifest: SherpaTtsModelManifest(
        kind: SherpaTtsModelKind.vits,
        directoryName: 'vits-melo-tts-zh_en',
        officialPackageUrl:
            'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-melo-tts-zh_en.tar.bz2',
        mirrorPackageUrls: <String>[
          'https://mirror.ghproxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-melo-tts-zh_en.tar.bz2',
        ],
        modelFileName: 'model.onnx',
        tokensFileName: 'tokens.txt',
        lexiconFileNames: <String>['lexicon.txt'],
        ruleFstFiles: <String>['phone.fst', 'date.fst', 'number.fst'],
      ),
    ),
  ];

  final DownloadTaskStore _downloadTaskStore;
  final Future<Directory> Function() _appSupportDirProvider;
  final SingleConnectionResumableDownloader _downloader;
  final Map<String, double> _progressByModel = <String, double>{};

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

  static TtsModelConfig? getModelById(String modelId) {
    for (final model in availableModels) {
      if (model.id == modelId) {
        return model;
      }
    }
    return null;
  }

  static List<String> downloadCandidates(
    TtsModelConfig model, {
    bool preferMirror = true,
  }) {
    if (model.isBuiltIn) {
      return const <String>[];
    }
    return model.sherpaManifest.toDownloadPlan().candidates(
      preferMirror: preferMirror,
    );
  }

  static SherpaPackageDownloadPlan resolveDownloadPlan(
    TtsModelConfig model, {
    bool preferMirror = true,
  }) {
    return model.sherpaManifest.toDownloadPlan();
  }

  static SherpaPackageDownloadPlan resolveAndroidDownloadPlan(
    TtsModelConfig model, {
    bool preferMirror = true,
  }) {
    return resolveDownloadPlan(model, preferMirror: preferMirror);
  }

  Future<void> hydrateDownloadTasks() async {
    await _downloadTaskStore.ensureInitialized();
    await _downloadTaskStore.markStaleActiveTasksAsFailed();
    for (final model in availableModels) {
      await _promoteStagedModelIfPossible(model);
    }
  }

  Future<Directory> _rootDir() async {
    final supportDir = await _appSupportDirProvider();
    final dir = Directory(p.join(supportDir.path, 'wenwen_tome', 'local_tts'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _installedModelDir(TtsModelConfig model) async {
    final root = await _rootDir();
    final dir = Directory(p.join(root.path, model.id));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> _downloadArchiveFile(TtsModelConfig model) async {
    final root = await _rootDir();
    return File(p.join(root.path, '${model.id}.tar.bz2.part'));
  }

  Future<Directory> _stagedModelDir(TtsModelConfig model) async {
    final root = await _rootDir();
    return Directory(p.join(root.path, '.staged_${model.id}'));
  }

  Future<Directory?> resolveSherpaModelDir(String modelId) async {
    final model = getModelById(modelId);
    if (model == null) {
      return null;
    }

    final platform = detectLocalRuntimePlatform();
    if (!model.supportsPlatform(platform)) {
      return null;
    }

    await _downloadTaskStore.ensureInitialized();
    final dir = await _installedModelDir(model);
    if (model.isBuiltIn) {
      await _ensureBundledAssets(model, dir);
    } else {
      await _promoteStagedModelIfPossible(model);
    }

    return await _hasSherpaBundle(model, dir) ? dir : null;
  }

  Future<TtsModelCheckResult> checkAvailability(String modelId) async {
    try {
      final model = getModelById(modelId);
      if (model == null) {
        return const TtsModelCheckResult(
          success: false,
          message: '未知的本地 TTS 模型。',
        );
      }

      final platform = detectLocalRuntimePlatform();
      if (!model.supportsPlatform(platform)) {
        return TtsModelCheckResult(
          success: false,
          message: '当前平台暂不支持 ${model.name}。',
        );
      }

      final bundleDir = await resolveSherpaModelDir(modelId);
      final task = await _downloadTaskStore.getTask(
        DownloadTaskKind.ttsModel,
        modelId,
      );
      final installed = bundleDir != null;
      if (installed) {
        return TtsModelCheckResult(success: true, message: '可用：${model.name}');
      }
      if (model.isBuiltIn && await _hasBundledAssetsForModel(model)) {
        return TtsModelCheckResult(
          success: true,
          message: '内置模型可用（首次朗读会自动准备）：${model.name}',
        );
      }
      if (task?.status == DownloadTaskStatus.staged) {
        return TtsModelCheckResult(
          success: false,
          message: task?.error?.isNotEmpty == true
              ? task!.error!
              : '模型已下载，等待切换。',
        );
      }
      if (task?.status == DownloadTaskStatus.failed) {
        return TtsModelCheckResult(
          success: false,
          message: '安装失败：${task?.error ?? '请重试'}',
        );
      }
      return const TtsModelCheckResult(success: false, message: '模型文件尚未安装完成。');
    } catch (error) {
      await AppRunLogService.instance.logError(
        '检查本地 TTS 模型失败: $modelId; $error',
      );
      return TtsModelCheckResult(success: false, message: '检查失败：$error');
    }
  }

  Future<void> extractArchiveFile(File zipFile, Directory modelDir) async {
    await modelDir.create(recursive: true);
    final input = archive_io.InputFileStream(zipFile.path);
    /*
    {
      var deletePackageFile = false;
      try {
        await _downloader.download(
          kind: DownloadTaskKind.ttsModel,
          modelId: model.id,
          candidates: plan.candidates(preferMirror: preferMirror),
          tempFile: packageFile,
          finalPath: installDir.path,
          onStatus: (message) {
            unawaited(
              AppRunLogService.instance.logInfo(
                '本地 TTS 模型下载状态: ${model.id}; $message',
              ),
            );
          },
          onProgress: (progress) => onProgress(progress.progress * 0.75),
        );
        if (await stagedDir.exists()) {
          await stagedDir.delete(recursive: true);
        }
        await stagedDir.create(recursive: true);
        await _extractTarBz2ModelArchive(
          archiveFile: packageFile,
          extractedRootName: plan.directoryName,
          installDir: stagedDir,
        );
        if (!await _hasSherpaBundle(model, stagedDir)) {
          throw Exception('安装后的模型文件不完整');
        }
        onProgress(0.95);
        await _activateInstalledDirectory(
          model: model,
          stagedDir: stagedDir,
          installDir: installDir,
          source: preferMirror ? 'mirror' : 'official',
        );
        deletePackageFile = true;
        onProgress(1.0);
        await AppRunLogService.instance.logInfo('本地 TTS 模型安装完成: ${model.id}');
      } finally {
        if (deletePackageFile && await packageFile.exists()) {
          await packageFile.delete();
        }
      }
      return;
    }
    */

    try {
      final archive = ZipDecoder().decodeBuffer(input);
      await archive_io.extractArchiveToDisk(archive, modelDir.path);
    } finally {
      await input.close();
    }
  }

  Stream<double> downloadModel(
    TtsModelConfig model, {
    bool preferMirror = true,
  }) {
    final controller = StreamController<double>();

    () async {
      try {
        await _downloadTaskStore.ensureInitialized();
        if (model.isBuiltIn) {
          final installDir = await _installedModelDir(model);
          await _ensureBundledAssets(model, installDir);
          await _downloadTaskStore.markCompleted(
            kind: DownloadTaskKind.ttsModel,
            modelId: model.id,
            source: 'bundled',
            finalPath: installDir.path,
          );
          _progressByModel[model.id] = 1.0;
          controller
            ..add(1.0)
            ..close();
          return;
        }

        final installDir = await _installedModelDir(model);
        final stagedDir = await _stagedModelDir(model);
        if (await stagedDir.exists()) {
          await stagedDir.delete(recursive: true);
        }
        await _installSherpaModel(
          model,
          installDir: installDir,
          stagedDir: stagedDir,
          preferMirror: preferMirror,
          onProgress: (progress) {
            _progressByModel[model.id] = progress;
            controller.add(progress);
          },
        );
        _progressByModel[model.id] = 1.0;
        controller
          ..add(1.0)
          ..close();
      } catch (error) {
        _progressByModel[model.id] = -1.0;
        await AppRunLogService.instance.logError(
          '本地 TTS 模型下载失败: ${model.id}; $error',
        );
        controller
          ..addError(error)
          ..close();
      }
    }();

    return controller.stream;
  }

  // ignore: unused_element
  Future<void> _downloadFileWithFallback({
    required TtsModelConfig model,
    required List<String> candidates,
    required File targetFile,
    required String finalPath,
    required void Function(double progress) onProgress,
  }) async {
    Object? lastError;

    for (final url in candidates) {
      final client = http.Client();
      IOSink? sink;
      var received = 0;
      var contentLength = 0;
      try {
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
        await _downloadTaskStore.markQueued(
          kind: DownloadTaskKind.ttsModel,
          modelId: model.id,
          source: url,
          tempPath: targetFile.path,
          finalPath: finalPath,
        );
        await AppRunLogService.instance.logInfo('尝试下载 TTS 资源: $url');
        final response = await client.send(
          http.Request('GET', Uri.parse(url))
            ..headers['User-Agent'] = 'WenwenTome/1.0',
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('HTTP ${response.statusCode}');
        }

        contentLength = response.contentLength ?? 0;
        sink = targetFile.openWrite();
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          await _downloadTaskStore.markProgress(
            kind: DownloadTaskKind.ttsModel,
            modelId: model.id,
            source: url,
            tempPath: targetFile.path,
            finalPath: finalPath,
            downloadedBytes: received,
            totalBytes: contentLength,
          );
          if (contentLength > 0) {
            onProgress(received / contentLength);
          }
        }
        await sink.close();
        sink = null;
        onProgress(1.0);
        await AppRunLogService.instance.logInfo('TTS 资源下载成功: $url');
        return;
      } catch (error) {
        lastError = error;
        await AppRunLogService.instance.logError('TTS 资源下载失败: $url; $error');
        await sink?.close();
        await _downloadTaskStore.markFailed(
          kind: DownloadTaskKind.ttsModel,
          modelId: model.id,
          source: url,
          tempPath: targetFile.path,
          finalPath: finalPath,
          error: error.toString(),
          downloadedBytes: received,
          totalBytes: contentLength,
        );
        if (await targetFile.exists()) {
          await targetFile.delete();
        }
      } finally {
        client.close();
      }
    }

    throw Exception('所有下载源都失败了：$lastError');
  }

  Future<bool> _hasSherpaBundle(TtsModelConfig model, Directory dir) async {
    for (final relativePath in model.sherpaManifest.requiredPaths) {
      final file = File(p.join(dir.path, relativePath));
      final folder = Directory(p.join(dir.path, relativePath));
      if (!await file.exists() && !await folder.exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _ensureBundledAssets(
    TtsModelConfig model,
    Directory installDir,
  ) async {
    final prefix = model.sherpaManifest.bundledAssetPrefix;
    if (prefix == null || prefix.isEmpty) {
      return;
    }
    if (await _hasSherpaBundle(model, installDir)) {
      return;
    }

    final assets = await _listBundledAssets(prefix);

    for (final asset in assets) {
      final relativePath = asset.substring(prefix.length + 1);
      if (!_isRequiredBundledAsset(model, relativePath)) {
        continue;
      }
      final data = await rootBundle.load(asset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final outFile = File(p.join(installDir.path, relativePath));
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(bytes, flush: true);
    }
  }

  bool _isRequiredBundledAsset(TtsModelConfig model, String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    for (final requiredPath in model.sherpaManifest.requiredPaths) {
      final requiredNormalized = requiredPath.replaceAll('\\', '/');
      if (normalized == requiredNormalized ||
          normalized.startsWith('$requiredNormalized/')) {
        return true;
      }
    }
    return false;
  }

  Future<List<String>> _listBundledAssets(String prefix) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets =
        manifest
            .listAssets()
            .where((key) => key.startsWith('$prefix/'))
            .toList(growable: false)
          ..sort();
    return assets;
  }

  Future<bool> _hasBundledAssetsForModel(TtsModelConfig model) async {
    final prefix = model.sherpaManifest.bundledAssetPrefix;
    if (prefix == null || prefix.isEmpty) {
      return false;
    }
    final assets = await _listBundledAssets(prefix);
    if (assets.isEmpty) {
      return false;
    }

    for (final requiredPath in model.sherpaManifest.requiredPaths) {
      final normalized = requiredPath.replaceAll('\\', '/');
      final found = assets.any((asset) {
        final relative = asset.substring(prefix.length + 1);
        return relative == normalized || relative.startsWith('$normalized/');
      });
      if (!found) {
        return false;
      }
    }
    return true;
  }

  Future<void> _installSherpaModel(
    TtsModelConfig model, {
    required Directory installDir,
    required Directory stagedDir,
    required bool preferMirror,
    required void Function(double progress) onProgress,
  }) async {
    return _installSherpaModelWithResume(
      model,
      installDir: installDir,
      stagedDir: stagedDir,
      preferMirror: preferMirror,
      onProgress: onProgress,
    );
  }

  Future<void> _installSherpaModelWithResume(
    TtsModelConfig model, {
    required Directory installDir,
    required Directory stagedDir,
    required bool preferMirror,
    required void Function(double progress) onProgress,
  }) async {
    final plan = model.sherpaManifest.toDownloadPlan();
    final packageFile = await _downloadArchiveFile(model);

    var deletePackageFile = false;
    try {
      await _downloader.download(
        kind: DownloadTaskKind.ttsModel,
        modelId: model.id,
        candidates: plan.candidates(preferMirror: preferMirror),
        tempFile: packageFile,
        finalPath: installDir.path,
        onStatus: (message) {
          unawaited(
            AppRunLogService.instance.logInfo(
              'Local TTS download status: ${model.id}; $message',
            ),
          );
        },
        onProgress: (progress) => onProgress(progress.progress * 0.75),
      );
      if (await stagedDir.exists()) {
        await stagedDir.delete(recursive: true);
      }
      await stagedDir.create(recursive: true);
      await _extractTarBz2ModelArchive(
        archiveFile: packageFile,
        extractedRootName: plan.directoryName,
        installDir: stagedDir,
      );
      if (!await _hasSherpaBundle(model, stagedDir)) {
        throw Exception('安装后的模型文件不完整。');
      }
      onProgress(0.95);
      await _activateInstalledDirectory(
        model: model,
        stagedDir: stagedDir,
        installDir: installDir,
        source: preferMirror ? 'mirror' : 'official',
      );
      deletePackageFile = true;
      onProgress(1.0);
      await AppRunLogService.instance.logInfo('本地 TTS 模型安装完成: ${model.id}');
    } finally {
      if (deletePackageFile && await packageFile.exists()) {
        await packageFile.delete();
      }
    }
    return;

    /*
    try {
      await _downloadFileWithFallback(
        model: model,
        candidates: plan.candidates(preferMirror: preferMirror),
        targetFile: packageFile,
        finalPath: installDir.path,
        onProgress: (progress) => onProgress(progress * 0.75),
      );
      if (await stagedDir.exists()) {
        await stagedDir.delete(recursive: true);
      }
      await stagedDir.create(recursive: true);
      await _extractTarBz2ModelArchive(
        archiveFile: packageFile,
        extractedRootName: plan.directoryName,
        installDir: stagedDir,
      );
      if (!await _hasSherpaBundle(model, stagedDir)) {
        throw Exception('安装后的模型文件不完整。');
      }
      onProgress(0.95);
      await _activateInstalledDirectory(
        model: model,
        stagedDir: stagedDir,
        installDir: installDir,
        source: preferMirror ? 'mirror' : 'official',
      );
      onProgress(1.0);
      await AppRunLogService.instance.logInfo('本地 TTS 模型安装完成: ${model.id}');
    } finally {
      if (await packageFile.exists()) {
        await packageFile.delete();
      }
    }
    */
  }

  Future<void> _extractTarBz2ModelArchive({
    required File archiveFile,
    required String extractedRootName,
    required Directory installDir,
  }) async {
    final tempRoot = Directory(
      p.join(
        installDir.parent.path,
        '.tmp_${extractedRootName}_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await tempRoot.create(recursive: true);
    try {
      final tempTar = File(p.join(tempRoot.path, '$extractedRootName.tar'));
      final input = archive_io.InputFileStream(archiveFile.path);
      final output = archive_io.OutputFileStream(tempTar.path);
      try {
        BZip2Decoder().decodeBuffer(input, output: output);
      } finally {
        await input.close();
        await output.close();
      }

      final tarInput = archive_io.InputFileStream(tempTar.path);
      try {
        final archive = TarDecoder().decodeBuffer(tarInput);
        await archive_io.extractArchiveToDisk(archive, tempRoot.path);
      } finally {
        await tarInput.close();
      }

      final extractedDir = Directory(p.join(tempRoot.path, extractedRootName));
      if (!await extractedDir.exists()) {
        throw Exception('解压后未找到目录: $extractedRootName');
      }
      await _copyDirectoryContents(extractedDir, installDir);
    } finally {
      await _safeDeleteDirectory(tempRoot);
    }
  }

  Future<void> _activateInstalledDirectory({
    required TtsModelConfig model,
    required Directory stagedDir,
    required Directory installDir,
    required String source,
  }) async {
    try {
      await _replaceDirectory(stagedDir, installDir);
      await _downloadTaskStore.markCompleted(
        kind: DownloadTaskKind.ttsModel,
        modelId: model.id,
        source: source,
        finalPath: installDir.path,
      );
    } catch (error) {
      await _downloadTaskStore.markStaged(
        kind: DownloadTaskKind.ttsModel,
        modelId: model.id,
        source: source,
        stagedPath: stagedDir.path,
        finalPath: installDir.path,
        error: '模型已下载，等待切换: $error',
      );
    }
  }

  Future<void> _promoteStagedModelIfPossible(TtsModelConfig model) async {
    final task = await _downloadTaskStore.getTask(
      DownloadTaskKind.ttsModel,
      model.id,
    );
    if (task == null || task.status != DownloadTaskStatus.staged) {
      return;
    }

    final installDir = await _installedModelDir(model);
    final stagedDir = Directory(task.tempPath);
    if (await _hasSherpaBundle(model, installDir)) {
      await _safeDeleteDirectory(stagedDir);
      await _downloadTaskStore.markCompleted(
        kind: DownloadTaskKind.ttsModel,
        modelId: model.id,
        source: task.source,
        finalPath: installDir.path,
      );
      return;
    }

    if (!await stagedDir.exists()) {
      await _downloadTaskStore.markFailed(
        kind: DownloadTaskKind.ttsModel,
        modelId: model.id,
        source: task.source,
        tempPath: task.tempPath,
        finalPath: installDir.path,
        error: '暂存目录丢失，请重新下载',
      );
      return;
    }

    await _activateInstalledDirectory(
      model: model,
      stagedDir: stagedDir,
      installDir: installDir,
      source: task.source,
    );
  }

  Future<void> _copyDirectoryContents(
    Directory source,
    Directory target,
  ) async {
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: true)) {
      final relative = p.relative(entity.path, from: source.path);
      final destPath = p.join(target.path, relative);
      if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      } else if (entity is File) {
        await File(destPath).parent.create(recursive: true);
        await entity.copy(destPath);
      }
    }
  }

  double getProgress(String modelId) => _progressByModel[modelId] ?? 0.0;

  Future<bool> isModelInstalled(String modelId) async {
    final result = await checkAvailability(modelId);
    return result.success;
  }

  Future<void> deleteModel(String modelId) async {
    final model = getModelById(modelId);
    if (model == null || model.isBuiltIn) {
      return;
    }
    final installDir = await _installedModelDir(model);
    if (await installDir.exists()) {
      await installDir.delete(recursive: true);
      await AppRunLogService.instance.logInfo('删除本地 TTS 模型: $modelId');
    }
    final stagedDir = await _stagedModelDir(model);
    await _safeDeleteDirectory(stagedDir);
    final archiveFile = await _downloadArchiveFile(model);
    if (await archiveFile.exists()) {
      await archiveFile.delete();
    }
    await _downloadTaskStore.remove(DownloadTaskKind.ttsModel, modelId);
    _progressByModel.remove(modelId);
  }

  Future<void> _replaceDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.parent.create(recursive: true);
    final backup = Directory('${destination.path}.bak');
    var movedExistingToBackup = false;

    if (await backup.exists()) {
      await _safeDeleteDirectory(backup);
    }
    if (await destination.exists()) {
      await destination.rename(backup.path);
      movedExistingToBackup = true;
    }

    try {
      await source.rename(destination.path);
    } catch (_) {
      if (movedExistingToBackup &&
          !await destination.exists() &&
          await backup.exists()) {
        await backup.rename(destination.path);
      }
      rethrow;
    }

    if (await backup.exists()) {
      await _safeDeleteDirectory(backup);
    }
  }

  Future<void> _safeDeleteDirectory(Directory dir) async {
    if (!await dir.exists()) {
      return;
    }
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // Keep staged content for next launch or manual retry.
    }
  }
}
