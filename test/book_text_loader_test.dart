import 'dart:convert';

import 'package:charset/charset.dart' as charset;
import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/reader/book_text_loader.dart';

void main() {
  group('BookTextLoader', () {
    test('decodes utf-8 text directly', () {
      final result = BookTextLoader.decodeBytes(utf8.encode('第一章 测试'));

      expect(result.text, '第一章 测试');
      expect(result.encoding, 'utf-8');
    });

    test('falls back to gbk for legacy chinese text files', () {
      final bytes = charset.gbk.encode('圣墟 第十章');
      final result = BookTextLoader.decodeBytes(bytes);

      expect(result.text, '圣墟 第十章');
      expect(result.encoding, 'gb18030');
    });

    test('handles utf-16 text with bom', () {
      final bytes = <int>[0xFF, 0xFE, 0x2C, 0x7B, 0x41, 0x53];
      final result = BookTextLoader.decodeBytes(bytes);

      expect(result.text, '第十');
      expect(result.encoding, 'utf-16le');
    });

    test('prefers utf-8 for normal chinese prose without bom', () {
      const text = '第一章 山风穿过旧城，少年抬头看见天边的云，心里忽然安静下来。';
      final result = BookTextLoader.decodeBytes(utf8.encode(text));

      expect(result.text, text);
      expect(result.encoding, 'utf-8');
    });
  });
}
