import 'dart:isolate';

class ReaderTextChunker {
  static const _defaultPreferredChunkLength = 2400;
  static const _defaultHardChunkLength = 3600;

  static Future<List<String>> chunkAsync(
    String content, {
    int preferredChunkLength = _defaultPreferredChunkLength,
    int hardChunkLength = _defaultHardChunkLength,
  }) {
    return Isolate.run(
      () => chunk(
        content,
        preferredChunkLength: preferredChunkLength,
        hardChunkLength: hardChunkLength,
      ),
    );
  }

  static List<String> chunk(
    String content, {
    int preferredChunkLength = _defaultPreferredChunkLength,
    int hardChunkLength = _defaultHardChunkLength,
  }) {
    if (content.isEmpty) {
      return const <String>[];
    }

    if (content.length <= hardChunkLength) {
      return <String>[content];
    }

    final chunks = <String>[];
    final buffer = StringBuffer();
    final lines = content.split('\n');

    void flushBuffer() {
      if (buffer.isEmpty) {
        return;
      }
      chunks.add(buffer.toString());
      buffer.clear();
    }

    for (var index = 0; index < lines.length; index++) {
      final suffix = index == lines.length - 1 ? '' : '\n';
      final segment = '${lines[index]}$suffix';
      if (segment.isEmpty) {
        continue;
      }

      if (segment.length > hardChunkLength) {
        flushBuffer();
        chunks.addAll(
          _splitLongSegment(
            segment,
            preferredChunkLength: preferredChunkLength,
            hardChunkLength: hardChunkLength,
          ),
        );
        continue;
      }

      if (buffer.isNotEmpty &&
          buffer.length + segment.length > hardChunkLength) {
        flushBuffer();
      }

      buffer.write(segment);
    }

    flushBuffer();
    return chunks;
  }

  static List<String> _splitLongSegment(
    String segment, {
    required int preferredChunkLength,
    required int hardChunkLength,
  }) {
    final chunks = <String>[];
    var start = 0;

    while (start < segment.length) {
      final remaining = segment.length - start;
      if (remaining <= hardChunkLength) {
        chunks.add(segment.substring(start));
        break;
      }

      final candidateEnd = start + hardChunkLength;
      final preferredEnd = start + preferredChunkLength;
      final splitAt = _findSplitPoint(
        segment,
        minIndex: preferredEnd.clamp(start + 1, candidateEnd),
        maxIndex: candidateEnd,
      );
      chunks.add(segment.substring(start, splitAt));
      start = splitAt;
    }

    return chunks;
  }

  static int _findSplitPoint(
    String value, {
    required int minIndex,
    required int maxIndex,
  }) {
    for (var index = maxIndex; index >= minIndex; index--) {
      final char = value[index - 1];
      if (_isPreferredBreak(char)) {
        return index;
      }
    }
    return maxIndex;
  }

  static bool _isPreferredBreak(String char) {
    return char == '\n' ||
        char == ' ' ||
        char == '\t' ||
        char == '。' ||
        char == '！' ||
        char == '？' ||
        char == '；' ||
        char == '，' ||
        char == '.' ||
        char == '!' ||
        char == '?' ||
        char == ';' ||
        char == ',';
  }
}
