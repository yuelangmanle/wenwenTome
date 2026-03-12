import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../annotation_service.dart';
import '../annotation_providers.dart';

/// 书籍笔记总览页面 - 展示某本书的所有高亮和书签
class AnnotationsScreen extends ConsumerWidget {
  final String bookId;
  final String bookTitle;
  const AnnotationsScreen({super.key, required this.bookId, required this.bookTitle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final annotationsAsync = ref.watch(annotationsProvider(bookId));
    final bookmarksAsync = ref.watch(bookmarksProvider(bookId));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(bookTitle, overflow: TextOverflow.ellipsis),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.highlight), text: '高亮笔记'),
            Tab(icon: Icon(Icons.bookmark), text: '书签'),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: '导出笔记',
              onPressed: () {/* TODO: 导出 Markdown */},
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _AnnotationList(annotationsAsync: annotationsAsync, ref: ref),
            _BookmarkList(bookmarksAsync: bookmarksAsync, ref: ref, bookId: bookId),
          ],
        ),
      ),
    );
  }
}

class _AnnotationList extends StatelessWidget {
  final AsyncValue<List<Annotation>> annotationsAsync;
  final WidgetRef ref;
  const _AnnotationList({required this.annotationsAsync, required this.ref});

  @override
  Widget build(BuildContext context) {
    return annotationsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('还没有高亮笔记\n阅读时长按文字可划线添加',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (ctx, i) => _AnnotationCard(annotation: list[i], ref: ref),
        );
      },
    );
  }
}

class _AnnotationCard extends StatelessWidget {
  final Annotation annotation;
  final WidgetRef ref;
  const _AnnotationCard({required this.annotation, required this.ref});

  static const _colorMap = {
    HighlightColor.yellow: Color(0xFFFFF176),
    HighlightColor.green:  Color(0xFFA5D6A7),
    HighlightColor.blue:   Color(0xFF90CAF9),
    HighlightColor.pink:   Color(0xFFF48FB1),
    HighlightColor.purple: Color(0xFFCE93D8),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colorMap[annotation.color] ?? Colors.yellow;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 高亮原文
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: color, width: 4)),
            ),
            child: Text(annotation.selectedText,
                style: const TextStyle(fontSize: 14, height: 1.5)),
          ),
          // 笔记内容
          if (annotation.note != null && annotation.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 12),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(child: Text(annotation.note!,
                      style: const TextStyle(color: Colors.grey, fontSize: 13))),
                ],
              ),
            ),
          // 操作行
          Row(
            children: [
              Text(
                '第${annotation.pageNumber + 1}章  ·  ${_formatDate(annotation.createdAt)}',
                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.grey,
                onPressed: () => ref.read(annotationActionsProvider)
                    .delete(annotation.bookId, annotation.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

class _BookmarkList extends StatelessWidget {
  final AsyncValue<List<Bookmark>> bookmarksAsync;
  final WidgetRef ref;
  final String bookId;
  const _BookmarkList({required this.bookmarksAsync, required this.ref, required this.bookId});

  @override
  Widget build(BuildContext context) {
    return bookmarksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (list) {
        if (list.isEmpty) {
          return const Center(child: Text('还没有书签\n点击阅读器工具栏 🔖 可添加书签',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (ctx, i) {
            final bm = list[i];
            return ListTile(
              leading: const Icon(Icons.bookmark, color: Colors.amber),
              title: Text(bm.title),
              subtitle: Text('位置: ${bm.position}'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => ref.read(annotationServiceProvider).deleteBookmark(bm.id),
              ),
            );
          },
        );
      },
    );
  }
}
