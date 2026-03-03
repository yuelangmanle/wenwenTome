import 'dart:io';
import 'package:flutter/foundation.dart';
import '../library/data/book_model.dart';

/// 章节条目
class TocEntry {
  final String title;
  final int position;    // 字符偏移 / 页码
  final int level;       // 嵌套级别（h1=1, h2=2...）
  final List<TocEntry> children;

  const TocEntry({
    required this.title,
    required this.position,
    this.level = 1,
    this.children = const [],
  });
}

/// 全文搜索结果
class SearchResult {
  final String bookId;
  final String excerpt;     // 匹配周围的上下文片段
  final int position;       // 匹配位置
  final int pageNumber;
  final String matchText;   // 精确匹配到的文字

  const SearchResult({
    required this.bookId,
    required this.excerpt,
    required this.position,
    required this.pageNumber,
    required this.matchText,
  });
}

/// TXT 章节识别引擎（正则）
class TextTocParser {
  static final _chapterRegex = RegExp(
    r'^(第[零一二三四五六七八九十百千万\d]+[章节回集部卷]|Chapter\s+\d+|第\d+章|CHAPTER\s+\d+)',
    multiLine: true,
    caseSensitive: false,
  );

  static List<TocEntry> parse(String content) {
    final matches = _chapterRegex.allMatches(content);
    return matches.map((m) => TocEntry(
      title: m.group(0)!.trim(),
      position: m.start,
    )).toList();
  }

  static List<SearchResult> search(String bookId, String content, String query) {
    if (query.isEmpty) return [];
    final results = <SearchResult>[];
    final lowerContent = content.toLowerCase();
    final lowerQuery = query.toLowerCase();
    int idx = 0;

    while (true) {
      final pos = lowerContent.indexOf(lowerQuery, idx);
      if (pos == -1) break;

      // 截取前后 60 字作为摘要
      final start = (pos - 60).clamp(0, content.length);
      final end = (pos + query.length + 60).clamp(0, content.length);
      final excerpt = content.substring(start, end).replaceAll('\n', ' ');

      results.add(SearchResult(
        bookId: bookId,
        excerpt: excerpt,
        position: pos,
        pageNumber: 0,
        matchText: content.substring(pos, pos + query.length),
      ));

      idx = pos + 1;
      if (results.length >= 50) break; // 最多返回50条
    }
    return results;
  }
}

/// 书库全文索引服务（轻量级本地搜索）
class FullTextSearch {
  /// 对单本书进行全文搜索
  static Future<List<SearchResult>> searchInBook(Book book, String query) async {
    if (query.trim().isEmpty) return [];

    return compute(_searchWorker, {
      'bookId': book.id,
      'filePath': book.filePath,
      'format': book.format.name,
      'query': query,
    });
  }

  static Future<List<SearchResult>> _searchWorker(Map<String, dynamic> args) async {
    final bookId = args['bookId'] as String;
    final filePath = args['filePath'] as String;
    final format = args['format'] as String;
    final query = args['query'] as String;

    try {
      if (format == 'txt') {
        final content = await File(filePath).readAsString();
        return TextTocParser.search(bookId, content, query);
      }
      // EPUB/PDF 全文搜索需解包文本层，暂用文件名占位
      return [
        SearchResult(
          bookId: bookId,
          excerpt: '[$format 格式全文索引正在开发中...]',
          position: 0,
          pageNumber: 0,
          matchText: query,
        )
      ];
    } catch (_) {
      return [];
    }
  }

  /// TXT 书籍章节目录提取
  static Future<List<TocEntry>> extractToc(Book book) async {
    if (book.format != BookFormat.txt) return [];
    try {
      final content = await File(book.filePath).readAsString();
      return TextTocParser.parse(content);
    } catch (_) {
      return [];
    }
  }
}
