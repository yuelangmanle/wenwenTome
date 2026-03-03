import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'annotation_service.dart';

final annotationServiceProvider = Provider<AnnotationService>((ref) => AnnotationService());

// ── 高亮笔记 ──

final annotationsProvider = FutureProvider.family<List<Annotation>, String>(
  (ref, bookId) => ref.read(annotationServiceProvider).loadAnnotations(bookId),
);

final annotationsNotifierProvider =
    AsyncNotifierProviderFamily<AnnotationsNotifier, List<Annotation>, String>(
  AnnotationsNotifier.new,
);

class AnnotationsNotifier extends FamilyAsyncNotifier<List<Annotation>, String> {
  @override
  Future<List<Annotation>> build(String bookId) =>
      ref.read(annotationServiceProvider).loadAnnotations(bookId);

  Future<void> add({
    required String selectedText,
    String? note,
    HighlightColor color = HighlightColor.yellow,
    int cfiStart = 0,
    int cfiEnd = 0,
    int pageNumber = 0,
  }) async {
    await ref.read(annotationServiceProvider).addAnnotation(
      bookId: arg,
      selectedText: selectedText,
      note: note,
      color: color,
      cfiStart: cfiStart,
      cfiEnd: cfiEnd,
      pageNumber: pageNumber,
    );
    ref.invalidateSelf();
    await future;
  }

  Future<void> update(String id, {String? note, HighlightColor? color}) async {
    await ref.read(annotationServiceProvider).updateAnnotation(id, note: note, color: color);
    ref.invalidateSelf();
    await future;
  }

  Future<void> delete(String id) async {
    await ref.read(annotationServiceProvider).deleteAnnotation(id);
    ref.invalidateSelf();
    await future;
  }
}

// ── 书签 ──

final bookmarksProvider =
    FutureProvider.family<List<Bookmark>, String>(
  (ref, bookId) => ref.read(annotationServiceProvider).loadBookmarks(bookId),
);
