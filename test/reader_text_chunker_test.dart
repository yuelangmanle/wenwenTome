import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/reader/text_render_chunker.dart';

void main() {
  group('ReaderTextChunker', () {
    test('keeps short content in a single chunk', () {
      const content = '第一章\n这是一个很短的正文。';

      final chunks = ReaderTextChunker.chunk(
        content,
        preferredChunkLength: 20,
        hardChunkLength: 32,
      );

      expect(chunks, [content]);
    });

    test('splits long multi paragraph content and preserves order', () {
      final content = List<String>.generate(
        20,
        (index) => '第${index + 1}段：这是用于测试长文本分块显示的正文内容。',
      ).join('\n\n');

      final chunks = ReaderTextChunker.chunk(
        content,
        preferredChunkLength: 60,
        hardChunkLength: 90,
      );

      expect(chunks.length, greaterThan(1));
      expect(chunks.join(), content);
      expect(chunks.every((chunk) => chunk.length <= 90), isTrue);
    });

    test('falls back to hard split for long lines without separators', () {
      final content = '甲' * 220;

      final chunks = ReaderTextChunker.chunk(
        content,
        preferredChunkLength: 40,
        hardChunkLength: 64,
      );

      expect(chunks.length, greaterThan(1));
      expect(chunks.join(), content);
      expect(chunks.every((chunk) => chunk.length <= 64), isTrue);
    });
  });
}
