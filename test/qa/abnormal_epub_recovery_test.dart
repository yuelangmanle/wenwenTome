import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/features/library/data/book_model.dart';
import 'package:wenwen_tome/features/reader/reader_document_probe.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory(
      p.join(
        Directory.current.path,
        '.dart_tool',
        'test_tmp',
        'qa_bad_epub',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
    await tempDir.create(recursive: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  test('recovers from raw HTML file disguised as .epub', () async {
    final file = File(p.join(tempDir.path, 'raw_html.epub'));
    await file.writeAsString(
      '<html><head><title>t</title></head><body><h1>标题</h1><p>正文</p></body></html>',
      flush: true,
    );

    final book = Book(
      id: 'raw_html_epub',
      filePath: file.path,
      title: 'raw',
      author: 'qa',
      format: BookFormat.epub,
      addedAt: DateTime.now(),
    );

    final result = await ReaderDocumentProbe.probe(book);
    expect(result.kind, ReaderDocumentKind.epub);
    expect(result.epubFallbackUsed, isTrue);
    expect(result.epubContent, contains('标题'));
    expect(result.epubToc, isNotEmpty);
  });

  test('fails gracefully on truncated ZIP-like epub', () async {
    final file = File(p.join(tempDir.path, 'truncated_zip.epub'));
    await file.writeAsBytes(
      <int>[0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00],
      flush: true,
    );

    final book = Book(
      id: 'truncated_zip_epub',
      filePath: file.path,
      title: 'bad',
      author: 'qa',
      format: BookFormat.epub,
      addedAt: DateTime.now(),
    );

    expect(
      () => ReaderDocumentProbe.probe(book),
      throwsA(
        predicate(
          (e) => e.toString().contains('EPUB 解析失败'),
        ),
      ),
    );
  });
}

