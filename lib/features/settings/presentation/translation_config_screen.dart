import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../logging/app_run_log_service.dart';
import '../../translation/translation_config.dart';
import '../../translation/translation_service.dart';
import '../providers/global_settings_provider.dart';

class TranslationConfigScreen extends ConsumerStatefulWidget {
  const TranslationConfigScreen({super.key});

  @override
  ConsumerState<TranslationConfigScreen> createState() =>
      _TranslationConfigScreenState();
}

class _TranslationConfigScreenState
    extends ConsumerState<TranslationConfigScreen> {
  bool _testing = false;

  Future<void> _editConfig(TranslationConfig? config) async {
    final result = await Navigator.of(context).push<TranslationConfig>(
      MaterialPageRoute(
        builder: (_) => _TranslationConfigEditScreen(config: config),
      ),
    );
    if (result == null) return;

    final settings = ref.read(globalSettingsProvider);
    final configs = List<TranslationConfig>.from(settings.translationConfigs);
    if (config == null) {
      configs.add(result);
      await AppRunLogService.instance.logInfo('新增 API 配置：${result.name}');
    } else {
      final index = configs.indexWhere((item) => item.id == config.id);
      if (index != -1) {
        configs[index] = result;
      }
      await AppRunLogService.instance.logInfo('更新 API 配置：${result.name}');
    }

    final notifier = ref.read(globalSettingsProvider.notifier);
    notifier.setTranslationConfigs(configs);
    if (config == null || settings.translationConfigId.isEmpty) {
      notifier.setTranslationConfigId(result.id);
    }
  }

  Future<void> _testConfig(TranslationConfig config) async {
    if (_testing) {
      return;
    }
    setState(() => _testing = true);
    try {
      final result = await TranslationService().checkAvailability(
        config: config,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green : Colors.redAccent,
        ),
      );
    } catch (error) {
      await AppRunLogService.instance.logError(
        '测试翻译配置失败: ${config.name}; $error',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('检测失败：$error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _deleteConfig(TranslationConfig config) async {
    final settings = ref.read(globalSettingsProvider);
    if (settings.translationConfigs.length <= 1) return;

    final next = settings.translationConfigs
        .where((item) => item.id != config.id)
        .toList();
    final notifier = ref.read(globalSettingsProvider.notifier);
    notifier.setTranslationConfigs(next);
    if (settings.translationConfigId == config.id && next.isNotEmpty) {
      notifier.setTranslationConfigId(next.first.id);
    }
    await AppRunLogService.instance.logInfo('删除 API 配置：${config.name}');
  }

  void _handleBack() {
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go('/settings');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(globalSettingsProvider);
    final notifier = ref.read(globalSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: '返回设置',
          onPressed: _handleBack,
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('翻译与 AI API 配置'),
        actions: [
          IconButton(
            tooltip: '新增配置',
            onPressed: () => _editConfig(null),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final config in settings.translationConfigs)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          onPressed: () =>
                              notifier.setTranslationConfigId(config.id),
                          icon: Icon(
                            settings.translationConfigId == config.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: settings.translationConfigId == config.id
                                ? Theme.of(context).colorScheme.primary
                                : null,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      config.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  if (settings.translationConfigId == config.id)
                                    const Chip(label: Text('当前')),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text('模型：${config.modelName}'),
                              const SizedBox(height: 2),
                              SelectableText(
                                config.baseUrl,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: _testing
                              ? null
                              : () => _testConfig(config),
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.health_and_safety_outlined),
                          label: const Text('检测'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _editConfig(config),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑'),
                        ),
                        if (settings.translationConfigs.length > 1)
                          OutlinedButton.icon(
                            onPressed: () => _deleteConfig(config),
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('删除'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TranslationConfigEditScreen extends StatefulWidget {
  const _TranslationConfigEditScreen({this.config});

  final TranslationConfig? config;

  @override
  State<_TranslationConfigEditScreen> createState() =>
      _TranslationConfigEditScreenState();
}

class _TranslationConfigEditScreenState
    extends State<_TranslationConfigEditScreen> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final config = widget.config;
    if (config != null) {
      _nameCtrl.text = config.name;
      _urlCtrl.text = config.baseUrl;
      _keyCtrl.text = config.apiKey;
      _modelCtrl.text = config.modelName;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  TranslationConfig? _buildConfig() {
    if (_nameCtrl.text.trim().isEmpty ||
        _urlCtrl.text.trim().isEmpty ||
        _modelCtrl.text.trim().isEmpty) {
      return null;
    }

    if (widget.config == null) {
      return TranslationConfig.create(
        name: _nameCtrl.text.trim(),
        baseUrl: _urlCtrl.text.trim(),
        apiKey: _keyCtrl.text.trim(),
        modelName: _modelCtrl.text.trim(),
      );
    }

    return widget.config!.copyWith(
      name: _nameCtrl.text.trim(),
      baseUrl: _urlCtrl.text.trim(),
      apiKey: _keyCtrl.text.trim(),
      modelName: _modelCtrl.text.trim(),
    );
  }

  Future<void> _save() async {
    final config = _buildConfig();
    if (config == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('名称、Base URL、Model Name 不能为空')),
      );
      return;
    }
    Navigator.of(context).pop(config);
  }

  Future<void> _testCurrentConfig() async {
    final config = _buildConfig();
    if (config == null || _testing) {
      return;
    }
    setState(() => _testing = true);
    try {
      final result = await TranslationService().checkAvailability(
        config: config,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green : Colors.redAccent,
        ),
      );
    } catch (error) {
      await AppRunLogService.instance.logError(
        '测试当前翻译配置失败: ${config.name}; $error',
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('检测失败：$error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.config == null ? '新增 API 配置' : '编辑 API 配置'),
        actions: [TextButton(onPressed: _save, child: const Text('保存'))],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomInset),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '配置名称',
              hintText: '例如：DeepSeek 官方',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(
              labelText: 'Base URL',
              hintText: 'https://api.deepseek.com/v1',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _keyCtrl,
            decoration: const InputDecoration(labelText: 'API Key'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: 'Model Name',
              hintText: 'deepseek-chat',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            onPressed: _testing ? null : _testCurrentConfig,
            icon: _testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.health_and_safety_outlined),
            label: const Text('测试当前配置'),
          ),
        ],
      ),
    );
  }
}
