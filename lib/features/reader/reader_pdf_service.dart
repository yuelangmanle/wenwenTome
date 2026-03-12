import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

class ReaderPdfSearchMatch {
  const ReaderPdfSearchMatch({
    required this.pageNumber,
    required this.position,
    required this.excerpt,
    required this.matchText,
  });

  final int pageNumber;
  final int position;
  final String excerpt;
  final String matchText;
}

class ReaderPdfOutlineEntry {
  const ReaderPdfOutlineEntry({required this.title, required this.pageNumber});

  final String title;
  final int pageNumber;
}

class ReaderPdfService {
  static Future<int> validateDocument(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('PDF 文件不存在');
    }

    final document = await PdfDocument.openFile(filePath);
    try {
      final pageCount = document.pages.length;
      if (pageCount <= 0) {
        throw Exception('PDF 页面数量为 0');
      }
      return pageCount;
    } finally {
      await document.dispose();
    }
  }

  static Future<List<ReaderPdfOutlineEntry>> loadOutline(
    String filePath,
  ) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('PDF 文件不存在');
    }

    final document = await PdfDocument.openFile(filePath);
    try {
      final pageCount = document.pages.length;
      final nodes = await document.loadOutline();
      return _flattenAndNormalizeOutline(nodes, pageCount: pageCount);
    } finally {
      await document.dispose();
    }
  }

  @visibleForTesting
  static List<ReaderPdfOutlineEntry> flattenAndNormalizeOutlineForTest(
    List<PdfOutlineNode> nodes, {
    required int pageCount,
  }) {
    return _flattenAndNormalizeOutline(nodes, pageCount: pageCount);
  }

  static List<ReaderPdfOutlineEntry> _flattenAndNormalizeOutline(
    List<PdfOutlineNode> nodes, {
    required int pageCount,
  }) {
    if (nodes.isEmpty || pageCount <= 0) {
      return const <ReaderPdfOutlineEntry>[];
    }

    final rawPageNumbers = <int>[];
    void gather(List<PdfOutlineNode> items) {
      for (final item in items) {
        final dest = item.dest;
        if (dest != null) {
          rawPageNumbers.add(dest.pageNumber);
        }
        gather(item.children);
      }
    }

    gather(nodes);

    final hasZero = rawPageNumbers.any((value) => value == 0);
    final maxRaw = rawPageNumbers.isEmpty
        ? 0
        : rawPageNumbers.reduce((a, b) => a > b ? a : b);
    final shift =
        hasZero && maxRaw <= math.max(0, pageCount - 1) ? 1 : 0;

    int normalize(int raw) {
      final candidate = raw + shift;
      if (candidate <= 0) {
        return 1;
      }
      if (candidate > pageCount) {
        return pageCount;
      }
      return candidate;
    }

    final entries = <ReaderPdfOutlineEntry>[];
    void visit(List<PdfOutlineNode> items) {
      for (final item in items) {
        final title = item.title.trim();
        final dest = item.dest;
        final pageNumber = normalize(dest?.pageNumber ?? 1);
        if (title.isNotEmpty) {
          entries.add(
            ReaderPdfOutlineEntry(title: title, pageNumber: pageNumber),
          );
        }
        visit(item.children);
      }
    }

    visit(nodes);
    return List<ReaderPdfOutlineEntry>.unmodifiable(entries);
  }

  static Future<List<ReaderPdfSearchMatch>> searchText(
    String filePath,
    String query,
  ) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return const <ReaderPdfSearchMatch>[];
    }

    final document = await PdfDocument.openFile(filePath);
    try {
      final results = <ReaderPdfSearchMatch>[];
      final lowerQuery = normalizedQuery.toLowerCase();

      for (final page in document.pages) {
        final pageText = await page.loadText();
        final text = pageText.fullText;
        final lowerText = text.toLowerCase();
        var offset = 0;
        while (true) {
          final index = lowerText.indexOf(lowerQuery, offset);
          if (index < 0) {
            break;
          }
          final start = (index - 60).clamp(0, text.length);
          final end = (index + normalizedQuery.length + 60).clamp(
            0,
            text.length,
          );
          results.add(
            ReaderPdfSearchMatch(
              pageNumber: page.pageNumber,
              position: index,
              excerpt: text.substring(start, end).replaceAll('\n', ' '),
              matchText: text.substring(index, index + normalizedQuery.length),
            ),
          );
          offset = index + 1;
          if (results.length >= 50) {
            return results;
          }
        }
      }

      return results;
    } finally {
      await document.dispose();
    }
  }
}
