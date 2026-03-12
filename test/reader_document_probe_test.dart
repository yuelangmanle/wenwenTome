import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/features/library/data/book_model.dart';
import 'package:wenwen_tome/features/reader/reader_document_probe.dart';

void main() {
  group('ReaderDocumentProbe', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = Directory(
        p.join(
          Directory.current.path,
          'tmp',
          'reader_document_probe_test',
          DateTime.now().microsecondsSinceEpoch.toString(),
        ),
      );
      await tmpDir.create(recursive: true);
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    test(
      'builds synthetic TOC for long TXT without chapter headings',
      () async {
        final txtPath = p.join(tmpDir.path, 'long.txt');
        final buffer = StringBuffer();
        for (var i = 0; i < 18000; i++) {
          buffer.writeln('这是无章节标题的正文段落 $i。用于验证超长文本目录分段。');
        }
        await File(txtPath).writeAsString(buffer.toString(), encoding: utf8);

        final result = await ReaderDocumentProbe.probe(
          Book(
            id: 'txt-long',
            filePath: txtPath,
            title: 'Long TXT',
            author: 'tester',
            format: BookFormat.txt,
            addedAt: DateTime.now(),
          ),
        );

        expect(result.kind, ReaderDocumentKind.txt);
        expect(result.txtContent, isNotEmpty);
        expect(result.txtToc.length, greaterThanOrEqualTo(4));
        expect(result.txtToc.first.title, startsWith('第 1 段'));
      },
    );

    test(
      'uses readable fallback chapter names for EPUB archive fallback',
      () async {
        final epubPath = p.join(tmpDir.path, 'fallback.epub');
        final chapterA = utf8.encode('<html><body><p>第一章正文</p></body></html>');
        final chapterB = utf8.encode('<html><body><p>第二章正文</p></body></html>');
        final archive = Archive()
          ..addFile(
            ArchiveFile('book/chapter-a.html', chapterA.length, chapterA),
          )
          ..addFile(
            ArchiveFile('book/chapter-b.html', chapterB.length, chapterB),
          );
        final bytes = ZipEncoder().encode(archive)!;
        await File(epubPath).writeAsBytes(bytes, flush: true);

        final result = await ReaderDocumentProbe.probe(
          Book(
            id: 'epub-fallback',
            filePath: epubPath,
            title: 'Fallback EPUB',
            author: 'tester',
            format: BookFormat.epub,
            addedAt: DateTime.now(),
          ),
        );

        expect(result.kind, ReaderDocumentKind.epub);
        expect(result.epubContent, isNotEmpty);
        expect(result.epubToc, isNotEmpty);
        expect(result.epubToc.first.title, '章节1');
        expect(result.epubToc.first.title.contains('绔犺妭'), isFalse);
      },
    );
  });
}
