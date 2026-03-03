import 'dart:io';
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('我的书架', style: TextStyle(fontWeight: FontWeight.bold)),
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
        error: (e, _) => Center(child: Text('加载失败: $e')),
        data: (books) {
          if (books.isEmpty) return _buildEmptyState(context);
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.62,
              crossAxisSpacing: 12,
              mainAxisSpacing: 16,
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
        elevation: 3,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 120, height: 120,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.menu_book_rounded, size: 56, color: cs.primary.withValues(alpha: 0.7)),
        ),
        const SizedBox(height: 24),
        Text('书架空空如也', style: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w600,
          color: cs.onSurface.withValues(alpha: 0.7))),
        const SizedBox(height: 8),
        Text('点击右下角按钮，将电子书导入书库', style: TextStyle(
          fontSize: 14, color: cs.onSurface.withValues(alpha: 0.45))),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('立即导入'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
        ),
      ]),
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
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _openBook(context),
      onLongPress: () => _showContextMenu(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _BookCover(book: book, cs: cs),
          ),
          const SizedBox(height: 6),
          Text(book.title,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, height: 1.3)),
          Text(book.author,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.55))),
          if (book.readingProgress > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: LinearProgressIndicator(
                value: book.readingProgress,
                minHeight: 2.5,
                borderRadius: BorderRadius.circular(2),
                color: cs.primary,
                backgroundColor: cs.primaryContainer,
              ),
            ),
        ],
      ),
    );
  }

  void _openBook(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderScreen(book: book),
    ));
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

// 书籍封面组件（支持封面图 + 格式色块 + 渐变蒙版）
class _BookCover extends StatelessWidget {
  final Book book;
  final ColorScheme cs;
  const _BookCover({required this.book, required this.cs});

  static const _formatColors = {
    BookFormat.epub:  [Color(0xFF4A6FA5), Color(0xFF2C4A7C)],
    BookFormat.pdf:   [Color(0xFFE53935), Color(0xFFC62828)],
    BookFormat.mobi:  [Color(0xFF43A047), Color(0xFF2E7D32)],
    BookFormat.azw3:  [Color(0xFF8E24AA), Color(0xFF6A1B9A)],
    BookFormat.cbz:   [Color(0xFFFB8C00), Color(0xFFE65100)],
    BookFormat.cbr:   [Color(0xFFFB8C00), Color(0xFFE65100)],
    BookFormat.txt:   [Color(0xFF78909C), Color(0xFF455A64)],
    BookFormat.unknown: [Color(0xFF90A4AE), Color(0xFF607D8B)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _formatColors[book.format] ??
        [const Color(0xFF90A4AE), const Color(0xFF607D8B)];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景色块（封面图加载前/无封面时）
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: colors,
                ),
              ),
            ),
            // 封面图（若存在）
            if (book.coverPath != null)
              Image.file(
                File(book.coverPath!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _formatIcon(),
              )
            else
              _formatIcon(),
            // 底部渐变蒙版（体现格式徽章）
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 16, 6, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.6), Colors.transparent],
                  ),
                ),
                child: Text(
                  book.format.name.toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatIcon() {
    final iconData = () {
      switch (book.format) {
        case BookFormat.pdf: return Icons.picture_as_pdf;
        case BookFormat.cbz:
        case BookFormat.cbr: return Icons.auto_stories;
        case BookFormat.txt: return Icons.text_snippet;
        default: return Icons.book;
      }
    }();
    return Center(child: Icon(iconData, size: 42, color: Colors.white.withValues(alpha: 0.9)));
  }
}

