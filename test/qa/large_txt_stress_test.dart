import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/features/library/data/book_model.dart';
import 'package:wenwen_tome/features/reader/reader_document_probe.dart';

Future<void> _writeLargeTxt(File file, int targetBytes) async {
  await file.parent.create(recursive: true);
  final sink = file.openWrite();
  try {
    var written = 0;
    var chapter = 1;
    const body =
        '这是用于 wenwen_tome 的 TXT 压测样本。为了触发目录规则，包含“第X章”标题。'
        '内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容内容\n';
    final bodyBytes = utf8.encode(body);

    while (written < targetBytes) {
      final header = '第$chapter章 压测章节 $chapter\n';
      final headerBytes = utf8.encode(header);
      sink.add(headerBytes);
      sink.add(bodyBytes);
      sink.add(bodyBytes);
      sink.add(bodyBytes);
      sink.add(const <int>[0x0A]);
      written += headerBytes.length + (bodyBytes.length * 3) + 1;
      chapter++;
      if (chapter % 50 == 0) {
        await sink.flush();
      }
    }
  } finally {
    await sink.flush();
    await sink.close();
  }
}

void main() {
  final runStress = Platform.environment['WENWEN_TOME_RUN_STRESS'] == '1';
  final mb =
      int.tryParse(Platform.environment['WENWEN_TOME_STRESS_TXT_MB'] ?? '') ??
      30;

  test(
    'probes large TXT without crashing (defer toc)',
    () async {
      final tempDir = Directory(
        p.join(
          Directory.current.path,
          '.dart_tool',
          'test_tmp',
          'qa_large_txt',
          DateTime.now().microsecondsSinceEpoch.toString(),
        ),
      );
      await tempDir.create(recursive: true);
      try {
        final file = File(p.join(tempDir.path, 'large_${mb}mb.txt'));
        await _writeLargeTxt(file, mb * 1024 * 1024);
        expect(await file.exists(), isTrue);

        final book = Book(
          id: 'stress_txt',
          filePath: file.path,
          title: 'large_txt_$mb',
          author: 'qa',
          format: BookFormat.txt,
          addedAt: DateTime.now(),
        );

        final result = await ReaderDocumentProbe.probe(book, deferTextToc: true);
        expect(result.kind, ReaderDocumentKind.txt);
        expect(result.txtTocDeferred, isTrue);
        expect(result.txtContent.length, greaterThan(1024));
      } finally {
        if (await tempDir.exists()) {
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {}
        }
      }
    },
    skip: runStress ? null : 'Set WENWEN_TOME_RUN_STRESS=1 to enable stress tests',
  );
}
