import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' show parse;

import '../library/data/book_model.dart';
import '../reader/book_text_loader.dart';
import '../reader/reader_pdf_service.dart';

class TocEntry {
  const TocEntry({
    required this.title,
    required this.position,
    this.level = 1,
    this.children = const [],
  });

  final String title;
  final int position;
  final int level;
  final List<TocEntry> children;
}

class SearchResult {
  const SearchResult({
    required this.bookId,
    required this.excerpt,
    required this.position,
    required this.pageNumber,
    required this.matchText,
  });

  final String bookId;
  final String excerpt;
  final int position;
  final int pageNumber;
  final String matchText;
}

class TextTocParser {
  static final _chapterRegex = RegExp(
    r'^(第[零一二三四五六七八九十百千万两〇\d]+[章节卷回集部篇]|Chapter\s+\d+|CHAPTER\s+\d+)',
    multiLine: true,
    caseSensitive: false,
  );

  static List<TocEntry> parse(String content) {
    final matches = _chapterRegex.allMatches(content);
    return matches
        .map((m) => TocEntry(title: m.group(0)!.trim(), position: m.start))
        .toList();
  }

  static List<SearchResult> search(
    String bookId,
    String content,
    String query,
  ) {
    if (query.isEmpty) {
      return const <SearchResult>[];
    }
    final results = <SearchResult>[];
    final lowerContent = content.toLowerCase();
    final lowerQuery = query.toLowerCase();
    var index = 0;

    while (true) {
      final position = lowerContent.indexOf(lowerQuery, index);
      if (position == -1) {
        break;
      }

      final start = (position - 60).clamp(0, content.length);
      final end = (position + query.length + 60).clamp(0, content.length);
      final excerpt = content.substring(start, end).replaceAll('\n', ' ');

      results.add(
        SearchResult(
          bookId: bookId,
          excerpt: excerpt,
          position: position,
          pageNumber: 0,
          matchText: content.substring(position, position + query.length),
        ),
      );

      index = position + 1;
      if (results.length >= 50) {
        break;
      }
    }
    return results;
  }
}

class FullTextSearch {
  static Future<List<SearchResult>> searchInBook(
    Book book,
    String query,
  ) async {
    if (query.trim().isEmpty) {
      return const <SearchResult>[];
    }

    return compute(_searchWorker, {
      'bookId': book.id,
      'filePath': book.filePath,
      'format': book.format.name,
      'query': query,
    });
  }

  static Future<List<SearchResult>> _searchWorker(
    Map<String, dynamic> args,
  ) async {
    final bookId = args['bookId'] as String;
    final filePath = args['filePath'] as String;
    final format = args['format'] as String;
    final query = args['query'] as String;

    try {
      if (format == 'txt') {
        final decoded = await BookTextLoader.readTextFile(filePath);
        return TextTocParser.search(bookId, decoded.text, query);
      }

      if (format == 'epub') {
        final bytes = await File(filePath).readAsBytes();
        final epubBook = await EpubReader.readBook(bytes);
        final results = <SearchResult>[];

        if (epubBook.Chapters != null) {
          for (var i = 0; i < epubBook.Chapters!.length; i++) {
            final chapter = epubBook.Chapters![i];
            final content = parse(chapter.HtmlContent ?? '').body?.text ?? '';
            results.addAll(
              TextTocParser.search(bookId, content, query).map(
                (item) => SearchResult(
                  bookId: item.bookId,
                  excerpt: item.excerpt,
                  position: i,
                  pageNumber: i,
                  matchText: item.matchText,
                ),
              ),
            );
            if (results.length >= 50) {
              return results.take(50).toList(growable: false);
            }
          }
        }
        return results;
      }

      if (format == 'pdf') {
        final matches = await ReaderPdfService.searchText(filePath, query);
        return matches
            .map(
              (item) => SearchResult(
                bookId: bookId,
                excerpt: item.excerpt,
                position: item.position,
                pageNumber: item.pageNumber,
                matchText: item.matchText,
              ),
            )
            .toList(growable: false);
      }

      return const <SearchResult>[];
    } catch (_) {
      return const <SearchResult>[];
    }
  }

  static Future<List<TocEntry>> extractToc(Book book) async {
    if (book.format != BookFormat.txt) {
      return const <TocEntry>[];
    }
    try {
      final decoded = await BookTextLoader.readTextFile(book.filePath);
      return TextTocParser.parse(decoded.text);
    } catch (_) {
      return const <TocEntry>[];
    }
  }
}
