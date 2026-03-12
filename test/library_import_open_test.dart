import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/features/library/data/book_model.dart';
import 'package:wenwen_tome/features/library/mobi_converter_service.dart';
import 'package:wenwen_tome/features/reader/comic_archive_loader.dart';
import 'package:wenwen_tome/features/reader/reader_document_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReaderDocumentProbe', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'wenwen_tome_reader_probe_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('reads txt file content and reports encoding', () async {
      final file = File(p.join(tempDir.path, 'sample.txt'));
      await file.writeAsString(
        'Chapter 1\nThis is the text body.',
        flush: true,
      );

      final result = await ReaderDocumentProbe.probe(
        Book(
          id: 'txt-1',
          filePath: file.path,
          title: 'sample',
          author: 'tester',
          format: BookFormat.txt,
          addedAt: DateTime(2026, 3, 6),
        ),
      );

      expect(result.kind, ReaderDocumentKind.txt);
      expect(result.txtContent, contains('This is the text body.'));
      expect(result.txtEncoding, isNotEmpty);
    });

    test('reuses existing converted epub for legacy mobi files', () async {
      final file = File(p.join(tempDir.path, 'legacy.mobi'));
      final converted = File(p.join(tempDir.path, 'legacy_converted.epub'));
      await file.writeAsString('placeholder mobi', flush: true);
      await converted.writeAsString('converted epub', flush: true);

      final result = await MobiConverterService.convertToEpub(file.path);

      expect(result?.outputPath, converted.path);
      expect(result?.usedExistingOutput, isTrue);
    });

    test('reuses existing converted epub for legacy azw3 files', () async {
      final file = File(p.join(tempDir.path, 'legacy.azw3'));
      final converted = File(p.join(tempDir.path, 'legacy_converted.epub'));
      await file.writeAsString('placeholder azw3', flush: true);
      await converted.writeAsString('converted epub', flush: true);

      final result = await MobiConverterService.convertToEpub(file.path);

      expect(result?.outputPath, converted.path);
      expect(result?.usedExistingOutput, isTrue);
    });

    test('extracts visible text from epub content', () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip'))
            ..compress = false,
        )
        ..addFile(
          ArchiveFile(
            'META-INF/container.xml',
            234,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/content.opf',
            560,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Example</dc:title>
    <dc:identifier id="bookid">demo</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="chapter1"/>
  </spine>
</package>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/toc.ncx',
            528,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="demo"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>Example</text></docTitle>
  <navMap>
    <navPoint id="navPoint-1" playOrder="1">
      <navLabel><text>Chapter 1</text></navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/chapter1.xhtml',
            154,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><h1>Chapter 1</h1><p>This is EPUB body text.</p></body>
</html>
'''),
          ),
        );

      final bytes = ZipEncoder().encode(archive)!;
      final file = File(p.join(tempDir.path, 'sample.epub'));
      await file.writeAsBytes(bytes, flush: true);

      final result = await ReaderDocumentProbe.probe(
        Book(
          id: 'epub-1',
          filePath: file.path,
          title: 'sample',
          author: 'tester',
          format: BookFormat.epub,
          addedAt: DateTime(2026, 3, 6),
        ),
      );

      expect(result.kind, ReaderDocumentKind.epub);
      expect(result.epubContent, contains('This is EPUB body text.'));
    });

    test('fills epub toc when chapter titles are missing', () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip'))
            ..compress = false,
        )
        ..addFile(
          ArchiveFile(
            'META-INF/container.xml',
            234,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/content.opf',
            640,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Example</dc:title>
    <dc:identifier id="bookid">demo-missing-title</dc:identifier>
  </metadata>
  <manifest>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
    <item id="chapter2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter1"/>
    <itemref idref="chapter2"/>
  </spine>
</package>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/chapter1.xhtml',
            148,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><p>chapter one body text</p></body>
</html>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/chapter2.xhtml',
            148,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><p>chapter two body text</p></body>
</html>
'''),
          ),
        );

      final bytes = ZipEncoder().encode(archive)!;
      final file = File(p.join(tempDir.path, 'missing-title.epub'));
      await file.writeAsBytes(bytes, flush: true);

      final result = await ReaderDocumentProbe.probe(
        Book(
          id: 'epub-missing-title-1',
          filePath: file.path,
          title: 'missing-title',
          author: 'tester',
          format: BookFormat.epub,
          addedAt: DateTime(2026, 3, 6),
        ),
      );

      expect(result.kind, ReaderDocumentKind.epub);
      expect(result.epubToc, isNotEmpty);
      expect(result.epubToc.first.title, contains('章节'));
    });

    test('keeps empty-text epub readable instead of hard failing', () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip'))
            ..compress = false,
        )
        ..addFile(
          ArchiveFile(
            'META-INF/container.xml',
            234,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/content.opf',
            560,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Example</dc:title>
    <dc:identifier id="bookid">demo-empty</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="chapter1"/>
  </spine>
</package>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/toc.ncx',
            424,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="demo-empty"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>Example</text></docTitle>
  <navMap />
</ncx>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/chapter1.xhtml',
            122,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body></body>
</html>
'''),
          ),
        );

      final bytes = ZipEncoder().encode(archive)!;
      final file = File(p.join(tempDir.path, 'empty.epub'));
      await file.writeAsBytes(bytes, flush: true);

      final result = await ReaderDocumentProbe.probe(
        Book(
          id: 'epub-empty-1',
          filePath: file.path,
          title: 'empty',
          author: 'tester',
          format: BookFormat.epub,
          addedAt: DateTime(2026, 3, 6),
        ),
      );

      expect(result.kind, ReaderDocumentKind.epub);
      expect(result.epubContent.trim(), isEmpty);
    });

    test('uses epub fallback extraction when body text is missing', () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile('mimetype', 20, utf8.encode('application/epub+zip'))
            ..compress = false,
        )
        ..addFile(
          ArchiveFile(
            'META-INF/container.xml',
            234,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/content.opf',
            560,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<package version="2.0" xmlns="http://www.idpf.org/2007/opf" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Example</dc:title>
    <dc:identifier id="bookid">demo-fallback</dc:identifier>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="chapter1"/>
  </spine>
</package>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/toc.ncx',
            528,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="demo-fallback"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>Example</text></docTitle>
  <navMap>
    <navPoint id="navPoint-1" playOrder="1">
      <navLabel><text>Image Chapter</text></navLabel>
      <content src="chapter1.xhtml"/>
    </navPoint>
  </navMap>
</ncx>
'''),
          ),
        )
        ..addFile(
          ArchiveFile(
            'OEBPS/chapter1.xhtml',
            176,
            utf8.encode('''
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <body><img src="page.png" alt="Fallback chapter text."/></body>
</html>
'''),
          ),
        );

      final bytes = ZipEncoder().encode(archive)!;
      final file = File(p.join(tempDir.path, 'fallback.epub'));
      await file.writeAsBytes(bytes, flush: true);

      final result = await ReaderDocumentProbe.probe(
        Book(
          id: 'epub-fallback-1',
          filePath: file.path,
          title: 'fallback',
          author: 'tester',
          format: BookFormat.epub,
          addedAt: DateTime(2026, 3, 6),
        ),
      );

      expect(result.kind, ReaderDocumentKind.epub);
      expect(result.epubFallbackUsed, isTrue);
      expect(result.epubContent, contains('Fallback chapter text.'));
    });

    test(
      'opens valid pdf files without treating them as unsupported',
      () async {
        final file = File(p.join(tempDir.path, 'sample.pdf'));
        await file.writeAsBytes(utf8.encode(_minimalPdf), flush: true);

        final result = await ReaderDocumentProbe.probe(
          Book(
            id: 'pdf-1',
            filePath: file.path,
            title: 'sample',
            author: 'tester',
            format: BookFormat.pdf,
            addedAt: DateTime(2026, 3, 6),
          ),
          pdfValidator: (_) async => 1,
          pdfOutlineLoader: (_) async => const [],
        );

        expect(result.kind, ReaderDocumentKind.pdf);
      },
    );

    test('extracts cbz pages to cached image paths', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('page10.jpg', 3, [1, 2, 3]))
        ..addFile(ArchiveFile('page2.jpg', 3, [4, 5, 6]))
        ..addFile(ArchiveFile('notes.txt', 2, [7, 8]));
      final bytes = ZipEncoder().encode(archive)!;
      final file = File(p.join(tempDir.path, 'sample.cbz'));
      await file.writeAsBytes(bytes, flush: true);

      final result = await ReaderDocumentProbe.probe(
        Book(
          id: 'comic-cbz',
          filePath: file.path,
          title: 'sample',
          author: 'tester',
          format: BookFormat.cbz,
          addedAt: DateTime(2026, 3, 6),
        ),
        comicLoader: ComicArchiveLoader(cacheDirProvider: () async => tempDir),
      );

      expect(result.kind, ReaderDocumentKind.comic);
      expect(result.comicImagePaths, hasLength(2));
      expect(p.basename(result.comicImagePaths.first), 'page2.jpg');
      expect(p.basename(result.comicImagePaths.last), 'page10.jpg');
    });

    test('adds synthetic toc sections for long txt without headings', () async {
      final file = File(p.join(tempDir.path, 'long_no_toc.txt'));
      final line = ('这是一段正文没有章节标记。' * 16);
      final buffer = StringBuffer();
      for (var index = 0; index < 4600; index++) {
        buffer.writeln(line);
      }
      await file.writeAsString(buffer.toString(), flush: true);

      final result = await ReaderDocumentProbe.probe(
        Book(
          id: 'txt-long-no-toc-1',
          filePath: file.path,
          title: 'long_no_toc',
          author: 'tester',
          format: BookFormat.txt,
          addedAt: DateTime(2026, 3, 6),
        ),
      );

      expect(result.kind, ReaderDocumentKind.txt);
      expect(result.txtToc.length, greaterThanOrEqualTo(2));
      expect(result.txtToc.first.title, startsWith('第'));
    });

    test('extracts cbr pages through the rar loader bridge', () async {
      final file = File(p.join(tempDir.path, 'sample.cbr'));
      await file.writeAsBytes([1, 2, 3], flush: true);

      final result = await ReaderDocumentProbe.probe(
        Book(
          id: 'comic-cbr',
          filePath: file.path,
          title: 'sample',
          author: 'tester',
          format: BookFormat.cbr,
          addedAt: DateTime(2026, 3, 6),
        ),
        comicLoader: ComicArchiveLoader(
          cacheDirProvider: () async => tempDir,
          windowsRarListFiles: (archivePath) async => <String>[
            'page10.jpg',
            'page2.jpg',
            'folder/readme.txt',
          ],
          windowsRarExtractAll: (archivePath, outputDir) async {
            await File(
              p.join(outputDir, 'page10.jpg'),
            ).writeAsBytes([1, 2, 3], flush: true);
            await File(
              p.join(outputDir, 'page2.jpg'),
            ).writeAsBytes([4, 5, 6], flush: true);
            await Directory(
              p.join(outputDir, 'folder'),
            ).create(recursive: true);
            await File(
              p.join(outputDir, 'folder', 'readme.txt'),
            ).writeAsString('ignore', flush: true);
          },
        ),
      );

      expect(result.kind, ReaderDocumentKind.comic);
      expect(result.comicImagePaths, hasLength(2));
      expect(p.basename(result.comicImagePaths.first), 'page2.jpg');
      expect(p.basename(result.comicImagePaths.last), 'page10.jpg');
    });

    test('fails invalid epub early instead of reporting success', () async {
      final file = File(p.join(tempDir.path, 'broken.epub'));
      await file.writeAsString('not an epub archive', flush: true);

      await expectLater(
        () => ReaderDocumentProbe.probe(
          Book(
            id: 'broken-1',
            filePath: file.path,
            title: 'broken',
            author: 'tester',
            format: BookFormat.epub,
            addedAt: DateTime(2026, 3, 6),
          ),
        ),
        throwsException,
      );
    });
  });
}

const _minimalPdf = r'''%PDF-1.1
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 44 >>
stream
BT
/F1 12 Tf
72 72 Td
(hello pdf) Tj
ET
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000010 00000 n 
0000000062 00000 n 
0000000118 00000 n 
0000000192 00000 n 
trailer
<< /Root 1 0 R /Size 5 >>
startxref
286
%%EOF
''';
