import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../logging/app_run_log_service.dart';
import '../../metadata/metadata_service.dart';
import '../data/book_model.dart';
import '../data/library_service.dart';
import '../providers/library_providers.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  SliverGridDelegate _buildGridDelegate(double width) {
    final columns = (width / 130).floor().clamp(3, 14);
    final spacing = width >= 1200 ? 12.0 : 8.0;
    final aspectRatio = width >= 1200 ? 0.58 : 0.56;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      childAspectRatio: aspectRatio,
      crossAxisSpacing: spacing,
      mainAxisSpacing: spacing,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);
    final loadIssue = ref.watch(booksLoadIssueProvider);
    final hasBooks = booksAsync.asData?.value.isNotEmpty ?? false;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          '我的书架',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '全文搜索',
            onPressed: () => context.push('/search'),
          ),
        ],
      ),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('加载失败：$error')),
        data: (books) {
          if (books.isEmpty) {
            return _buildEmptyState(context, ref, loadIssue: loadIssue);
          }

          final todayStr =
              '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
          var todaySeconds = 0;
          for (final book in books) {
            if (book.lastReadDay == todayStr) {
              todaySeconds += book.readingTimeSeconds;
            }
          }

          return Column(
            children: [
              if (loadIssue != null)
                _buildLoadIssueBanner(context, ref, loadIssue),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: _buildStatsCard(context, todaySeconds),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                          sliver: SliverGrid(
                            gridDelegate: _buildGridDelegate(
                              constraints.maxWidth,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => _BookCard(book: books[index]),
                              childCount: books.length,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: hasBooks
          ? FloatingActionButton.extended(
              onPressed: () => _importBooks(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('导入书籍'),
            )
          : null,
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    WidgetRef ref, {
    String? loadIssue,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loadIssue != null) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _buildLoadIssueBanner(
                context,
                ref,
                loadIssue,
                compact: true,
              ),
            ),
            const SizedBox(height: 24),
          ],
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.menu_book_rounded,
              size: 56,
              color: colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '书架还空着',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角按钮，把电子书导入书库。',
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: () => _importBooks(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('立即导入'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadIssueBanner(
    BuildContext context,
    WidgetRef ref,
    String message, {
    bool compact = false,
  }) {
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: Theme.of(
          context,
        ).colorScheme.errorContainer.withValues(alpha: compact ? 0.88 : 1),
        borderRadius: BorderRadius.circular(compact ? 20 : 16),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 16,
            vertical: compact ? 12 : 16,
          ),
          child: Row(
            children: [
              Icon(
                compact ? Icons.error_outline : Icons.warning_amber_rounded,
                size: compact ? 20 : 24,
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(child: Text(message)),
              SizedBox(width: compact ? 8 : 12),
              TextButton(
                onPressed: () => ref.read(booksProvider.notifier).retryLoad(),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCard(BuildContext context, int todaySeconds) {
    final colorScheme = Theme.of(context).colorScheme;
    final hours = todaySeconds ~/ 3600;
    final minutes = (todaySeconds % 3600) ~/ 60;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
            child: Icon(
              Icons.auto_graph_rounded,
              color: colorScheme.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '今日阅读',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$hours',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    ' 小时 ',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '$minutes',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    ' 分钟',
                    style: TextStyle(
                      color: colorScheme.onPrimaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _importBooks(BuildContext context, WidgetRef ref) async {
    final paths = await pickBookFiles();
    if (paths == null || paths.isEmpty) return;

    await AppRunLogService.instance.logInfo('用户开始导入书籍，选择文件数：${paths.length}');
    final validPaths = paths
        .where(LibraryService.isSupportedImportPath)
        .toList();
    if (validPaths.isEmpty) {
      await AppRunLogService.instance.logInfo('导入被拒绝：无受支持文件类型');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('没有可导入的受支持文件（EPUB/PDF/MOBI/AZW3/TXT/CBZ/CBR）'),
        ),
      );
      return;
    }

    if (!context.mounted) {
      return;
    }
    final mode = await _askImportMode(context);
    if (mode == null) return;
    await AppRunLogService.instance.logInfo(
      '导入模式：${mode.name}；待导入数量：${validPaths.length}',
    );

    final notifier = ref.read(booksProvider.notifier);
    var successCount = 0;
    for (final path in validPaths) {
      try {
        await notifier.importBook(path, mode: mode);
        successCount++;
        await AppRunLogService.instance.logInfo('导入成功：$path');
      } catch (error) {
        await AppRunLogService.instance.logError('导入失败：$path; $error');
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('跳过：$error')));
        }
      }
    }

    await AppRunLogService.instance.logInfo(
      '导入流程结束，成功：$successCount/${validPaths.length}',
    );
    if (!context.mounted) return;
    if (successCount > 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('成功导入 $successCount 本书籍')));
    }
  }

  Future<ImportStorageMode?> _askImportMode(BuildContext context) {
    return showDialog<ImportStorageMode>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('导入方式'),
          content: const Text(
            '请选择导入策略：\n\n'
            '1. 另存到 App：更稳定，源文件移动或删除后仍可打开。\n'
            '2. 直接引用源文件：更省空间，但源文件路径变化后会失效。\n\n'
            '说明：若检测到系统临时路径，程序会自动改为另存到 App。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, ImportStorageMode.sourceFile),
              child: const Text('直接引用源文件'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, ImportStorageMode.appCopy),
              child: const Text('另存到 App（推荐）'),
            ),
          ],
        );
      },
    );
  }
}

class _BookCard extends ConsumerWidget {
  const _BookCard({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _openBook(context),
      onLongPress: () => _showContextMenu(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _BookCover(book: book, colorScheme: colorScheme),
          ),
          const SizedBox(height: 6),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          Text(
            book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
          if (book.readingProgress > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 4),
              child: LinearProgressIndicator(
                value: book.readingProgress,
                minHeight: 2.5,
                borderRadius: BorderRadius.circular(2),
                color: colorScheme.primary,
                backgroundColor: colorScheme.primaryContainer,
              ),
            ),
          if (book.readingTimeSeconds > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 10,
                    color: colorScheme.primary.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _formatDuration(book.readingTimeSeconds),
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.primary.withValues(alpha: 0.8),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds 秒';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes 分钟';
    final hours = minutes ~/ 60;
    final remainMinutes = minutes % 60;
    return '$hours 小时 $remainMinutes 分钟';
  }

  void _openBook(BuildContext context) {
    context.push('/reader', extra: book);
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(book.title, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _fetchMetadata(context, ref);
              },
              child: const Text('在线补全元数据'),
            ),
            TextButton(
              onPressed: () {
                ref.read(booksProvider.notifier).removeBook(book.id);
                Navigator.pop(context);
              },
              child: const Text('移出书库', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchMetadata(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('正在搜索在线元数据…')));

    final metadataService = MetadataService();
    final metadata = await metadataService.searchBestEffort(book.title);

    if (metadata == null) {
      if (context.mounted) {
        messenger.showSnackBar(const SnackBar(content: Text('未找到匹配的在线书籍信息')));
      }
      metadataService.dispose();
      return;
    }

    var localCoverPath = book.coverPath;
    if (metadata.coverUrl != null && metadata.coverUrl!.isNotEmpty) {
      localCoverPath =
          await metadataService.downloadCover(metadata.coverUrl!, book.id) ??
          book.coverPath;
    }

    final updatedBook = book.copyWith(
      title: metadata.title,
      author: metadata.author.isNotEmpty ? metadata.author : book.author,
      coverPath: localCoverPath,
      tags: metadata.tags.isNotEmpty ? metadata.tags : book.tags,
    );

    await ref.read(booksProvider.notifier).updateBook(updatedBook);
    metadataService.dispose();

    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('元数据与封面已更新')));
  }
}

class _BookCover extends StatelessWidget {
  const _BookCover({required this.book, required this.colorScheme});

  final Book book;
  final ColorScheme colorScheme;

  static const _formatColors = {
    BookFormat.epub: [Color(0xFF4A6FA5), Color(0xFF2C4A7C)],
    BookFormat.pdf: [Color(0xFFE53935), Color(0xFFC62828)],
    BookFormat.mobi: [Color(0xFF43A047), Color(0xFF2E7D32)],
    BookFormat.azw3: [Color(0xFF8E24AA), Color(0xFF6A1B9A)],
    BookFormat.cbz: [Color(0xFFFB8C00), Color(0xFFE65100)],
    BookFormat.cbr: [Color(0xFFFB8C00), Color(0xFFE65100)],
    BookFormat.txt: [Color(0xFF78909C), Color(0xFF455A64)],
    BookFormat.unknown: [Color(0xFF90A4AE), Color(0xFF607D8B)],
  };

  @override
  Widget build(BuildContext context) {
    final colors =
        _formatColors[book.format] ??
        const [Color(0xFF90A4AE), Color(0xFF607D8B)];

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
          ),
          if (book.coverPath != null)
            Image.file(
              File(book.coverPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _formatIcon(),
            )
          else
            _formatIcon(),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Text(
                book.format.name.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _formatIcon() {
    final iconData = switch (book.format) {
      BookFormat.pdf => Icons.picture_as_pdf,
      BookFormat.cbz || BookFormat.cbr => Icons.auto_stories,
      BookFormat.txt => Icons.text_snippet,
      _ => Icons.book,
    };

    return Center(
      child: Icon(
        iconData,
        size: 42,
        color: Colors.white.withValues(alpha: 0.9),
      ),
    );
  }
}
