import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class TextPageSlice {
  const TextPageSlice({
    required this.startOffset,
    required this.endOffset,
    required this.text,
  });

  final int startOffset;
  final int endOffset;
  final String text;

  String get displayText => text.trimRight();
}

class TextPaginationResult {
  const TextPaginationResult(this.pages);

  final List<TextPageSlice> pages;

  int pageIndexForOffset(int offset) {
    if (pages.isEmpty) {
      return 0;
    }

    final normalizedOffset = offset.clamp(0, pages.last.endOffset);
    var low = 0;
    var high = pages.length - 1;

    while (low <= high) {
      final mid = low + ((high - low) ~/ 2);
      final page = pages[mid];
      if (normalizedOffset < page.startOffset) {
        high = mid - 1;
      } else if (normalizedOffset >= page.endOffset && mid < pages.length - 1) {
        low = mid + 1;
      } else {
        return mid;
      }
    }

    return math.max(0, math.min(low, pages.length - 1));
  }
}

class TextPaginator {
  static const _softBreakLookback = 96;
  static const _maxCacheEntries = 24;
  static final LinkedHashMap<String, TextPaginationResult> _cache =
      LinkedHashMap<String, TextPaginationResult>();
  static const _defaultProgressInterval = 3;
  static const Duration _defaultYieldBudget = Duration(milliseconds: 12);

  static void clearCache() => _cache.clear();

  static TextPaginationResult paginate({
    required String text,
    required TextStyle style,
    required Size size,
    TextDirection textDirection = TextDirection.ltr,
    String? cacheKey,
  }) {
    if (text.isEmpty || size.width <= 0 || size.height <= 0) {
      return const TextPaginationResult(<TextPageSlice>[]);
    }

    final normalizedCacheKey = cacheKey == null || cacheKey.isEmpty
        ? null
        : '$cacheKey|${text.length}';
    if (normalizedCacheKey != null) {
      final cached = _cache.remove(normalizedCacheKey);
      if (cached != null) {
        _cache[normalizedCacheKey] = cached;
        return cached;
      }
    }

    final painter = TextPainter(
      textDirection: textDirection,
      maxLines: null,
      textWidthBasis: TextWidthBasis.parent,
    );
    final pages = <TextPageSlice>[];
    var startOffset = 0;

    while (startOffset < text.length) {
      final bestEndOffset = _measureBestFitOffset(
        text: text,
        style: style,
        size: size,
        startOffset: startOffset,
        painter: painter,
      );
      final endOffset = _adjustEndOffset(
        text,
        startOffset: startOffset,
        endOffset: bestEndOffset,
      );

      pages.add(
        TextPageSlice(
          startOffset: startOffset,
          endOffset: endOffset,
          text: text.substring(startOffset, endOffset),
        ),
      );
      startOffset = endOffset;
    }

    final result = TextPaginationResult(
      List<TextPageSlice>.unmodifiable(pages),
    );
    if (normalizedCacheKey != null) {
      _cache[normalizedCacheKey] = result;
      while (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
    }
    return result;
  }

  static Future<TextPaginationResult> paginateIncremental({
    required String text,
    required TextStyle style,
    required Size size,
    TextDirection textDirection = TextDirection.ltr,
    String? cacheKey,
    int progressInterval = _defaultProgressInterval,
    Duration yieldBudget = _defaultYieldBudget,
    bool Function()? isCancelled,
    void Function(List<TextPageSlice> pages)? onProgress,
  }) async {
    if (text.isEmpty || size.width <= 0 || size.height <= 0) {
      return const TextPaginationResult(<TextPageSlice>[]);
    }

    final normalizedCacheKey = cacheKey == null || cacheKey.isEmpty
        ? null
        : '$cacheKey|${text.length}';
    if (normalizedCacheKey != null) {
      final cached = _cache.remove(normalizedCacheKey);
      if (cached != null) {
        _cache[normalizedCacheKey] = cached;
        onProgress?.call(cached.pages);
        return cached;
      }
    }

    final painter = TextPainter(
      textDirection: textDirection,
      maxLines: null,
      textWidthBasis: TextWidthBasis.parent,
    );
    final pages = <TextPageSlice>[];
    var startOffset = 0;
    var pendingProgress = 0;
    final budgetWatch = Stopwatch()..start();

    while (startOffset < text.length) {
      if (isCancelled?.call() ?? false) {
        return TextPaginationResult(List<TextPageSlice>.unmodifiable(pages));
      }
      final bestEndOffset = _measureBestFitOffset(
        text: text,
        style: style,
        size: size,
        startOffset: startOffset,
        painter: painter,
      );
      final endOffset = _adjustEndOffset(
        text,
        startOffset: startOffset,
        endOffset: bestEndOffset,
      );
      pages.add(
        TextPageSlice(
          startOffset: startOffset,
          endOffset: endOffset,
          text: text.substring(startOffset, endOffset),
        ),
      );
      startOffset = endOffset;
      pendingProgress += 1;
      if (pages.length == 1 || pendingProgress >= progressInterval) {
        pendingProgress = 0;
        onProgress?.call(List<TextPageSlice>.unmodifiable(pages));
      }
      if (budgetWatch.elapsed >= yieldBudget) {
        budgetWatch.reset();
        await Future<void>.delayed(Duration.zero);
      }
    }

    final result = TextPaginationResult(
      List<TextPageSlice>.unmodifiable(pages),
    );
    if (normalizedCacheKey != null) {
      _cache[normalizedCacheKey] = result;
      while (_cache.length > _maxCacheEntries) {
        _cache.remove(_cache.keys.first);
      }
    }
    onProgress?.call(result.pages);
    return result;
  }

  static int _measureBestFitOffset({
    required String text,
    required TextStyle style,
    required Size size,
    required int startOffset,
    required TextPainter painter,
  }) {
    var low = startOffset + 1;
    var high = text.length;
    var bestFitOffset = low;

    while (low <= high) {
      final mid = low + ((high - low) ~/ 2);
      painter.text = TextSpan(
        text: text.substring(startOffset, mid),
        style: style,
      );
      painter.layout(maxWidth: size.width);

      if (painter.height <= size.height) {
        bestFitOffset = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return bestFitOffset > startOffset ? bestFitOffset : startOffset + 1;
  }

  static int _adjustEndOffset(
    String text, {
    required int startOffset,
    required int endOffset,
  }) {
    if (endOffset >= text.length) {
      return text.length;
    }

    final lowerBound = math.max(
      startOffset + 1,
      endOffset - _softBreakLookback,
    );
    for (var index = endOffset; index > lowerBound; index--) {
      final previousChar = text[index - 1];
      if (_isPreferredBreak(previousChar)) {
        return index;
      }
    }

    return endOffset;
  }

  static bool _isPreferredBreak(String char) {
    return char == '\n' ||
        char == '\r' ||
        char == ' ' ||
        char == '\t' ||
        char == '\u3002' ||
        char == '\uFF01' ||
        char == '\uFF1F' ||
        char == '\uFF1B' ||
        char == '\uFF0C' ||
        char == '.' ||
        char == '!' ||
        char == '?' ||
        char == ';' ||
        char == ':';
  }
}
