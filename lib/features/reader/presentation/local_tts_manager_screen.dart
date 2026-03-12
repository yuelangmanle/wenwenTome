import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/runtime_platform.dart';
import '../../../core/downloads/download_task_store.dart';
import '../../logging/app_run_log_service.dart';
import '../android_tts_engine_service.dart';
import '../local_tts_model_manager.dart';
import '../providers/reader_settings_provider.dart';

class LocalTtsManagerScreen extends ConsumerStatefulWidget {
  const LocalTtsManagerScreen({super.key});

  @override
  ConsumerState<LocalTtsManagerScreen> createState() =>
      _LocalTtsManagerScreenState();
}

class _LocalTtsManagerScreenState extends ConsumerState<LocalTtsManagerScreen> {
  static const _modelCheckTimeout = Duration(seconds: 45);

  final LocalTtsModelManager _manager = LocalTtsModelManager();
  final AndroidTtsEngineService _engineService = AndroidTtsEngineService();

  final Map<String, TtsModelCheckResult> _checkResults =
      <String, TtsModelCheckResult>{};
  final Map<String, bool> _checking = <String, bool>{};

  List<String> _engines = const <String>[];
  List<Map<String, String>> _voices = const <Map<String, String>>[];
  String? _defaultEngine;
  bool _loadingEngines = false;
  bool _loadingVoices = false;
  bool _checkingExternal = false;
  TtsModelCheckResult? _externalCheckResult;

  bool get _isAndroid =>
      detectLocalRuntimePlatform() == LocalRuntimePlatform.android;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    try {
      await _manager.hydrateDownloadTasks();
      for (final model in LocalTtsModelManager.availableModels) {
        await _runCheck(model.id);
      }
      if (_isAndroid) {
        await _loadAndroidEngines();
      }
    } catch (error) {
      await AppRunLogService.instance.logError('初始化 TTS 管理页失败: $error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('初始化 TTS 管理页失败：$error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _runCheck(String modelId) async {
    if (mounted) {
      setState(() => _checking[modelId] = true);
    }
    late final TtsModelCheckResult result;
    try {
      result = await _manager
          .checkAvailability(modelId)
          .timeout(_modelCheckTimeout);
    } on TimeoutException {
      result = const TtsModelCheckResult(
        success: false,
        message: '检测超时，请稍后重试。',
      );
      await AppRunLogService.instance.logError('TTS 模型检测超时: $modelId');
    } catch (error) {
      result = TtsModelCheckResult(success: false, message: '检测失败: $error');
      await AppRunLogService.instance.logError('TTS 模型检测失败: $modelId; $error');
    }
    await AppRunLogService.instance.logInfo(
      'TTS 检测结果 $modelId; success=${result.success}; ${result.message}',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _checkResults[modelId] = result;
      _checking[modelId] = false;
    });
  }

  Future<void> _download(TtsModelConfig model, bool preferMirror) async {
    StreamSubscription<double>? subscription;
    try {
      subscription = _manager
          .downloadModel(model, preferMirror: preferMirror)
          .listen((_) {});
      await subscription.asFuture<void>();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${model.name} 安装完成')));
    } catch (error) {
      await AppRunLogService.instance.logError(
        '下载本地 TTS 模型失败: ${model.id}; $error',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('下载失败: $error')));
    } finally {
      await subscription?.cancel();
      await _runCheck(model.id);
    }
  }

  Future<void> _delete(TtsModelConfig model) async {
    await _manager.deleteModel(model.id);
    await _runCheck(model.id);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除 ${model.name}')));
  }

  Future<void> _loadAndroidEngines() async {
    if (!_isAndroid || _loadingEngines) {
      return;
    }

    setState(() => _loadingEngines = true);
    try {
      final settings = ref.read(readerSettingsProvider);
      final engines = await _engineService.getEngines();
      final defaultEngine = await _engineService.getDefaultEngine();
      final selectedEngine = _pickSelectedEngine(
        savedEngine: settings.androidExternalTtsEngine,
        engines: engines,
        defaultEngine: defaultEngine,
      );
      final voices = selectedEngine == null
          ? const <Map<String, String>>[]
          : await _engineService.getVoices(engine: selectedEngine);

      if (!mounted) {
        return;
      }
      setState(() {
        _engines = engines;
        _defaultEngine = defaultEngine;
        _voices = voices;
        _loadingEngines = false;
      });

      if (selectedEngine != null &&
          settings.androidExternalTtsEngine != selectedEngine) {
        ref
            .read(readerSettingsProvider.notifier)
            .setAndroidExternalTtsEngine(selectedEngine);
      }
      await _ensureVoiceSelection(selectedEngine, voices);
    } catch (error) {
      await AppRunLogService.instance.logError('加载 Android TTS 引擎失败: $error');
      if (!mounted) {
        return;
      }
      setState(() => _loadingEngines = false);
    }
  }

  String? _pickSelectedEngine({
    required String savedEngine,
    required List<String> engines,
    required String? defaultEngine,
  }) {
    if (savedEngine.isNotEmpty && engines.contains(savedEngine)) {
      return savedEngine;
    }
    if (defaultEngine != null && engines.contains(defaultEngine)) {
      return defaultEngine;
    }
    if (engines.isNotEmpty) {
      return engines.first;
    }
    return null;
  }

  Future<void> _loadVoicesForEngine(String engine) async {
    if (!_isAndroid) {
      return;
    }

    setState(() {
      _loadingVoices = true;
      _externalCheckResult = null;
    });

    try {
      final voices = await _engineService.getVoices(engine: engine);
      if (!mounted) {
        return;
      }
      setState(() {
        _voices = voices;
        _loadingVoices = false;
      });
      await _ensureVoiceSelection(engine, voices);
    } catch (error) {
      await AppRunLogService.instance.logError('加载 Android TTS 声线失败: $error');
      if (!mounted) {
        return;
      }
      setState(() => _loadingVoices = false);
    }
  }

  Future<void> _ensureVoiceSelection(
    String? engine,
    List<Map<String, String>> voices,
  ) async {
    if (!mounted || engine == null) {
      return;
    }

    final notifier = ref.read(readerSettingsProvider.notifier);
    final settings = ref.read(readerSettingsProvider);
    final savedVoice = settings.androidExternalTtsVoice;

    Map<String, String> nextVoice = const <String, String>{};
    if (savedVoice.isNotEmpty &&
        voices.any(
          (voice) => AndroidTtsEngineService.sameVoice(voice, savedVoice),
        )) {
      nextVoice = savedVoice;
    } else if (voices.isNotEmpty) {
      nextVoice = Map<String, String>.from(voices.first);
    }

    notifier.setAndroidExternalTtsEngine(engine);
    if (nextVoice.isNotEmpty) {
      notifier.setAndroidExternalTtsVoice(nextVoice);
    }
  }

  Future<void> _checkExternalEngine() async {
    if (!_isAndroid || _checkingExternal) {
      return;
    }

    final settings = ref.read(readerSettingsProvider);
    final engine = settings.androidExternalTtsEngine;
    final voice = settings.androidExternalTtsVoice;

    setState(() => _checkingExternal = true);
    try {
      final result = await _engineService.checkAvailability(
        engine: engine,
        voice: voice,
      );
      if (!mounted) {
        return;
      }
      setState(() => _externalCheckResult = result);
    } catch (error) {
      await AppRunLogService.instance.logError('检测 Android TTS 引擎失败: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _externalCheckResult = TtsModelCheckResult(
          success: false,
          message: '检测失败：$error',
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('检测失败：$error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _checkingExternal = false);
      }
    }
  }

  Future<void> _enableExternalEngine() async {
    final notifier = ref.read(readerSettingsProvider.notifier);
    final settings = ref.read(readerSettingsProvider);
    final engine = settings.androidExternalTtsEngine.trim();
    if (engine.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择一个 Android TTS 引擎')));
      return;
    }

    notifier.setAndroidExternalTts(
      true,
      engine: settings.androidExternalTtsEngine,
      voice: settings.androidExternalTtsVoice,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已切换到伴生引擎: ${_engineLabel(engine)}')),
    );
  }

  String _voiceLabel(Map<String, String> voice) {
    final name = voice['name'] ?? voice['identifier'] ?? '默认声线';
    final locale = voice['locale'];
    if (locale == null || locale.isEmpty) {
      return name;
    }
    return '$name ($locale)';
  }

  String _engineLabel(String engine) {
    return AndroidTtsEngineService.displayEngineLabel(engine);
  }

  DownloadTaskRecord? _taskFor(List<DownloadTaskRecord> tasks, String modelId) {
    for (final task in tasks) {
      if (task.kind == DownloadTaskKind.ttsModel && task.modelId == modelId) {
        return task;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final tasks = ref.watch(downloadTasksProvider).asData?.value ?? const [];
    final selectedExternalEngine = settings.androidExternalTtsEngine;
    final selectedExternalVoice = settings.androidExternalTtsVoice;

    return Scaffold(
      appBar: AppBar(title: const Text('TTS 模型与引擎')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '双层 TTS 架构',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '第一层是 App 内置或下载的离线模型，负责稳定朗读。第二层是 Android 伴生引擎，负责承接系统 TTS 或独立伴生服务。',
                  ),
                  if (_isAndroid) ...[
                    const SizedBox(height: 8),
                    const Text('高表现力模型建议走 Android 伴生引擎，不直接塞进主 APK。'),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('内置与离线模型', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final model in LocalTtsModelManager.availableModels)
            _buildModelCard(
              context,
              settings,
              notifier,
              model,
              _taskFor(tasks, model.id),
            ),
          if (_isAndroid) ...[
            const SizedBox(height: 8),
            Text(
              'Android 伴生引擎',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('这里接的是手机上已经安装好的 TTS 引擎，可以是系统引擎，也可以是第三方伴生服务。'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _loadingEngines
                                ? '正在扫描引擎...'
                                : '已发现 ${_engines.length} 个引擎',
                          ),
                        ),
                        IconButton(
                          onPressed: _loadingEngines
                              ? null
                              : _loadAndroidEngines,
                          icon: const Icon(Icons.refresh),
                          tooltip: '刷新引擎列表',
                        ),
                      ],
                    ),
                    if (_defaultEngine != null && _defaultEngine!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('系统默认引擎: ${_engineLabel(_defaultEngine!)}'),
                      ),
                    DropdownButtonFormField<String>(
                      initialValue: _engines.contains(selectedExternalEngine)
                          ? selectedExternalEngine
                          : null,
                      decoration: const InputDecoration(
                        labelText: '伴生引擎',
                        border: OutlineInputBorder(),
                      ),
                      items: _engines
                          .map(
                            (engine) => DropdownMenuItem<String>(
                              value: engine,
                              child: Text(_engineLabel(engine)),
                            ),
                          )
                          .toList(),
                      onChanged: _engines.isEmpty
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              notifier.setAndroidExternalTtsEngine(value);
                              notifier.setAndroidExternalTtsVoice(
                                const <String, String>{},
                              );
                              unawaited(_loadVoicesForEngine(value));
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue:
                          _voices.any(
                            (voice) => AndroidTtsEngineService.sameVoice(
                              voice,
                              selectedExternalVoice,
                            ),
                          )
                          ? _voiceLabel(selectedExternalVoice)
                          : null,
                      decoration: const InputDecoration(
                        labelText: '声线',
                        border: OutlineInputBorder(),
                      ),
                      items: _voices
                          .map(
                            (voice) => DropdownMenuItem<String>(
                              value: _voiceLabel(voice),
                              child: Text(_voiceLabel(voice)),
                            ),
                          )
                          .toList(),
                      onChanged: _voices.isEmpty || _loadingVoices
                          ? null
                          : (value) {
                              if (value == null) {
                                return;
                              }
                              final matchedVoice = _voices.firstWhere(
                                (voice) => _voiceLabel(voice) == value,
                              );
                              notifier.setAndroidExternalTtsVoice(
                                Map<String, String>.from(matchedVoice),
                              );
                            },
                    ),
                    if (_loadingVoices) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
                    if (_externalCheckResult != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _externalCheckResult!.success
                                ? Icons.check_circle
                                : Icons.error_outline,
                            color: _externalCheckResult!.success
                                ? Colors.green
                                : Colors.orange,
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_externalCheckResult!.message)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _checkingExternal
                              ? null
                              : _checkExternalEngine,
                          icon: const Icon(Icons.health_and_safety_outlined),
                          label: const Text('检测引擎'),
                        ),
                        FilledButton.icon(
                          onPressed: _engines.isEmpty
                              ? null
                              : _enableExternalEngine,
                          icon: const Icon(Icons.link),
                          label: Text(
                            settings.useAndroidExternalTts
                                ? '当前使用伴生引擎'
                                : '设为当前朗读引擎',
                          ),
                        ),
                        if (settings.useAndroidExternalTts)
                          OutlinedButton.icon(
                            onPressed: () {
                              notifier.setAndroidExternalTts(false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('已退出伴生引擎模式')),
                              );
                            },
                            icon: const Icon(Icons.link_off),
                            label: const Text('退出伴生引擎'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModelCard(
    BuildContext context,
    ReaderSettings settings,
    ReaderSettingsNotifier notifier,
    TtsModelConfig model,
    DownloadTaskRecord? task,
  ) {
    final isDownloading =
        task?.status == DownloadTaskStatus.queued ||
        task?.status == DownloadTaskStatus.downloading;
    final isStaged = task?.status == DownloadTaskStatus.staged;
    final progress = task?.progress ?? 0.0;

    final statusText = _checking[model.id] == true
        ? '正在检测...'
        : task?.status == DownloadTaskStatus.failed &&
              task?.error?.isNotEmpty == true
        ? '下载失败: ${task!.error}'
        : task?.status == DownloadTaskStatus.staged &&
              task?.error?.isNotEmpty == true
        ? task!.error!
        : (_checkResults[model.id]?.message ?? '尚未检测');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  model.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Chip(label: Text(model.isBuiltIn ? '内置' : model.size)),
                if (settings.useLocalTts &&
                    settings.activeLocalTtsId == model.id)
                  const Chip(label: Text('当前离线朗读')),
                if (isStaged) const Chip(label: Text('待切换')),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              model.description,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _checkResults[model.id]?.success == true
                      ? Icons.check_circle
                      : Icons.error_outline,
                  color: _checkResults[model.id]?.success == true
                      ? Colors.green
                      : Colors.orange,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(statusText)),
              ],
            ),
            if (isDownloading || isStaged) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(value: isStaged ? 1.0 : progress),
              const SizedBox(height: 4),
              Text(
                isStaged
                    ? '100.0% - 已下载，等待切换'
                    : '${(progress * 100).toStringAsFixed(1)}%',
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _checking[model.id] == true
                      ? null
                      : () => _runCheck(model.id),
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: const Text('检测'),
                ),
                FilledButton.icon(
                  onPressed:
                      settings.useLocalTts &&
                          settings.activeLocalTtsId == model.id
                      ? null
                      : () {
                          notifier.setLocalTts(true, model.id);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('已切换到 ${model.name}')),
                          );
                        },
                  icon: const Icon(Icons.record_voice_over),
                  label: Text(
                    settings.useLocalTts &&
                            settings.activeLocalTtsId == model.id
                        ? '正在使用'
                        : '设为离线朗读',
                  ),
                ),
                if (!model.isBuiltIn) ...[
                  ElevatedButton.icon(
                    onPressed: isDownloading
                        ? null
                        : () => _download(model, false),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('下载(官方)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isDownloading
                        ? null
                        : () => _download(model, true),
                    icon: const Icon(Icons.cloud_download_outlined, size: 18),
                    label: const Text('下载(镜像)'),
                  ),
                  OutlinedButton.icon(
                    onPressed: isDownloading ? null : () => _delete(model),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('删除'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
