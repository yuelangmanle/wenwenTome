import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/features/library/data/book_model.dart';
import 'package:wenwen_tome/features/reader/reader_document_probe.dart';

void main() {
  group('ReaderDocumentProbe recovery', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = Directory(
        p.join(
          Directory.current.path,
          'tmp',
          'reader_document_probe_recovery_test',
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
      'falls back to raw html extraction for malformed epub payload',
      () async {
        final epubPath = p.join(tmpDir.path, 'broken.epub');
        await File(epubPath).writeAsString(
          '<html><body><h1>Recovered Chapter</h1><p>Hello fallback text.</p></body></html>',
          flush: true,
        );

        final result = await ReaderDocumentProbe.probe(
          Book(
            id: 'broken-epub',
            filePath: epubPath,
            title: 'Broken EPUB',
            author: 'tester',
            format: BookFormat.epub,
            addedAt: DateTime.now(),
          ),
        );

        expect(result.kind, ReaderDocumentKind.epub);
        expect(result.epubFallbackUsed, isTrue);
        expect(result.epubContent, contains('Hello fallback text'));
        expect(result.epubToc, isNotEmpty);
      },
    );
  });
}
