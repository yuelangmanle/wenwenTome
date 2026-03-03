import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'annotation_service.dart';

final annotationServiceProvider = Provider<AnnotationService>((ref) => AnnotationService());

// ── 高亮笔记 ──
// 使用 FutureProvider.family 来按书 ID 加载笔记（简单可靠）

final annotationsProvider = FutureProvider.family<List<Annotation>, String>(
  (ref, bookId) => ref.read(annotationServiceProvider).loadAnnotations(bookId),
);

// 用于写操作的 StateNotifier，按书 ID 分组
final annotationActionsProvider = Provider<AnnotationActions>((ref) {
  return AnnotationActions(ref.read(annotationServiceProvider), ref);
});

class AnnotationActions {
  final AnnotationService _service;
  final Ref _ref;
  AnnotationActions(this._service, this._ref);

  Future<void> add({
    required String bookId,
    required String selectedText,
    String? note,
    HighlightColor color = HighlightColor.yellow,
    int cfiStart = 0,
    int cfiEnd = 0,
    int pageNumber = 0,
  }) async {
    await _service.addAnnotation(
      bookId: bookId,
      selectedText: selectedText,
      note: note,
      color: color,
      cfiStart: cfiStart,
      cfiEnd: cfiEnd,
      pageNumber: pageNumber,
    );
    _ref.invalidate(annotationsProvider(bookId));
  }

  Future<void> update(String bookId, String id, {String? note, HighlightColor? color}) async {
    await _service.updateAnnotation(id, note: note, color: color);
    _ref.invalidate(annotationsProvider(bookId));
  }

  Future<void> delete(String bookId, String id) async {
    await _service.deleteAnnotation(id);
    _ref.invalidate(annotationsProvider(bookId));
  }
}

// ── 书签 ──

final bookmarksProvider = FutureProvider.family<List<Bookmark>, String>(
  (ref, bookId) => ref.read(annotationServiceProvider).loadBookmarks(bookId),
);
