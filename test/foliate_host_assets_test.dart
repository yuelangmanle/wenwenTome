import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'foliate host html includes text reader nodes required by host script',
    () async {
      final html = await File(
        'assets/reader/foliate/reader.html',
      ).readAsString();

      expect(html, contains('id="text-reader"'));
      expect(html, contains('id="text-content"'));
    },
  );

  test('foliate host script exposes chunked text document helpers', () async {
    final script = await File(
      'assets/reader/foliate/wenwen-foliate-host.js',
    ).readAsString();

    expect(script, contains('beginTextDocument(payload)'));
    expect(script, contains('appendTextSection(section)'));
    expect(script, contains('finishTextDocument()'));
  });
}
