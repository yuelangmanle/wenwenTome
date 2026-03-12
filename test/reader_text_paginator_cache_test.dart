import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/reader/utils/text_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextPaginator cache', () {
    test('reuses pagination result when cache key matches', () {
      TextPaginator.clearCache();
      final text = List<String>.generate(
        80,
        (index) =>
            'Paragraph ${index + 1}. This is a stable pagination sample.',
      ).join('\n\n');

      final first = TextPaginator.paginate(
        text: text,
        style: const TextStyle(fontSize: 18, height: 1.6),
        size: const Size(240, 180),
        cacheKey: 'reader-cache-1',
      );
      final second = TextPaginator.paginate(
        text: text,
        style: const TextStyle(fontSize: 18, height: 1.6),
        size: const Size(240, 180),
        cacheKey: 'reader-cache-1',
      );

      expect(identical(first, second), isTrue);
      expect(first.pages, isNotEmpty);
    });

    test('does not reuse cache for different input length', () {
      TextPaginator.clearCache();
      final a = TextPaginator.paginate(
        text: 'A short sample',
        style: const TextStyle(fontSize: 16, height: 1.5),
        size: const Size(220, 160),
        cacheKey: 'reader-cache-2',
      );
      final b = TextPaginator.paginate(
        text: 'A short sample with extra suffix',
        style: const TextStyle(fontSize: 16, height: 1.5),
        size: const Size(220, 160),
        cacheKey: 'reader-cache-2',
      );

      expect(identical(a, b), isFalse);
    });
  });
}
