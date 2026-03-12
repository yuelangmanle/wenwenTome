import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/reader/utils/text_paginator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextPaginator', () {
    test('splits long prose into ordered pages with stable offsets', () {
      final text = List<String>.generate(
        24,
        (index) => '第${index + 1}段：这是用于分页测试的正文内容，会重复多次以保证页面足够长，并且在结尾保留标点。',
      ).join('\n\n');

      final result = TextPaginator.paginate(
        text: text,
        style: const TextStyle(fontSize: 18, height: 1.6),
        size: const Size(240, 180),
      );

      expect(result.pages.length, greaterThan(1));
      expect(result.pages.first.startOffset, 0);
      expect(result.pages.last.endOffset, text.length);
      expect(result.pages.map((page) => page.text).join(), text);

      for (var index = 1; index < result.pages.length; index++) {
        expect(
          result.pages[index - 1].endOffset,
          result.pages[index].startOffset,
        );
      }
    });

    test('maps offsets back to the containing page', () {
      const text = '第一页文本。\n\n第二页文本。\n\n第三页文本。';

      final result = TextPaginator.paginate(
        text: text,
        style: const TextStyle(fontSize: 22, height: 1.7),
        size: const Size(180, 90),
      );

      expect(result.pages.length, greaterThanOrEqualTo(2));
      expect(result.pageIndexForOffset(0), 0);
      expect(result.pageIndexForOffset(text.length), result.pages.length - 1);
      expect(
        result.pageIndexForOffset(result.pages.last.startOffset),
        result.pages.length - 1,
      );
    });
  });
}
