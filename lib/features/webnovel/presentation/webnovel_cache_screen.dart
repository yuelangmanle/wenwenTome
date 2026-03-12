import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../logging/run_event_tracker.dart';
import '../webnovel_download_manager.dart';
import '../webnovel_repository.dart';

class WebNovelCacheScreen extends StatefulWidget {
  WebNovelCacheScreen({super.key, WebNovelRepositoryHandle? repository})
    : repository = repository ?? WebNovelRepository();

  final WebNovelRepositoryHandle repository;

  @override
  State<WebNovelCacheScreen> createState() => _WebNovelCacheScreenState();
}

class _WebNovelCacheScreenState extends State<WebNovelCacheScreen> {
  final RunEventTracker _runEventTracker = RunEventTracker();

  bool _loading = true;
  Object? _loadError;

  final _maxConcurrentController = TextEditingController();
  final _quotaMbController = TextEditingController();
  final _maxBooksController = TextEditingController();
  final _maxDaysController = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_loadSettings());
  }

  @override
  void dispose() {
    _maxConcurrentController.dispose();
    _quotaMbController.dispose();
    _maxBooksController.dispose();
    _maxDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await widget.repository.prewarm();
      final maxConcurrent = await widget.repository.getDownloadSettingInt(
        'download_max_concurrent',
        2,
      );
      final quotaBytes = await widget.repository.getDownloadSettingInt(
        'cache_quota_bytes',
        0,
      );
      final maxBooks = await widget.repository.getDownloadSettingInt(
        'cache_max_books',
        0,
      );
      final maxDays = await widget.repository.getDownloadSettingInt(
        'cache_max_days',
        0,
      );

      _maxConcurrentController.text = maxConcurrent.toString();
      _quotaMbController.text =
          quotaBytes <= 0 ? '0' : (quotaBytes ~/ (1024 * 1024)).toString();
      _maxBooksController.text = maxBooks.toString();
      _maxDaysController.text = maxDays.toString();
    } catch (error) {
      _loadError = error;
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    int readInt(TextEditingController controller) =>
        int.tryParse(controller.text.trim()) ?? 0;

    final maxConcurrent = readInt(_maxConcurrentController).clamp(1, 8);
    final quotaMb = readInt(_quotaMbController).clamp(0, 1024 * 1024);
    final maxBooks = readInt(_maxBooksController).clamp(0, 100000);
    final maxDays = readInt(_maxDaysController).clamp(0, 3650);

    await widget.repository.setDownloadSettingInt(
      'download_max_concurrent',
      maxConcurrent,
    );
    await widget.repository.setDownloadSettingInt(
      'cache_quota_bytes',
      quotaMb <= 0 ? 0 : quotaMb * 1024 * 1024,
    );
    await widget.repository.setDownloadSettingInt('cache_max_books', maxBooks);
    await widget.repository.setDownloadSettingInt('cache_max_days', maxDays);

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已保存缓存设置')));
    HapticFeedback.selectionClick();
  }

  Future<void> _pauseAll() async {
    await _runEventTracker.track<void>(
      action: 'webnovel.download.pause_all',
      isCancelled: () => !mounted,
      operation: () => widget.repository.pauseAllDownloads(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已暂停全部缓存任务')),
    );
  }

  Future<void> _resumeAll() async {
    await _runEventTracker.track<void>(
      action: 'webnovel.download.resume_all',
      isCancelled: () => !mounted,
      operation: () => widget.repository.resumeAllDownloads(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已继续全部缓存任务')),
    );
  }

  Future<void> _clearDoneTasks() async {
    await _runEventTracker.track<void>(
      action: 'webnovel.download.clear_terminal_tasks',
      isCancelled: () => !mounted,
      operation: () => widget.repository.clearTerminalDownloadTasks(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清理已完成/失败任务')),
    );
  }

  Future<void> _clearAllTasks() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空任务'),
        content: const Text('将删除全部缓存任务记录（不会删除已缓存章节内容）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runEventTracker.track<void>(
      action: 'webnovel.download.clear_all_tasks',
      isCancelled: () => !mounted,
      operation: () => widget.repository.clearAllDownloadTasks(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已清空全部任务')),
    );
  }

  Future<void> _clearAllCache() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空缓存'),
        content: const Text('将删除全部已缓存章节内容（不会删除书架书籍）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除缓存'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await _runEventTracker.track<int>(
      action: 'webnovel.cache.clear_all',
      isCancelled: () => !mounted,
      operation: () => widget.repository.clearCachedChapters(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已删除缓存章节：$deleted 条')),
    );
  }

  Widget _buildSettingsCard() {
    InputDecoration deco(String label, String hint) => InputDecoration(
      labelText: label,
      hintText: hint,
      border: const OutlineInputBorder(),
      isDense: true,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '策略与并发',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxConcurrentController,
                    keyboardType: TextInputType.number,
                    decoration: deco('并发下载', '1~8'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _quotaMbController,
                    keyboardType: TextInputType.number,
                    decoration: deco('缓存上限(MB)', '0=不限'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _maxBooksController,
                    keyboardType: TextInputType.number,
                    decoration: deco('最多保留(本)', '0=不限'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _maxDaysController,
                    keyboardType: TextInputType.number,
                    decoration: deco('保留天数', '0=不限'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _saveSettings,
                icon: const Icon(Icons.save_outlined),
                label: const Text('保存设置'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(Map<String, int> stats) {
    final chapters = stats['cachedChapters'] ?? 0;
    final books = stats['cachedBooks'] ?? 0;
    final bytes = stats['cachedBytes'] ?? 0;
    final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _StatTile(title: '缓存章节', value: chapters.toString()),
            ),
            Expanded(child: _StatTile(title: '涉及书籍', value: books.toString())),
            Expanded(child: _StatTile(title: '占用(MB)', value: mb)),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskList(List<WebDownloadTask> tasks) {
    if (tasks.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('暂无缓存任务。'),
        ),
      );
    }

    String statusLabel(WebDownloadTaskStatus status) => switch (status) {
      WebDownloadTaskStatus.queued => '排队中',
      WebDownloadTaskStatus.running => '进行中',
      WebDownloadTaskStatus.paused => '已暂停',
      WebDownloadTaskStatus.failed => '失败',
      WebDownloadTaskStatus.completed => '完成',
    };

    String typeLabel(WebDownloadTaskType type) =>
        type == WebDownloadTaskType.book ? '书级' : '章级';

    return Card(
      child: Column(
        children: [
          for (final task in tasks.take(120)) ...[
            ListTile(
              dense: true,
              leading: Icon(
                task.status == WebDownloadTaskStatus.failed
                    ? Icons.error_outline
                    : task.status == WebDownloadTaskStatus.completed
                    ? Icons.check_circle_outline
                    : task.status == WebDownloadTaskStatus.paused
                    ? Icons.pause_circle_outline
                    : Icons.cloud_download_outlined,
              ),
              title: Text(
                task.type == WebDownloadTaskType.book
                    ? '缓存书籍 ${task.webBookId}'
                    : '缓存 ${task.webBookId}#${task.chapterIndex}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${typeLabel(task.type)} · ${statusLabel(task.status)}'
                '${task.type == WebDownloadTaskType.book && task.totalCount > 0 ? ' · ${task.completedCount}/${task.totalCount}' : ''}'
                '${task.lastErrorMessage.trim().isNotEmpty ? ' · ${task.lastErrorMessage.trim()}' : ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('缓存管理')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('缓存管理')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('加载失败：$_loadError', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _loadSettings,
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('缓存管理'),
        actions: [
          IconButton(
            tooltip: '暂停',
            onPressed: _pauseAll,
            icon: const Icon(Icons.pause_outlined),
          ),
          IconButton(
            tooltip: '继续',
            onPressed: _resumeAll,
            icon: const Icon(Icons.play_arrow_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear_done') {
                unawaited(_clearDoneTasks());
              } else if (value == 'clear_tasks') {
                unawaited(_clearAllTasks());
              } else if (value == 'clear_cache') {
                unawaited(_clearAllCache());
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear_done', child: Text('清理已完成/失败任务')),
              PopupMenuItem(value: 'clear_tasks', child: Text('清空全部任务')),
              PopupMenuItem(value: 'clear_cache', child: Text('清空全部缓存')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<int>(
        stream: widget.repository.watchDownloadTasks(),
        builder: (context, snapshot) {
          return FutureBuilder<Map<String, int>>(
            future: widget.repository.getChapterCacheStats(),
            builder: (context, statsSnapshot) {
              return FutureBuilder<List<WebDownloadTask>>(
                future: widget.repository.listDownloadTasks(
                  includeCompleted: true,
                  limit: 200,
                ),
                builder: (context, taskSnapshot) {
                  final stats = statsSnapshot.data ?? const <String, int>{};
                  final tasks = taskSnapshot.data ?? const <WebDownloadTask>[];

                  return ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      _buildStats(stats),
                      const SizedBox(height: 12),
                      _buildSettingsCard(),
                      const SizedBox(height: 12),
                      _buildTaskList(tasks),
                      const SizedBox(height: 12),
                      Text(
                        '提示：缓存任务会在后台自动恢复；可通过“缓存上限/保留天数/最多保留本数”控制空间占用。',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
