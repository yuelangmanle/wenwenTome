import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart' as epubx;
import 'package:html/parser.dart' show parse;
import 'package:path/path.dart' as p;

import '../../core/storage/app_storage_paths.dart';
import '../library/data/book_model.dart';
import '../logging/app_run_log_service.dart';
import 'book_text_loader.dart';
import 'comic_archive_loader.dart';
import 'reader_pdf_service.dart';

class ReaderTocEntry {
  const ReaderTocEntry({required this.title, required this.position});

  final String title;
  final int position;
}

enum ReaderDocumentKind { epub, pdf, txt, comic, webnovel }

class ReaderDocumentProbeResult {
  const ReaderDocumentProbeResult({
    required this.kind,
    this.txtContent = '',
    this.txtEncoding = '',
    this.txtToc = const <ReaderTocEntry>[],
    this.txtTocDeferred = false,
    this.epubContent = '',
    this.epubToc = const <ReaderTocEntry>[],
    this.epubFallbackUsed = false,
    this.pdfPageCount = 0,
    this.pdfToc = const <ReaderTocEntry>[],
    this.comicImagePaths = const <String>[],
  });

  final ReaderDocumentKind kind;
  final String txtContent;
  final String txtEncoding;
  final List<ReaderTocEntry> txtToc;
  final bool txtTocDeferred;
  final String epubContent;
  final List<ReaderTocEntry> epubToc;
  final bool epubFallbackUsed;
  final int pdfPageCount;
  final List<ReaderTocEntry> pdfToc;
  final List<String> comicImagePaths;
}

class ReaderDocumentProbe {
  static const String _probeCacheVersion = 'rdr-probe-v2';
  static final Map<String, ReaderDocumentProbeResult> _probeCache =
      <String, ReaderDocumentProbeResult>{};

  static final RegExp _chapterLinePattern = RegExp(
    r'^\s*(?:\u6b63\u6587\s*)?(?:\u7b2c[\d0-9\uff10-\uff19\u4e00\u4e8c\u4e09\u56db\u4e94\u516d\u4e03\u516b\u4e5d\u5341\u767e\u5343\u4e07\u4e24\u3007\u96f6\u58f9\u8d30\u53c1\u8086\u4f0d\u9646\u67d2\u634c\u7396\u62fe\u4f70\u4edf\u842c]+[\u7ae0\u8282\u56de\u5377\u90e8\u7bc7\u96c6]|[\u5377\u90e8\u7bc7][\d0-9\uff10-\uff19\u4e00\u4e8c\u4e09\u56db\u4e94\u516d\u4e03\u516b\u4e5d\u5341\u767e\u5343\u4e07\u4e24\u3007\u96f6]+|chapter\s*[\divxlcdm]+|chap\.?\s*[\divxlcdm]+|prologue|epilogue|\u756a\u5916|\u6954\u5b50|\u5e8f\u7ae0|\u540e\u8bb0)',
    caseSensitive: false,
    unicode: true,
  );

  static Future<ReaderDocumentProbeResult> probe(
    Book book, {
    ComicArchiveLoader? comicLoader,
    Future<int> Function(String filePath)? pdfValidator,
    Future<List<ReaderPdfOutlineEntry>> Function(String filePath)?
    pdfOutlineLoader,
    bool deferTextToc = false,
  }) async {
    final cacheKey = await _buildCacheKey(book, deferTextToc: deferTextToc);
    if (cacheKey != null) {
      final cached = _probeCache[cacheKey];
      if (cached != null) {
        return cached;
      }
    }

    final effectiveComicLoader = comicLoader ?? ComicArchiveLoader();
    final effectivePdfValidator =
        pdfValidator ?? ReaderPdfService.validateDocument;
    final effectivePdfOutlineLoader =
        pdfOutlineLoader ?? ReaderPdfService.loadOutline;

    switch (book.format) {
      case BookFormat.epub:
        final file = File(book.filePath);
        if (!await file.exists()) {
          throw Exception('EPUB 解析失败：文件不存在或不可读取');
        }
        final extraction = await _readEpubExtractionWithRecovery(book.filePath);
        final result = ReaderDocumentProbeResult(
          kind: ReaderDocumentKind.epub,
          epubContent: extraction.text,
          epubToc: extraction.toc,
          epubFallbackUsed: extraction.fallbackUsed,
        );
        _cacheProbeResult(cacheKey, result);
        return result;
      case BookFormat.pdf:
        final pageCount = await effectivePdfValidator(book.filePath);
        final outline = await effectivePdfOutlineLoader(book.filePath);
        final result = ReaderDocumentProbeResult(
          kind: ReaderDocumentKind.pdf,
          pdfPageCount: pageCount,
          pdfToc: outline
              .map(
                (entry) => ReaderTocEntry(
                  title: entry.title,
                  position: entry.pageNumber,
                ),
              )
              .toList(growable: false),
        );
        _cacheProbeResult(cacheKey, result);
        return result;
      case BookFormat.txt:
        final file = File(book.filePath);
        if (!await file.exists()) {
          throw Exception('TXT 文件不存在');
        }
        final decoded = await BookTextLoader.readTextFile(book.filePath);
        final effectiveDeferToc = deferTextToc;
        final toc = effectiveDeferToc
            ? const <ReaderTocEntry>[]
            : await buildTextTocAsync(decoded.text);
        final result = ReaderDocumentProbeResult(
          kind: ReaderDocumentKind.txt,
          txtContent: decoded.text,
          txtEncoding: decoded.encoding,
          txtToc: toc,
          txtTocDeferred: effectiveDeferToc,
        );
        _cacheProbeResult(cacheKey, result);
        return result;
      case BookFormat.cbz:
      case BookFormat.cbr:
        final file = File(book.filePath);
        if (!await file.exists()) {
          throw Exception('文件不存在');
        }
        final images = await effectiveComicLoader.resolveComicPages(book);
        final result = ReaderDocumentProbeResult(
          kind: ReaderDocumentKind.comic,
          comicImagePaths: images,
        );
        _cacheProbeResult(cacheKey, result);
        return result;
      case BookFormat.webnovel:
        final result = const ReaderDocumentProbeResult(
          kind: ReaderDocumentKind.webnovel,
        );
        _cacheProbeResult(cacheKey, result);
        return result;
      case BookFormat.mobi:
      case BookFormat.azw3:
        throw Exception('MOBI / AZW3 请先转换为 EPUB 后再导入');
      case BookFormat.unknown:
        throw Exception('当前版本暂不支持该格式');
    }
  }

  static Future<String?> _buildCacheKey(
    Book book, {
    required bool deferTextToc,
  }) async {
    try {
      if (book.format == BookFormat.webnovel || book.filePath.isEmpty) {
        return '${book.format.name}|${book.filePath}|$_probeCacheVersion|toc:$deferTextToc';
      }
      final file = File(book.filePath);
      if (!await file.exists()) {
        return null;
      }
      final stat = await file.stat();
      return '${book.format.name}|${book.filePath}|${stat.size}|${stat.modified.millisecondsSinceEpoch}|$_probeCacheVersion|toc:$deferTextToc';
    } catch (_) {
      return null;
    }
  }

  static void _cacheProbeResult(
    String? cacheKey,
    ReaderDocumentProbeResult result,
  ) {
    if (cacheKey == null) {
      return;
    }
    _probeCache[cacheKey] = result;
    if (_probeCache.length > 64) {
      _probeCache.remove(_probeCache.keys.first);
    }
  }

  static List<ReaderTocEntry> _parseTextToc(String content) {
    if (content.trim().isEmpty) {
      return const <ReaderTocEntry>[];
    }

    final entries = <ReaderTocEntry>[];
    final seenTitles = <String>{};
    final lines = content.split('\n');
    var offset = 0;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isNotEmpty) {
        final isHeadingLine =
            _chapterLinePattern.hasMatch(line) ||
            (line.length <= 72 &&
                RegExp(r'^#{1,4}\s+\S+', caseSensitive: false).hasMatch(line));
        if (isHeadingLine) {
          final normalizedTitle = line.replaceAll(RegExp(r'\s+'), ' ').trim();
          if (normalizedTitle.isNotEmpty && seenTitles.add(normalizedTitle)) {
            entries.add(
              ReaderTocEntry(title: normalizedTitle, position: offset),
            );
          }
        }
      }
      offset += rawLine.length + 1;
    }

    if (entries.length >= 4 || content.length < 240000) {
      return entries;
    }

    return _expandSparseTextToc(content, entries);
  }

  static Future<List<ReaderTocEntry>> buildTextTocAsync(String content) async {
    if (content.trim().isEmpty) {
      return const <ReaderTocEntry>[];
    }
    final raw = await Isolate.run(() {
      final entries = _parseTextToc(content);
      return entries
          .map(
            (entry) => <String, Object>{
              'title': entry.title,
              'position': entry.position,
            },
          )
          .toList(growable: false);
    });
    return raw
        .map((item) {
          final map = Map<String, Object?>.from(item as Map);
          return ReaderTocEntry(
            title: map['title'] as String? ?? '',
            position: map['position'] as int? ?? 0,
          );
        })
        .toList(growable: false);
  }

  static List<ReaderTocEntry> _expandSparseTextToc(
    String content,
    List<ReaderTocEntry> baseEntries,
  ) {
    const sectionChars = 120000;
    final merged = <ReaderTocEntry>[];
    final usedOffset = <int>{};

    void addEntry(String title, int offset) {
      final normalizedOffset = offset.clamp(0, content.length);
      final normalizedTitle = title.trim();
      if (normalizedTitle.isEmpty) {
        return;
      }
      if (!usedOffset.add(normalizedOffset)) {
        return;
      }
      merged.add(
        ReaderTocEntry(title: normalizedTitle, position: normalizedOffset),
      );
    }

    for (final entry in baseEntries) {
      addEntry(entry.title, entry.position);
    }

    var syntheticIndex = 1;
    for (var cursor = 0; cursor < content.length; cursor += sectionChars) {
      final snapped = _snapTextOffsetToSoftBreak(
        content,
        cursor.clamp(0, content.length),
      );
      addEntry('第 $syntheticIndex 段', snapped);
      syntheticIndex++;
    }

    merged.sort((left, right) => left.position.compareTo(right.position));
    if (merged.length <= baseEntries.length) {
      return baseEntries;
    }
    return merged;
  }

  static int _snapTextOffsetToSoftBreak(String text, int offset) {
    if (text.isEmpty) {
      return 0;
    }
    final normalizedOffset = offset.clamp(0, text.length);
    if (normalizedOffset == 0 || normalizedOffset >= text.length) {
      return normalizedOffset;
    }

    const lookaround = 240;
    final start = (normalizedOffset - lookaround).clamp(0, text.length);
    final end = (normalizedOffset + lookaround).clamp(0, text.length);

    for (var index = normalizedOffset; index < end; index++) {
      if (text[index] == '\n') {
        return index + 1;
      }
    }
    for (var index = normalizedOffset; index > start; index--) {
      if (text[index - 1] == '\n') {
        return index;
      }
    }
    return normalizedOffset;
  }

  static _EpubExtraction _extractEpubText(List<epubx.EpubChapter> chapters) {
    final buffer = StringBuffer();
    final toc = <ReaderTocEntry>[];
    var fallbackUsed = false;
    var hasBodyContent = false;

    void visit(epubx.EpubChapter chapter) {
      final document = parse(chapter.HtmlContent ?? '');
      final title = _resolveEpubChapterTitle(
        preferredTitle: chapter.Title ?? '',
        document: document,
        fallbackIndex: toc.length + 1,
      );
      final bodyText = _normalizeExtractedText(
        document.body?.text ?? document.documentElement?.text ?? '',
      );
      final fallbackText = _extractReadableFallbackText(document);
      final chapterText =
          _shouldUseFallbackText(
            primaryText: bodyText,
            fallbackText: fallbackText,
            htmlContent: chapter.HtmlContent ?? '',
          )
          ? fallbackText
          : bodyText;
      if (chapterText.isNotEmpty) {
        final start = buffer.length;
        if (title.isNotEmpty) {
          toc.add(ReaderTocEntry(title: title, position: start));
          buffer.writeln(title);
        }
        if (chapterText == fallbackText && fallbackText != bodyText) {
          fallbackUsed = true;
        }
        hasBodyContent = true;
        buffer.writeln(chapterText);
        buffer.writeln();
      }

      for (final child in chapter.SubChapters ?? const <epubx.EpubChapter>[]) {
        visit(child);
      }
    }

    for (final chapter in chapters) {
      visit(chapter);
    }

    if (!hasBodyContent) {
      return const _EpubExtraction(
        text: '',
        toc: <ReaderTocEntry>[],
        fallbackUsed: false,
      );
    }
    return _EpubExtraction(
      text: buffer.toString().trim(),
      toc: toc,
      fallbackUsed: fallbackUsed,
    );
  }

  static bool _shouldUseFallbackText({
    required String primaryText,
    required String fallbackText,
    required String htmlContent,
  }) {
    if (fallbackText.isEmpty) {
      return false;
    }
    if (primaryText.isEmpty) {
      return true;
    }
    if (fallbackText.length > primaryText.length + 40 &&
        primaryText.length < 80) {
      return true;
    }

    final structuralBlockCount = RegExp(
      r'</(p|div|li|blockquote|h[1-6]|section|article|figure|figcaption|td|th)>',
      caseSensitive: false,
    ).allMatches(htmlContent).length;
    if (structuralBlockCount >= 3 &&
        !primaryText.contains('\n') &&
        fallbackText.contains('\n')) {
      return true;
    }

    return false;
  }

  static String _normalizeExtractedText(String text) {
    return text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  static String _extractReadableFallbackText(dynamic document) {
    final body = document.body ?? document.documentElement;
    if (body == null) {
      return '';
    }

    final blocks = <String>[];

    void appendText(String value) {
      final normalized = _normalizeExtractedText(value);
      if (normalized.isEmpty) {
        return;
      }
      if (blocks.isNotEmpty && blocks.last == normalized) {
        return;
      }
      blocks.add(normalized);
    }

    for (final selector in const <String>[
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'p',
      'li',
      'blockquote',
      'pre',
      'figcaption',
      'td',
      'th',
    ]) {
      for (final element in body.querySelectorAll(selector)) {
        appendText(element.text);
      }
    }

    if (blocks.isEmpty) {
      for (final element in body.querySelectorAll('div, section, article')) {
        final hasStructuredChildren = element.querySelector(
          'p, li, h1, h2, h3, h4, h5, h6, blockquote, pre, figcaption, table',
        );
        if (hasStructuredChildren != null) {
          continue;
        }
        appendText(element.text);
      }
    }

    for (final image in body.querySelectorAll('img')) {
      appendText(
        image.attributes['alt'] ??
            image.attributes['title'] ??
            image.attributes['aria-label'] ??
            '',
      );
    }
    for (final svgText in body.querySelectorAll('svg text')) {
      appendText(svgText.text);
    }

    if (blocks.isEmpty) {
      appendText(body.text);
    }

    return blocks.join('\n\n');
  }

  static String _resolveEpubChapterTitle({
    required String preferredTitle,
    required dynamic document,
    required int fallbackIndex,
  }) {
    final candidates = <String>[
      preferredTitle.trim(),
      document.querySelector('title')?.text ?? '',
      document.querySelector('h1')?.text ?? '',
      document.querySelector('h2')?.text ?? '',
      document.querySelector('h3')?.text ?? '',
    ];

    for (final raw in candidates) {
      final normalized = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (normalized.isNotEmpty) {
        return normalized;
      }
    }
    return '章节$fallbackIndex';
  }
}

Future<_EpubExtraction> _readEpubExtractionWithRecovery(String filePath) async {
  final startedAt = DateTime.now();
  await AppRunLogService.instance.logEvent(
    action: 'reader.epub.parse',
    result: 'start',
    context: <String, Object?>{'path': filePath},
  );

  try {
    final cached = await _readEpubCache(filePath);
    if (cached != null) {
      await AppRunLogService.instance.logEvent(
        action: 'reader.epub.parse',
        result: cached.fallbackUsed ? 'fallback' : 'ok',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: <String, Object?>{
          'cache': 'hit',
          'fallback_used': cached.fallbackUsed,
        },
      );
      return cached;
    }
  } catch (error) {
    await AppRunLogService.instance.logError('EPUB cache read failed: $error');
  }

  try {
    final extraction = await _readEpubExtraction(
      filePath,
    ).timeout(const Duration(seconds: 60));
    await _writeEpubCache(filePath, extraction);
    await AppRunLogService.instance.logEvent(
      action: 'reader.epub.parse',
      result: extraction.fallbackUsed ? 'fallback' : 'ok',
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      context: <String, Object?>{
        'cache': 'miss',
        'fallback_used': extraction.fallbackUsed,
      },
    );
    return extraction;
  } catch (error) {
    final recovered = await _recoverEpubFromRawFile(filePath);
    if (recovered != null) {
      await _writeEpubCache(filePath, recovered);
      await AppRunLogService.instance.logEvent(
        action: 'reader.epub.parse',
        result: 'fallback',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: const <String, Object?>{
          'cache': 'miss',
          'fallback_used': true,
        },
      );
      return recovered;
    }
    await AppRunLogService.instance.logEvent(
      action: 'reader.epub.parse',
      result: 'error',
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      error: error,
      level: 'ERROR',
    );
    throw Exception('EPUB 解析失败，文件可能损坏或不完整：$error');
  }
}

Future<_EpubExtraction?> _recoverEpubFromRawFile(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    return await Isolate.run(() => _extractEpubRawFallback(bytes));
  } catch (_) {
    return null;
  }
}

_EpubExtraction? _extractEpubRawFallback(List<int> bytes) {
  if (bytes.isEmpty) {
    return null;
  }
  if (bytes.length >= 2 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
    // ZIP (EPUB) headers should not be decoded as text.
    return null;
  }
  final decoded = BookTextLoader.decodeBytes(bytes).text.trim();
  if (decoded.isEmpty) {
    return null;
  }
  if (!decoded.contains('<')) {
    return null;
  }

  final document = parse(decoded);
  final text = ReaderDocumentProbe._extractReadableFallbackText(
    document,
  ).trim();
  if (text.isEmpty) {
    return null;
  }

  final title = ReaderDocumentProbe._resolveEpubChapterTitle(
    preferredTitle: '',
    document: document,
    fallbackIndex: 1,
  );
  return _EpubExtraction(
    text: '$title\\n$text',
    toc: <ReaderTocEntry>[ReaderTocEntry(title: title, position: 0)],
    fallbackUsed: true,
  );
}

Future<_EpubExtraction> _readEpubExtraction(String filePath) async {
  final payload = await Isolate.run(() async {
    final bytes = await File(filePath).readAsBytes();
    Object? primaryError;
    _EpubExtraction? primaryParsed;
    _EpubExtraction? fallbackParsed;
    _EpubExtraction? extraction;

    try {
      final epubBook = await epubx.EpubReader.readBook(bytes);
      primaryParsed = ReaderDocumentProbe._extractEpubText(
        epubBook.Chapters ?? const <epubx.EpubChapter>[],
      );
    } catch (error) {
      primaryError = error;
    }

    fallbackParsed = _extractEpubArchiveFallback(bytes);

    if (primaryParsed != null && fallbackParsed != null) {
      extraction = _pickBetterEpubExtraction(primaryParsed, fallbackParsed);
    } else {
      extraction = primaryParsed ?? fallbackParsed;
    }

    if (extraction == null) {
      if (primaryError != null) {
        throw Exception('EPUB 解析失败：$primaryError');
      }
      throw Exception('EPUB 解析失败：未找到可读取的正文内容');
    }

    return <String, Object?>{
      'text': extraction.text,
      'fallbackUsed': extraction.fallbackUsed,
      'toc': extraction.toc
          .map(
            (entry) => <String, Object>{
              'title': entry.title,
              'position': entry.position,
            },
          )
          .toList(growable: false),
    };
  });

  final rawToc = payload['toc'] as List<dynamic>? ?? const <dynamic>[];
  final extractedToc = rawToc
      .map((item) {
        final map = Map<String, Object?>.from(item as Map);
        return ReaderTocEntry(
          title: map['title'] as String? ?? '',
          position: map['position'] as int? ?? 0,
        );
      })
      .toList(growable: false);
  final text = payload['text'] as String? ?? '';
  final toc = _expandSparseEpubToc(text, extractedToc);
  return _EpubExtraction(
    text: text,
    toc: toc,
    fallbackUsed: payload['fallbackUsed'] as bool? ?? false,
  );
}

const int _epubCacheVersion = 1;

String _buildEpubCacheKey(String filePath, int size, int mtime) {
  final hash = filePath.hashCode.toUnsigned(32).toRadixString(16);
  return 'epub_v$_epubCacheVersion'
      '_$hash'
      '_$size'
      '_$mtime';
}

Future<File> _resolveEpubCacheFile(String filePath) async {
  final stat = await File(filePath).stat();
  final supportDir = await getSafeApplicationSupportDirectory();
  final cacheDir = Directory(p.join(supportDir.path, 'epub_cache'));
  await cacheDir.create(recursive: true);
  final key = _buildEpubCacheKey(
    filePath,
    stat.size,
    stat.modified.millisecondsSinceEpoch,
  );
  return File(p.join(cacheDir.path, '$key.json'));
}

Future<_EpubExtraction?> _readEpubCache(String filePath) async {
  final cacheFile = await _resolveEpubCacheFile(filePath);
  if (!await cacheFile.exists()) {
    return null;
  }
  final raw = await cacheFile.readAsString();
  if (raw.trim().isEmpty) {
    return null;
  }
  final json = jsonDecode(raw) as Map<String, dynamic>;
  if (json['version'] != _epubCacheVersion) {
    return null;
  }
  final text = json['text'] as String? ?? '';
  final fallbackUsed = json['fallbackUsed'] as bool? ?? false;
  final tocRaw = json['toc'] as List<dynamic>? ?? const <dynamic>[];
  final toc = tocRaw
      .map(
        (item) => ReaderTocEntry(
          title: (item as Map<String, dynamic>)['title'] as String? ?? '',
          position: (item)['position'] as int? ?? 0,
        ),
      )
      .toList(growable: false);
  if (text.trim().isEmpty) {
    return null;
  }
  return _EpubExtraction(text: text, toc: toc, fallbackUsed: fallbackUsed);
}

Future<void> _writeEpubCache(
  String filePath,
  _EpubExtraction extraction,
) async {
  final cacheFile = await _resolveEpubCacheFile(filePath);
  final payload = <String, Object?>{
    'version': _epubCacheVersion,
    'text': extraction.text,
    'fallbackUsed': extraction.fallbackUsed,
    'toc': extraction.toc
        .map(
          (entry) => <String, Object>{
            'title': entry.title,
            'position': entry.position,
          },
        )
        .toList(growable: false),
  };
  await cacheFile.writeAsString(jsonEncode(payload), flush: true);
}

_EpubExtraction _pickBetterEpubExtraction(
  _EpubExtraction primary,
  _EpubExtraction fallback,
) {
  int score(_EpubExtraction value) {
    final text = value.text.trim();
    if (text.isEmpty) {
      return 0;
    }
    final lines = text.split('\n');
    var longLines = 0;
    for (final line in lines) {
      if (line.trim().length >= 24) {
        longLines++;
      }
    }
    return text.length +
        (value.toc.length * 120) +
        (longLines * 40) +
        (value.fallbackUsed ? -80 : 0);
  }

  final primaryScore = score(primary);
  final fallbackScore = score(fallback);
  if (fallbackScore > primaryScore + 200) {
    return fallback;
  }
  return primary;
}

List<ReaderTocEntry> _expandSparseEpubToc(
  String content,
  List<ReaderTocEntry> baseToc,
) {
  if (content.trim().isEmpty ||
      baseToc.length >= 4 ||
      content.length < 180000) {
    return baseToc;
  }

  const sectionChars = 80000;
  final merged = <ReaderTocEntry>[];
  final usedOffset = <int>{};

  void addEntry(String title, int offset) {
    final normalizedOffset = offset.clamp(0, content.length);
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty || !usedOffset.add(normalizedOffset)) {
      return;
    }
    merged.add(
      ReaderTocEntry(title: normalizedTitle, position: normalizedOffset),
    );
  }

  for (final entry in baseToc) {
    addEntry(entry.title, entry.position);
  }

  var syntheticIndex = 1;
  for (var cursor = 0; cursor < content.length; cursor += sectionChars) {
    final snapped = ReaderDocumentProbe._snapTextOffsetToSoftBreak(
      content,
      cursor.clamp(0, content.length),
    );
    addEntry('第 $syntheticIndex 段', snapped);
    syntheticIndex++;
  }

  merged.sort((left, right) => left.position.compareTo(right.position));
  return merged.length > baseToc.length ? merged : baseToc;
}

_EpubExtraction? _extractEpubArchiveFallback(List<int> bytes) {
  Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes, verify: false);
  } catch (_) {
    return _extractEpubRawFallback(bytes);
  }
  final files = <String, ArchiveFile>{};
  for (final entry in archive.files) {
    if (!entry.isFile) {
      continue;
    }
    files[entry.name] = entry;
  }

  final orderedPaths = _resolveEpubDocumentOrder(files);
  if (orderedPaths.isEmpty) {
    return null;
  }

  final buffer = StringBuffer();
  final toc = <ReaderTocEntry>[];

  for (final path in orderedPaths) {
    if (_isLikelyEpubNavigationDocument(path)) {
      continue;
    }
    final entry = files[path];
    final bytes = entry?.content;
    if (bytes is! List<int> || bytes.isEmpty) {
      continue;
    }

    final document = parse(BookTextLoader.decodeBytes(bytes).text);
    var title = _pickArchiveDocumentTitle(document, path);
    final text = ReaderDocumentProbe._extractReadableFallbackText(document);
    if (_shouldSkipArchiveDocument(title: title, text: text, path: path)) {
      continue;
    }
    if (title.isEmpty && text.isEmpty) {
      continue;
    }
    if (title.isEmpty && text.isNotEmpty) {
      title = '章节${toc.length + 1}';
    }

    final start = buffer.length;
    if (title.isNotEmpty) {
      toc.add(ReaderTocEntry(title: title, position: start));
      buffer.writeln(title);
    }
    if (text.isNotEmpty) {
      buffer.writeln(text);
      buffer.writeln();
    }
  }

  final content = buffer.toString().trim();
  if (content.isEmpty) {
    return const _EpubExtraction(
      text: '',
      toc: <ReaderTocEntry>[],
      fallbackUsed: true,
    );
  }

  return _EpubExtraction(text: content, toc: toc, fallbackUsed: true);
}

List<String> _resolveEpubDocumentOrder(Map<String, ArchiveFile> files) {
  final normalized = <String, String>{
    for (final path in files.keys) path.toLowerCase(): path,
  };

  String? findPath(String rawPath) {
    final cleaned = rawPath.replaceAll('\\', '/');
    return normalized[cleaned.toLowerCase()];
  }

  final containerPath = findPath('META-INF/container.xml');
  if (containerPath != null) {
    final containerBytes = files[containerPath]?.content;
    if (containerBytes is List<int> && containerBytes.isNotEmpty) {
      final containerDoc = parse(
        BookTextLoader.decodeBytes(containerBytes).text,
      );
      final opfPath = containerDoc
          .querySelector('rootfile')
          ?.attributes['full-path']
          ?.trim();
      if (opfPath != null && opfPath.isNotEmpty) {
        final packagePath = findPath(opfPath);
        if (packagePath != null) {
          final ordered = _resolveEpubDocumentOrderFromPackage(
            files,
            packagePath: packagePath,
          );
          if (ordered.isNotEmpty) {
            return ordered;
          }
        }
      }
    }
  }

  final candidates =
      files.keys
          .where((path) {
            final normalizedPath = path.toLowerCase();
            return normalizedPath.endsWith('.xhtml') ||
                normalizedPath.endsWith('.html') ||
                normalizedPath.endsWith('.htm');
          })
          .where((path) {
            final normalizedPath = path.toLowerCase();
            return !normalizedPath.contains('/meta-inf/') &&
                !normalizedPath.endsWith('.ncx');
          })
          .toList()
        ..sort();
  return candidates;
}

List<String> _resolveEpubDocumentOrderFromPackage(
  Map<String, ArchiveFile> files, {
  required String packagePath,
}) {
  final packageBytes = files[packagePath]?.content;
  if (packageBytes is! List<int> || packageBytes.isEmpty) {
    return const <String>[];
  }

  final packageDoc = parse(BookTextLoader.decodeBytes(packageBytes).text);
  final baseDir = File(packagePath).parent.path.replaceAll('\\', '/');
  final manifest = <String, String>{};

  for (final item in packageDoc.querySelectorAll('manifest > item')) {
    final id = item.attributes['id']?.trim();
    final href = item.attributes['href']?.trim();
    if (id == null || id.isEmpty || href == null || href.isEmpty) {
      continue;
    }
    final resolved = _resolveArchivePath(baseDir, href);
    if (resolved.isNotEmpty) {
      manifest[id] = resolved;
    }
  }

  final ordered = <String>[];
  for (final itemref in packageDoc.querySelectorAll('spine > itemref')) {
    final idRef = itemref.attributes['idref']?.trim();
    if (idRef == null || idRef.isEmpty) {
      continue;
    }
    final path = manifest[idRef];
    if (path != null && files.containsKey(path)) {
      ordered.add(path);
    }
  }

  return ordered;
}

String _resolveArchivePath(String baseDir, String href) {
  final normalizedHref = href.replaceAll('\\', '/');
  if (normalizedHref.startsWith('/')) {
    return normalizedHref.replaceFirst('/', '');
  }
  final segments = <String>[
    if (baseDir.isNotEmpty && baseDir != '.') ...baseDir.split('/'),
    ...normalizedHref.split('/'),
  ];
  final resolved = <String>[];
  for (final segment in segments) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (resolved.isNotEmpty) {
        resolved.removeLast();
      }
      continue;
    }
    resolved.add(segment);
  }
  return resolved.join('/');
}

String _pickArchiveDocumentTitle(dynamic document, String path) {
  for (final selector in const <String>['title', 'h1', 'h2']) {
    final text = document.querySelector(selector)?.text.trim() ?? '';
    if (text.isNotEmpty) {
      return text;
    }
  }
  return '';
}

bool _isLikelyEpubNavigationDocument(String path) {
  final normalized = path.toLowerCase();
  return normalized.contains('/toc') ||
      normalized.contains('/nav') ||
      normalized.endsWith('toc.xhtml') ||
      normalized.endsWith('toc.html') ||
      normalized.endsWith('nav.xhtml') ||
      normalized.endsWith('nav.html') ||
      normalized.contains('contents');
}

bool _shouldSkipArchiveDocument({
  required String title,
  required String text,
  required String path,
}) {
  if (text.trim().isEmpty) {
    return false;
  }

  final normalizedTitle = title.replaceAll(RegExp(r'\s+'), '').toLowerCase();
  final normalizedText = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  final lines = text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  final longLines = lines.where((line) => line.length >= 28).length;
  final shortLines = lines.where((line) => line.length <= 18).length;

  if (_isLikelyEpubNavigationDocument(path)) {
    return longLines == 0 || shortLines >= longLines * 2;
  }

  if (normalizedTitle == '目录' ||
      normalizedTitle == 'contents' ||
      normalizedTitle == 'tableofcontents') {
    return true;
  }

  if (normalizedText.length < 120 && shortLines >= 4 && longLines == 0) {
    return true;
  }

  final bodyDensity = normalizedText.length / lines.length;
  if (lines.length >= 8 && bodyDensity < 16 && longLines <= 1) {
    return true;
  }

  return false;
}

class _EpubExtraction {
  const _EpubExtraction({
    required this.text,
    required this.toc,
    required this.fallbackUsed,
  });

  final String text;
  final List<ReaderTocEntry> toc;
  final bool fallbackUsed;
}
