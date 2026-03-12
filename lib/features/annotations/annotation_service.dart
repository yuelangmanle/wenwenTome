import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';

import '../../core/storage/app_storage_paths.dart';

enum HighlightColor { yellow, green, blue, pink, purple }

/// 高亮/笔记模型
class Annotation {
  final String id;
  final String bookId;
  final String selectedText;   // 被划选的原文
  final String? note;          // 用户的笔记文字（可选）
  final HighlightColor color;
  final int cfiStart;          // EPUB CFI 位置（或字符偏移）
  final int cfiEnd;
  final int pageNumber;        // PDF 页码（EPUB 章节索引）
  final DateTime createdAt;

  const Annotation({
    required this.id,
    required this.bookId,
    required this.selectedText,
    this.note,
    required this.color,
    required this.cfiStart,
    required this.cfiEnd,
    required this.pageNumber,
    required this.createdAt,
  });

  Annotation copyWith({String? note, HighlightColor? color}) => Annotation(
    id: id,
    bookId: bookId,
    selectedText: selectedText,
    note: note ?? this.note,
    color: color ?? this.color,
    cfiStart: cfiStart,
    cfiEnd: cfiEnd,
    pageNumber: pageNumber,
    createdAt: createdAt,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'selectedText': selectedText,
    'note': note,
    'color': color.name,
    'cfiStart': cfiStart,
    'cfiEnd': cfiEnd,
    'pageNumber': pageNumber,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Annotation.fromJson(Map<String, dynamic> json) => Annotation(
    id: json['id'],
    bookId: json['bookId'],
    selectedText: json['selectedText'],
    note: json['note'],
    color: HighlightColor.values.firstWhere(
      (c) => c.name == json['color'],
      orElse: () => HighlightColor.yellow,
    ),
    cfiStart: json['cfiStart'] ?? 0,
    cfiEnd: json['cfiEnd'] ?? 0,
    pageNumber: json['pageNumber'] ?? 0,
    createdAt: DateTime.parse(json['createdAt']),
  );
}

/// 书签模型
class Bookmark {
  final String id;
  final String bookId;
  final String title;        // 用户给书签起的名字（或者自动截取章节标题）
  final int position;        // 字符偏移 / 页码
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.bookId,
    required this.title,
    required this.position,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'bookId': bookId,
    'title': title,
    'position': position,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'],
    bookId: json['bookId'],
    title: json['title'],
    position: json['position'] ?? 0,
    createdAt: DateTime.parse(json['createdAt']),
  );
}

/// 高亮笔记 + 书签持久化服务
class AnnotationService {
  static const _annotationFile = 'annotations.json';
  static const _bookmarkFile = 'bookmarks.json';
  static final _uuid = Uuid();

  Future<File> _getFile(String name) async {
    final dir = await getSafeApplicationDocumentsDirectory();
    return File('${dir.path}/wenwen_tome/$name');
  }

  // ─── 高亮笔记 ───

  Future<List<Annotation>> loadAnnotations(String bookId) async {
    try {
      final file = await _getFile(_annotationFile);
      if (!await file.exists()) return [];
      final all = (jsonDecode(await file.readAsString()) as List)
          .map((j) => Annotation.fromJson(j))
          .toList();
      return all.where((a) => a.bookId == bookId).toList()
        ..sort((a, b) => a.cfiStart.compareTo(b.cfiStart));
    } catch (_) {
      return [];
    }
  }

  Future<List<Annotation>> loadAllAnnotations() async {
    try {
      final file = await _getFile(_annotationFile);
      if (!await file.exists()) return [];
      return (jsonDecode(await file.readAsString()) as List)
          .map((j) => Annotation.fromJson(j))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Annotation> addAnnotation({
    required String bookId,
    required String selectedText,
    String? note,
    HighlightColor color = HighlightColor.yellow,
    int cfiStart = 0,
    int cfiEnd = 0,
    int pageNumber = 0,
  }) async {
    final all = await loadAllAnnotations();
    final annotation = Annotation(
      id: _uuid.v4(),
      bookId: bookId,
      selectedText: selectedText,
      note: note,
      color: color,
      cfiStart: cfiStart,
      cfiEnd: cfiEnd,
      pageNumber: pageNumber,
      createdAt: DateTime.now(),
    );
    all.add(annotation);
    await _saveAnnotations(all);
    return annotation;
  }

  Future<void> updateAnnotation(String id, {String? note, HighlightColor? color}) async {
    final all = await loadAllAnnotations();
    final idx = all.indexWhere((a) => a.id == id);
    if (idx == -1) return;
    all[idx] = all[idx].copyWith(note: note, color: color);
    await _saveAnnotations(all);
  }

  Future<void> deleteAnnotation(String id) async {
    final all = await loadAllAnnotations();
    all.removeWhere((a) => a.id == id);
    await _saveAnnotations(all);
  }

  Future<void> _saveAnnotations(List<Annotation> list) async {
    final file = await _getFile(_annotationFile);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(list.map((a) => a.toJson()).toList()));
  }

  // ─── 书签 ───

  Future<List<Bookmark>> loadBookmarks(String bookId) async {
    try {
      final file = await _getFile(_bookmarkFile);
      if (!await file.exists()) return [];
      final all = (jsonDecode(await file.readAsString()) as List)
          .map((j) => Bookmark.fromJson(j))
          .toList();
      return all.where((b) => b.bookId == bookId).toList()
        ..sort((a, b) => a.position.compareTo(b.position));
    } catch (_) {
      return [];
    }
  }

  Future<Bookmark> addBookmark({
    required String bookId,
    required String title,
    required int position,
  }) async {
    final file = await _getFile(_bookmarkFile);
    List<Bookmark> all = [];
    if (await file.exists()) {
      all = (jsonDecode(await file.readAsString()) as List)
          .map((j) => Bookmark.fromJson(j))
          .toList();
    }
    final bookmark = Bookmark(
      id: _uuid.v4(),
      bookId: bookId,
      title: title,
      position: position,
      createdAt: DateTime.now(),
    );
    all.add(bookmark);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(all.map((b) => b.toJson()).toList()));
    return bookmark;
  }

  Future<void> deleteBookmark(String id) async {
    final file = await _getFile(_bookmarkFile);
    if (!await file.exists()) return;
    final all = (jsonDecode(await file.readAsString()) as List)
        .map((j) => Bookmark.fromJson(j))
        .where((b) => b.id != id)
        .toList();
    await file.writeAsString(jsonEncode(all.map((b) => b.toJson()).toList()));
  }
}
