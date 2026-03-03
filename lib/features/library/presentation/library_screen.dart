import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../data/book_model.dart';
import '../providers/library_providers.dart';
import '../../reader/presentation/reader_screen.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(booksProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的书架', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: '同步',
            onPressed: () => context.push('/sync'),
          ),
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: '全文搜索',
            onPressed: () => context.push('/search'),
          ),
          IconButton(icon: const Icon(Icons.settings_outlined), onPressed: () {}),
        ],
      ),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (books) {
          if (books.isEmpty) return _buildEmptyState();
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.65,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: books.length,
            itemBuilder: (ctx, i) => _BookCard(book: books[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _importBooks(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('导入书籍'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.menu_book_rounded, size: 80, color: Colors.grey),
          SizedBox(height: 16),
          Text('书架空空如也', style: TextStyle(fontSize: 18, color: Colors.grey)),
          SizedBox(height: 8),
          Text('点击右下角按钮导入书籍', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Future<void> _importBooks(BuildContext context, WidgetRef ref) async {
    final paths = await pickBookFiles();
    if (paths == null || paths.isEmpty) return;

    final notifier = ref.read(booksProvider.notifier);
    int success = 0;
    for (final path in paths) {
      try {
        await notifier.importBook(path);
        success++;
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('跳过：$e'), duration: const Duration(seconds: 2)),
          );
        }
      }
    }
    if (context.mounted && success > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成功导入 $success 本书籍 ✓')),
      );
    }
  }
}

class _BookCard extends ConsumerWidget {
  final Book book;
  const _BookCard({required this.book});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
      ),
      onLongPress: () => _showContextMenu(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: book.coverPath != null
                  ? Image.asset(book.coverPath!, fit: BoxFit.cover, width: double.infinity)
                  : Container(
                      color: colorScheme.primaryContainer,
                      child: Center(
                        child: Icon(_formatIcon(book.format), size: 40,
                            color: colorScheme.onPrimaryContainer),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withValues(alpha: 0.6))),
          if (book.readingProgress > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: book.readingProgress,
                minHeight: 2,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }

  IconData _formatIcon(BookFormat fmt) {
    switch (fmt) {
      case BookFormat.pdf: return Icons.picture_as_pdf;
      case BookFormat.cbz:
      case BookFormat.cbr: return Icons.auto_stories;
      case BookFormat.txt: return Icons.text_snippet;
      default:             return Icons.book;
    }
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(book.title, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            child: const Text('移出书库', style: TextStyle(color: Colors.red)),
            onPressed: () {
              ref.read(booksProvider.notifier).removeBook(book.id);
              Navigator.pop(ctx);
            },
          ),
          TextButton(child: const Text('取消'), onPressed: () => Navigator.pop(ctx)),
        ],
      ),
    );
  }
}
