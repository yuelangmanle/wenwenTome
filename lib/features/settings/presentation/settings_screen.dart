import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/runtime_platform.dart';
import '../../logging/app_run_log_service.dart';
import '../../reader/android_tts_engine_service.dart';
import '../../reader/local_tts_model_manager.dart';
import '../../reader/providers/reader_settings_provider.dart';
import '../../translation/translation_config.dart';
import '../../translation/translation_service.dart';
import '../../webnovel/defaults.dart';
import '../providers/global_settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _checkingEnvironment = false;

  bool get _isDesktop =>
      detectLocalRuntimePlatform() == LocalRuntimePlatform.windows;

  TranslationConfig? _activeConfig(GlobalSettings settings) {
    if (settings.translationConfigs.isEmpty) {
      return null;
    }

    return settings.translationConfigs.firstWhere(
      (config) => config.id == settings.translationConfigId,
      orElse: () => settings.translationConfigs.first,
    );
  }

  String _aiRepairModeLabel(String value) {
    switch (value) {
      case 'suggest':
        return '仅建议';
      case 'shadow_validate':
        return '影子验证后可应用';
      default:
        return '关闭';
    }
  }

  Future<void> _runEnvironmentCheck() async {
    if (_checkingEnvironment) {
      return;
    }

    setState(() => _checkingEnvironment = true);
    try {
      final settings = ref.read(globalSettingsProvider);
      final readerSettings = ref.read(readerSettingsProvider);
      final activeConfig = _activeConfig(settings);

      await AppRunLogService.instance.logInfo('开始执行环境自检');
      final ttsResult = await _checkCurrentTts(readerSettings);
      final apiResult = await TranslationService().checkAvailability(
        config: activeConfig,
      );
      await AppRunLogService.instance.logInfo(
        '环境自检结束: tts=${ttsResult.success}; api=${apiResult.success}',
      );

      if (!mounted) {
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('环境自检结果'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CheckRow(
                    title: '当前 TTS',
                    success: ttsResult.success,
                    message: ttsResult.message,
                  ),
                  const SizedBox(height: 12),

                  _CheckRow(
                    title: 'AI API',
                    success: apiResult.success,
                    message: apiResult.message,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      await AppRunLogService.instance.logError('环境自检失败: $error');
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('环境自检失败：$error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _checkingEnvironment = false);
      }
    }
  }

  Future<TtsModelCheckResult> _checkCurrentTts(ReaderSettings settings) async {
    if (settings.useAndroidExternalTts) {
      return AndroidTtsEngineService().checkAvailability(
        engine: settings.androidExternalTtsEngine,
        voice: settings.androidExternalTtsVoice,
      );
    }

    if (settings.useLocalTts) {
      return LocalTtsModelManager().checkAvailability(
        settings.activeLocalTtsId,
      );
    }

    if (settings.useEdgeTts) {
      return const TtsModelCheckResult(
        success: true,
        message: '当前使用 Edge TTS，不依赖本地模型。',
      );
    }

    return const TtsModelCheckResult(success: true, message: '当前使用系统 TTS。');
  }

  String _activeTtsSummary(ReaderSettings settings) {
    if (settings.useAndroidExternalTts) {
      final engine = settings.androidExternalTtsEngine.trim();
      final voice =
          settings.androidExternalTtsVoice['name'] ??
          settings.androidExternalTtsVoice['identifier'];
      if (engine.isEmpty) {
        return 'Android 外部引擎，未选择';
      }
      final displayEngine = AndroidTtsEngineService.displayEngineLabel(engine);
      return voice == null || voice.isEmpty
          ? 'Android 外部引擎 / $displayEngine'
          : 'Android 外部引擎 / $displayEngine / $voice';
    }

    if (settings.useLocalTts) {
      final model =
          LocalTtsModelManager.getModelById(settings.activeLocalTtsId) ??
          LocalTtsModelManager.availableModels.first;
      return '离线模型 / ${model.name}';
    }

    if (settings.useEdgeTts) {
      return 'Edge TTS / ${settings.edgeTtsVoice}';
    }

    return '系统 TTS';
  }

  Future<void> _pickObsidianPath(
    String currentPath,
    GlobalSettingsNotifier notifier,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController(text: currentPath);
        return AlertDialog(
          title: const Text('Obsidian Vault 路径'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: r'E:\Documents\MyVault',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (result != null) {
      notifier.setObsidianPath(result);
      await AppRunLogService.instance.logInfo('更新 Obsidian 路径: $result');
    }
  }

  void _showSourcesDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('内置书源'),
          content: SizedBox(
            width: 320,
            child: ListView(
              shrinkWrap: true,
              children: builtinBookSources
                  .map(
                    (source) => ListTile(
                      leading: const Icon(Icons.rss_feed),
                      title: Text(source.name),
                      subtitle: Text(source.baseUrl),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(globalSettingsProvider);
    final notifier = ref.read(globalSettingsProvider.notifier);
    final readerSettings = ref.watch(readerSettingsProvider);
    final activeConfig = _activeConfig(settings);
    final isAndroid =
        detectLocalRuntimePlatform() == LocalRuntimePlatform.android;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          if (!_isDesktop) ...[
            const _SectionTitle('翻译与 AI'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.api),
                    title: const Text('API 配置'),
                    subtitle: Text(activeConfig?.name ?? '未配置'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/translation-config'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.health_and_safety_outlined),
                    title: const Text('一键环境自检'),
                    subtitle: const Text('检查当前 TTS 和 AI API 是否可用'),
                    trailing: _checkingEnvironment
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: _checkingEnvironment ? null : _runEnvironmentCheck,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.translate),
                    title: const Text('翻译目标语言'),
                    trailing: DropdownButton<String>(
                      value: settings.translateTo,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                        DropdownMenuItem(value: 'zh-TW', child: Text('繁體中文')),
                        DropdownMenuItem(value: 'en', child: Text('English')),
                        DropdownMenuItem(value: 'ja', child: Text('日本語')),
                      ],
                      onChanged: (value) =>
                          notifier.setTranslateTo(value ?? 'zh'),
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: const Icon(Icons.auto_fix_high),
                    title: const Text('AI 搜书增强'),
                    subtitle: const Text('对聚合结果进行语义重排与非小说过滤'),
                    value: settings.enableAiSearchBoost,
                    onChanged: notifier.setEnableAiSearchBoost,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.tune_outlined),
                    title: const Text('AI 书源修复模式'),
                    subtitle: Text(_aiRepairModeLabel(settings.aiSourceRepairMode)),
                    trailing: DropdownButton<String>(
                      value: settings.aiSourceRepairMode,
                      underline: const SizedBox.shrink(),
                      items: const [
                        DropdownMenuItem(value: 'off', child: Text('关闭')),
                        DropdownMenuItem(value: 'suggest', child: Text('仅建议')),
                        DropdownMenuItem(
                          value: 'shadow_validate',
                          child: Text('影子验证后可应用'),
                        ),
                      ],
                      onChanged: (value) =>
                          notifier.setAiSourceRepairMode(value ?? 'off'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _SectionTitle('朗读与声音'),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.record_voice_over),
                    title: const Text('TTS 模型与引擎'),
                    subtitle: Text(_activeTtsSummary(readerSettings)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/local-tts'),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.layers_outlined),
                    title: const Text('双层 TTS 架构'),
                    subtitle: Text(
                      isAndroid
                          ? '手机端可组合使用离线模型与 Android 外部引擎。'
                          : '当前平台优先使用离线模型，外部引擎仅在手机端提供。',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          const _SectionTitle('书库与同步'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_download_outlined),
                  title: const Text('导入时自动补全元数据'),
                  subtitle: const Text('从外部服务获取书名、封面和标签'),
                  value: settings.autoFetchMeta,
                  onChanged: notifier.setAutoFetchMeta,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.source_outlined),
                  title: const Text('书源文件'),
                  subtitle: Text(
                    _isDesktop
                        ? '桌面端仅保留书源文件导入、导出、启停与测试'
                        : '查看内置书源，手机端网文功能仍在独立页面提供',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/source-files'),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.public_outlined),
                  title: const Text('书源搜索网页兜底'),
                  subtitle: const Text('仅在书源搜索结果不足时启用网页搜索兜底'),
                  value: settings.enableWebFallbackInBookSearch,
                  onChanged: notifier.setEnableWebFallbackInBookSearch,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('网文缓存管理'),
                  subtitle: const Text('查看缓存任务、空间占用与清理策略'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/webnovel-cache'),
                ),
                if (!_isDesktop) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: const Text('Obsidian Vault 路径'),
                    subtitle: Text(
                      settings.obsidianPath.isEmpty
                          ? '未配置'
                          : settings.obsidianPath,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _pickObsidianPath(settings.obsidianPath, notifier),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _SectionTitle('日志与更新'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('运行日志'),
                  subtitle: const Text('查看、导出、分享、清空'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/runtime-logs'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('版本与更新日志'),
                  subtitle: const Text('查看 CHANGELOG.md'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/about'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.title,
    required this.success,
    required this.message,
  });

  final String title;
  final bool success;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          success ? Icons.check_circle : Icons.error_outline,
          color: success ? Colors.green : Colors.redAccent,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(message),
            ],
          ),
        ),
      ],
    );
  }
}
