import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logging/app_run_log_service.dart';
import '../../../core/utils/text_sanitizer.dart';
import '../providers/global_settings_provider.dart';
import '../../translation/translation_config.dart';
import '../../webnovel/models.dart';
import '../../webnovel/webnovel_repository.dart';

enum _SourceMenuAction { aiRepair, versions }

class BookSourceFilesScreen extends ConsumerStatefulWidget {
  BookSourceFilesScreen({super.key, WebNovelRepositoryHandle? repository})
    : repository = repository ?? WebNovelRepository();

  final WebNovelRepositoryHandle repository;

  @override
  ConsumerState<BookSourceFilesScreen> createState() =>
      _BookSourceFilesScreenState();
}

class _BookSourceFilesScreenState
    extends ConsumerState<BookSourceFilesScreen> {
  final TextEditingController _filterController = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  String _filterText = '';
  List<WebNovelSource> _sources = const <WebNovelSource>[];
  final Set<String> _selectedSourceIds = <String>{};

  WebNovelRepositoryHandle get _repository => widget.repository;

  List<WebNovelSource> get _visibleSources {
    final query = _filterText.trim().toLowerCase();
    if (query.isEmpty) {
      return _sources;
    }

    return _sources
        .where((source) {
          final haystack = sanitizeUiText(
            '${source.name}\n${source.baseUrl}\n${source.tags.join('\n')}',
            fallback: '',
          ).toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }

  int get _enabledCount => _sources.where((source) => source.enabled).length;

  int get _selectedCount => _selectedSourceIds.length;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      await _repository.prewarm().timeout(const Duration(seconds: 12));
      final sources = await _repository.listSources().timeout(
        const Duration(seconds: 12),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sources = sources;
        _selectedSourceIds.removeWhere(
          (id) => !sources.any((source) => source.id == id),
        );
        _loading = false;
      });
    } catch (error) {
      await AppRunLogService.instance.logError('加载书源文件失败: $error');
      if (!mounted) {
        return;
      }
      setState(() {
        _sources = const <WebNovelSource>[];
        _loading = false;
        _loadError = '加载书源文件失败：$error';
      });
    }
  }

  Future<void> _runBusyTask(Future<void> Function() action) async {
    if (_busy) {
      return;
    }

    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _importFromFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    final path = picked?.files.single.path;
    if (path == null || path.isEmpty) {
      return;
    }

    await _runBusyTask(() async {
      try {
        final text = await File(path).readAsString();
        final report = await _repository.importSourcesInputWithReport(text);
        await _reload();
        if (!mounted) {
          return;
        }
        await _showImportReport(report);
      } catch (error) {
        await AppRunLogService.instance.logError('导入书源文件失败: $error');
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _importFromPaste() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('粘贴书源 JSON / Legado 链接'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('支持直接粘贴 JSON、Legado 导入链接，或书源 JSON 地址。'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('导入'),
            ),
          ],
        );
      },
    );

    if (text == null || text.isEmpty) {
      return;
    }

    await _runBusyTask(() async {
      try {
        final report = await _repository.importSourcesInputWithReport(text);
        await _reload();
        if (!mounted) {
          return;
        }
        await _showImportReport(report);
      } catch (error) {
        await AppRunLogService.instance.logError('粘贴导入书源失败: $error');
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _exportToFile() async {
    await _runBusyTask(() async {
      try {
        final payload = await _repository.exportSourcesJson();
        final path = await FilePicker.platform.saveFile(
          dialogTitle: '选择自定义书源文件导出路径',
          fileName: 'wenwen_tome_sources.json',
          type: FileType.custom,
          allowedExtensions: const ['json'],
        );
        if (path == null || path.isEmpty) {
          return;
        }
        await File(path).writeAsString(payload);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出成功：$path')));
      } catch (error) {
        await AppRunLogService.instance.logError('导出自定义书源文件失败: $error');
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _copyJson() async {
    await _runBusyTask(() async {
      try {
        final payload = await _repository.exportSourcesJson();
        await Clipboard.setData(ClipboardData(text: payload));
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('自定义书源 JSON 已复制到剪贴板')));
      } catch (error) {
        await AppRunLogService.instance.logError('复制书源 JSON 失败: $error');
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('复制失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _toggleSource(WebNovelSource source, bool enabled) async {
    await _runBusyTask(() async {
      try {
        await _repository.setSourceEnabled(source.id, enabled);
        await _reload();
      } catch (error) {
        await AppRunLogService.instance.logError(
          '切换书源状态失败: ${source.id}; $error',
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('切换失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _testSource(WebNovelSource source) async {
    await _runBusyTask(() async {
      try {
        final result = await _repository.testSource(source);
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      } catch (error) {
        await AppRunLogService.instance.logError(
          '测试书源失败: ${source.id}; $error',
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('测试失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _showImportReport(SourceImportReport report) async {
    final failedCount = report.entries
        .where((entry) => entry.status == SourceImportEntryStatus.failed)
        .length;
    final skippedCount = report.entries
        .where((entry) => entry.status == SourceImportEntryStatus.skipped)
        .length;
    final message =
        '导入 ${report.importedCount}/${report.totalEntries}（更新 ${report.updatedCount}），兼容映射 ${report.legacyMappedCount}，跳过 $skippedCount，失败 $failedCount。';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );

    String statusLabel(SourceImportEntryStatus status) {
      switch (status) {
        case SourceImportEntryStatus.imported:
          return '导入';
        case SourceImportEntryStatus.updated:
          return '更新';
        case SourceImportEntryStatus.skipped:
          return '跳过';
        case SourceImportEntryStatus.failed:
          return '失败';
      }
    }

    final issues = report.entries
        .where(
          (entry) =>
              entry.status != SourceImportEntryStatus.imported ||
              entry.warnings.isNotEmpty ||
              (entry.message.isNotEmpty && entry.message != '导入成功'),
        )
        .toList(growable: false);
    if (issues.isEmpty) {
      return;
    }

    const limit = 200;
    final visible = issues.take(limit).toList(growable: false);
    final truncated = issues.length > visible.length;
    final lines = <String>[
      message,
      if (truncated) '（仅展示前 $limit 条，共 ${issues.length} 条）',
      '',
      for (final entry in visible)
        [
          '#${entry.index} [${statusLabel(entry.status)}]',
          if (entry.sourceName.trim().isNotEmpty) entry.sourceName.trim(),
          if (entry.sourceId.trim().isNotEmpty) '(${entry.sourceId.trim()})',
          if (entry.legacyMapped) '[Legado]',
          if (entry.message.trim().isNotEmpty) entry.message.trim(),
          ...entry.warnings.map((item) => '  - $item'),
        ].join(' '),
    ];
    final detailText = lines.join('\n');

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('导入报告'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(child: SelectableText(detailText)),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: detailText));
                if (!context.mounted) {
                  return;
                }
                Navigator.pop(context);
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('导入报告已复制')));
              },
              child: const Text('复制报告'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  TranslationConfig? _activeAiConfig(GlobalSettings settings) {
    if (settings.translationConfigs.isEmpty) {
      return null;
    }
    return settings.translationConfigs.firstWhere(
      (config) => config.id == settings.translationConfigId,
      orElse: () => settings.translationConfigs.first,
    );
  }

  Future<void> _promptAiRepair(WebNovelSource source) async {
    final settings = ref.read(globalSettingsProvider);
    final mode = AiSourceRepairModeX.fromStorageValue(
      settings.aiSourceRepairMode,
    );
    if (mode == AiSourceRepairMode.off) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI 书源修复已关闭，请先在设置中开启')),
      );
      return;
    }
    final config = _activeAiConfig(settings);
    if (config == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('缺少可用的 AI API 配置')),
      );
      return;
    }

    final urlController = TextEditingController(text: source.baseUrl);
    final queryController = TextEditingController(text: '斗破苍穹');
    final input = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('AI 书源修复'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('提供一个失败页面的 URL，以及可选的样例搜索关键词。'),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: '样例 URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: queryController,
                decoration: const InputDecoration(
                  labelText: '样例搜索关键词（可选）',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              [urlController.text.trim(), queryController.text.trim()],
            ),
            child: const Text('开始修复'),
          ),
        ],
      ),
    );
    if (input == null || input.isEmpty) {
      return;
    }

    final sampleUrl = input[0].trim();
    final sampleQuery = input.length > 1 ? input[1].trim() : '';
    if (sampleUrl.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('样例 URL 不能为空')));
      return;
    }

    await _runBusyTask(() async {
      try {
        final suggestion = await _repository.repairSourceWithAi(
          source: source,
          sampleUrl: sampleUrl,
          sampleQuery: sampleQuery,
          config: config,
          mode: mode,
        );
        if (!mounted) {
          return;
        }
        if (suggestion.applied) {
          await _reload();
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('AI 修复已应用：${suggestion.validationMessage}')),
          );
          return;
        }
        final status =
            suggestion.validationMessage.isNotEmpty
                ? suggestion.validationMessage
                : '已生成建议，当前模式不会自动应用';
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('AI 修复建议'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(status),
                  if (suggestion.note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('说明：${suggestion.note}'),
                  ],
                  const SizedBox(height: 12),
                  const Text('补丁 JSON 已复制到剪贴板，可用于人工比对。'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
        await Clipboard.setData(
          ClipboardData(text: jsonEncode(suggestion.patch)),
        );
      } catch (error) {
        await AppRunLogService.instance.logError('AI 修复失败: $error');
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI 修复失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _showSourceVersions(WebNovelSource source) async {
    await _runBusyTask(() async {
      try {
        final versions = await _repository.listSourceVersions(source.id);
        if (versions.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('暂无历史版本')));
          }
          return;
        }
        if (!mounted) {
          return;
        }
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            minChildSize: 0.45,
            maxChildSize: 0.9,
            builder: (context, controller) => ListView.separated(
              controller: controller,
              padding: const EdgeInsets.all(16),
              itemCount: versions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final version = versions[index];
                final time = version.createdAt.toLocal().toString();
                return ListTile(
                  title: Text(version.note.isEmpty ? '版本记录' : version.note),
                  subtitle: Text('$time · ${version.createdBy}'),
                  trailing: TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('回滚书源'),
                          content: const Text('确定回滚到该版本吗？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('回滚'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) {
                        return;
                      }
                      await _repository.rollbackSourceVersion(version.id);
                      await _reload();
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(content: Text('已回滚至选定版本')),
                      );
                    },
                    child: const Text('回滚'),
                  ),
                );
              },
            ),
          ),
        );
      } catch (error) {
        await AppRunLogService.instance.logError('加载书源版本失败: $error');
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加载版本失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  void _toggleSelection(String sourceId, bool selected) {
    setState(() {
      if (selected) {
        _selectedSourceIds.add(sourceId);
      } else {
        _selectedSourceIds.remove(sourceId);
      }
    });
  }

  void _selectAllVisible(List<WebNovelSource> visibleSources) {
    setState(() {
      for (final source in visibleSources) {
        if (!source.builtin) {
          _selectedSourceIds.add(source.id);
        }
      }
    });
  }

  void _invertVisibleSelection(List<WebNovelSource> visibleSources) {
    setState(() {
      for (final source in visibleSources) {
        if (source.builtin) {
          continue;
        }
        if (_selectedSourceIds.contains(source.id)) {
          _selectedSourceIds.remove(source.id);
        } else {
          _selectedSourceIds.add(source.id);
        }
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedSourceIds.clear());
  }

  Future<void> _deleteSelectedSources() async {
    final ids = _selectedSourceIds.toList(growable: false);
    if (ids.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除所选书源'),
          content: Text('将删除 $_selectedCount 个自定义书源，内置书源不会受影响。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    await _runBusyTask(() async {
      final removed = await _repository.removeCustomSources(ids);
      await AppRunLogService.instance.logInfo('批量删除书源：$removed 项');
      _clearSelection();
      await _reload();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除 $removed 个自定义书源')));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visibleSources = _visibleSources;

    return Scaffold(
      appBar: AppBar(
        title: const Text('书源文件'),
        actions: [
          IconButton(
            onPressed: _loading || _busy ? null : _reload,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '桌面端只保留书源文件管理，不再提供网文浏览、搜书和网页阅读。',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Chip(label: Text('书源 $_sources.length 个')),
                          Chip(label: Text('启用 $_enabledCount 个')),
                          Chip(label: Text('已选 $_selectedCount 项')),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : _importFromFile,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('导入文件'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _importFromPaste,
                            icon: const Icon(Icons.paste),
                            label: const Text('粘贴导入'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _exportToFile,
                            icon: const Icon(Icons.download_outlined),
                            label: const Text('导出自定义文件'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _copyJson,
                            icon: const Icon(Icons.content_copy_outlined),
                            label: const Text('复制自定义 JSON'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _selectAllVisible(visibleSources),
                            icon: const Icon(Icons.select_all),
                            label: const Text('全选可见'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _invertVisibleSelection(visibleSources),
                            icon: const Icon(Icons.flip),
                            label: const Text('反选可见'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy || _selectedCount == 0
                                ? null
                                : _clearSelection,
                            icon: const Icon(Icons.clear_all),
                            label: const Text('清空选择'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _busy || _selectedCount == 0
                                ? null
                                : _deleteSelectedSources,
                            icon: const Icon(Icons.delete_sweep_outlined),
                            label: const Text('删除所选'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _filterController,
                onChanged: (value) => setState(() => _filterText = value),
                decoration: InputDecoration(
                  hintText: '筛选书源（名称 / 域名 / 标签）',
                  border: const OutlineInputBorder(),
                  suffixText: '$visibleSources.length/${_sources.length}',
                ),
              ),
              const SizedBox(height: 12),
              if (_loadError != null)
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('书源文件加载失败'),
                    subtitle: Text(_loadError!),
                    trailing: TextButton(
                      onPressed: _busy ? null : _reload,
                      child: const Text('重试'),
                    ),
                  ),
                ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (visibleSources.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('当前没有可显示的书源文件。'),
                  ),
                )
              else
                for (final source in visibleSources)
                  Card(
                    child: ListTile(
                      leading: source.builtin
                          ? const Icon(Icons.lock_outline)
                          : Checkbox(
                              value: _selectedSourceIds.contains(source.id),
                              onChanged: _busy
                                  ? null
                                  : (value) => _toggleSelection(
                                      source.id,
                                      value ?? false,
                                    ),
                            ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              sanitizeUiText(source.name, fallback: source.name),
                            ),
                          ),
                          if (source.builtin)
                            const Chip(
                              label: Text('内置'),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${sanitizeUiText(source.baseUrl, fallback: source.baseUrl)}\n'
                        '${source.tags.map((tag) => sanitizeUiText(tag, fallback: tag)).where((tag) => tag.isNotEmpty).join(' / ')}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: true,
                      onLongPress: source.builtin || _busy
                          ? null
                          : () => _toggleSelection(
                              source.id,
                              !_selectedSourceIds.contains(source.id),
                            ),
                      trailing: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PopupMenuButton<_SourceMenuAction>(
                            tooltip: '更多操作',
                            onSelected: (action) {
                              switch (action) {
                                case _SourceMenuAction.aiRepair:
                                  if (!source.builtin) {
                                    unawaited(_promptAiRepair(source));
                                  }
                                  return;
                                case _SourceMenuAction.versions:
                                  unawaited(_showSourceVersions(source));
                                  return;
                              }
                            },
                            itemBuilder: (context) => [
                              if (!source.builtin)
                                const PopupMenuItem(
                                  value: _SourceMenuAction.aiRepair,
                                  child: Text('AI 修复'),
                                ),
                              const PopupMenuItem(
                                value: _SourceMenuAction.versions,
                                child: Text('版本记录'),
                              ),
                            ],
                          ),
                          IconButton(
                            onPressed: _busy ? null : () => _testSource(source),
                            tooltip: '测试书源',
                            icon: const Icon(Icons.health_and_safety_outlined),
                          ),
                          Switch(
                            value: source.enabled,
                            onChanged: _busy
                                ? null
                                : (value) => _toggleSource(source, value),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
