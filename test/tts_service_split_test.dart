import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/reader/tts_service.dart';

void main() {
  group('TtsService.splitTextForPlayback', () {
    test('splits by punctuation and max segment length', () {
      const text = '第一句很短。第二句也很短！第三句用于验证分段？第四句继续，保证超过单段长度。';

      final segments = TtsService.splitTextForPlayback(
        text,
        maxSegmentChars: 18,
      );

      expect(segments.length, greaterThan(2));
      expect(segments.every((segment) => segment.length <= 18), isTrue);
    });

    test('falls back to hard slicing when a sentence is too long', () {
      final text = 'a' * 100;

      final segments = TtsService.splitTextForPlayback(
        text,
        maxSegmentChars: 24,
      );

      expect(segments.length, greaterThan(3));
      expect(segments.join(), text);
      expect(segments.every((segment) => segment.length <= 24), isTrue);
    });
  });
}
