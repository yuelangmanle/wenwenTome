import 'dart:io';

import 'package:charset/charset.dart' as charset;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ChineseSimplified.isl is stored as readable GBK text', () async {
    final file = File('tools/ChineseSimplified.isl');
    expect(await file.exists(), isTrue);

    final bytes = await file.readAsBytes();
    final text = charset.gbk.decode(bytes, allowMalformed: false);

    expect(text, contains('LanguageName=简体中文'));
    expect(text, contains('SetupAppTitle=安装'));
    expect(text, contains('ButtonCancel=取消'));
    expect(text, isNot(contains('缁犫偓娴ｆ挷鑵戦弬')));
    expect(text, isNot(contains('鐎瑰顥')));
    expect(text, isNot(contains('閸欐牗绉')));
  });
}
