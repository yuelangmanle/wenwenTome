import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:charset/charset.dart' as charset;

class DecodedTextResult {
  const DecodedTextResult({required this.text, required this.encoding});

  final String text;
  final String encoding;
}

class DecodedTextChunk {
  const DecodedTextChunk({required this.text, required this.encoding});

  final String text;
  final String encoding;
}

class BookTextLoader {
  static const _utf8Bom = [0xEF, 0xBB, 0xBF];
  static const _utf16LeBom = [0xFF, 0xFE];
  static const _utf16BeBom = [0xFE, 0xFF];
  static const _headerProbeSize = 32768;
  static const _previewProbeSize = 262144;

  static Future<DecodedTextResult> readTextFile(String filePath) async {
    return Isolate.run(() async {
      final file = File(filePath);
      final header = await _readHeaderBytes(file, _headerProbeSize);
      final detected = decodeBytes(header);
      final encoding = detected.encoding;
      if (encoding.startsWith('utf-16')) {
        final bytes = await file.readAsBytes();
        return decodeBytes(bytes);
      }

      var startOffset = 0;
      if (encoding == 'utf-8-bom' && _startsWith(header, _utf8Bom)) {
        startOffset = _utf8Bom.length;
      }

      final stream = file.openRead(startOffset);
      final buffer = StringBuffer();
      final decoder = _decoderForEncoding(encoding);
      await for (final chunk in stream.transform(decoder)) {
        buffer.write(chunk);
      }
      return DecodedTextResult(text: buffer.toString(), encoding: encoding);
    });
  }

  static Future<DecodedTextResult> readTextFilePreview(
    String filePath, {
    int maxBytes = _previewProbeSize,
  }) async {
    return Isolate.run(() async {
      final file = File(filePath);
      final header = await _readHeaderBytes(file, maxBytes);
      if (header.isEmpty) {
        return const DecodedTextResult(text: '', encoding: 'empty');
      }
      return decodeBytes(header);
    });
  }

  static Stream<DecodedTextChunk> streamTextFileChunks(
    String filePath,
  ) async* {
    final file = File(filePath);
    final header = await _readHeaderBytes(file, _headerProbeSize);
    if (header.isEmpty) {
      return;
    }
    final detected = decodeBytes(header);
    final encoding = detected.encoding;
    var startOffset = 0;
    if (encoding == 'utf-8-bom' && _startsWith(header, _utf8Bom)) {
      startOffset = _utf8Bom.length;
    } else if (encoding == 'utf-16le' && _startsWith(header, _utf16LeBom)) {
      startOffset = _utf16LeBom.length;
    } else if (encoding == 'utf-16be' && _startsWith(header, _utf16BeBom)) {
      startOffset = _utf16BeBom.length;
    }

    if (encoding.startsWith('utf-16')) {
      final decoder = _Utf16StreamDecoder(
        littleEndian: encoding.contains('le'),
      );
      await for (final bytes in file.openRead(startOffset)) {
        final text = decoder.convert(bytes);
        if (text.isNotEmpty) {
          yield DecodedTextChunk(text: text, encoding: encoding);
        }
      }
      final tail = decoder.flush();
      if (tail.isNotEmpty) {
        yield DecodedTextChunk(text: tail, encoding: encoding);
      }
      return;
    }

    final decoder = _decoderForEncoding(encoding);
    await for (final text in file.openRead(startOffset).transform(decoder)) {
      if (text.isNotEmpty) {
        yield DecodedTextChunk(text: text, encoding: encoding);
      }
    }
  }

  static DecodedTextResult decodeBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      return const DecodedTextResult(text: '', encoding: 'empty');
    }

    if (_startsWith(bytes, _utf8Bom)) {
      return DecodedTextResult(
        text: utf8.decode(bytes.sublist(3), allowMalformed: true),
        encoding: 'utf-8-bom',
      );
    }

    if (_startsWith(bytes, _utf16LeBom)) {
      return DecodedTextResult(
        text: _decodeUtf16(bytes.sublist(2), littleEndian: true),
        encoding: 'utf-16le',
      );
    }

    if (_startsWith(bytes, _utf16BeBom)) {
      return DecodedTextResult(
        text: _decodeUtf16(bytes.sublist(2), littleEndian: false),
        encoding: 'utf-16be',
      );
    }

    final inferredUtf16 = _tryDecodeUtf16WithoutBom(bytes);
    if (inferredUtf16 != null && _looksReadable(inferredUtf16.text)) {
      return inferredUtf16;
    }

    final utf8Text = _tryDecode(
      () => utf8.decode(bytes, allowMalformed: false),
      encoding: 'utf-8',
    );
    if (utf8Text != null && _looksReadable(utf8Text.text)) {
      return utf8Text;
    }

    final gbkText = _tryDecode(
      () => charset.gbk.decode(bytes),
      encoding: 'gbk',
    );
    if (gbkText != null && _looksReadable(gbkText.text)) {
      return gbkText;
    }

    return DecodedTextResult(
      text: latin1.decode(bytes, allowInvalid: true),
      encoding: 'latin1-fallback',
    );
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }

  static Future<List<int>> _readHeaderBytes(File file, int maxBytes) async {
    try {
      final raf = await file.open();
      try {
        return await raf.read(maxBytes);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return const <int>[];
    }
  }

  static Converter<List<int>, String> _decoderForEncoding(String encoding) {
    if (encoding == 'utf-8' || encoding == 'utf-8-bom') {
      return const Utf8Decoder(allowMalformed: true);
    }
    if (encoding == 'gbk') {
      return charset.gbk.decoder;
    }
    return latin1.decoder;
  }

  static DecodedTextResult? _tryDecode(
    String Function() decode, {
    required String encoding,
  }) {
    try {
      return DecodedTextResult(text: decode(), encoding: encoding);
    } catch (_) {
      return null;
    }
  }

  static String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
    final codeUnits = <int>[];
    for (var i = 0; i < bytes.length; i += 2) {
      final first = bytes[i];
      final second = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final value = littleEndian
          ? first | (second << 8)
          : (first << 8) | second;
      codeUnits.add(value);
    }
    return String.fromCharCodes(codeUnits);
  }

  static DecodedTextResult? _tryDecodeUtf16WithoutBom(List<int> bytes) {
    if (bytes.length < 4) {
      return null;
    }
    final sampleLength = bytes.length < 4096 ? bytes.length : 4096;
    var evenZero = 0;
    var oddZero = 0;
    var inspected = 0;
    for (var i = 0; i < sampleLength; i++) {
      final value = bytes[i];
      if (i.isEven) {
        if (value == 0) evenZero++;
      } else {
        if (value == 0) oddZero++;
      }
      inspected++;
    }
    if (inspected < 32) {
      return null;
    }
    final evenRatio = evenZero / (inspected / 2);
    final oddRatio = oddZero / (inspected / 2);
    if (oddRatio > 0.25 && evenRatio < 0.05) {
      return DecodedTextResult(
        text: _decodeUtf16(bytes, littleEndian: true),
        encoding: 'utf-16le-no-bom',
      );
    }
    if (evenRatio > 0.25 && oddRatio < 0.05) {
      return DecodedTextResult(
        text: _decodeUtf16(bytes, littleEndian: false),
        encoding: 'utf-16be-no-bom',
      );
    }
    return null;
  }

  static bool _looksReadable(String text) {
    if (text.trim().isEmpty) return false;
    final replacementCount = '\uFFFD'.allMatches(text).length;
    if (replacementCount > 0) return false;

    final runeCount = text.runes.length;
    if (runeCount == 0) return false;

    var controlCount = 0;
    for (final rune in text.runes) {
      final isWhitespace = rune == 0x09 || rune == 0x0A || rune == 0x0D;
      if (!isWhitespace && rune < 0x20) {
        controlCount++;
      }
    }

    return controlCount / runeCount < 0.02;
  }
}

class _Utf16StreamDecoder {
  _Utf16StreamDecoder({required this.littleEndian});

  final bool littleEndian;
  int? _carry;

  String convert(List<int> bytes) {
    if (bytes.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    var index = 0;
    if (_carry != null) {
      if (bytes.isNotEmpty) {
        final value = littleEndian
            ? _carry! | (bytes[0] << 8)
            : (_carry! << 8) | bytes[0];
        buffer.writeCharCode(value);
        _carry = null;
        index = 1;
      }
    }

    for (; index + 1 < bytes.length; index += 2) {
      final first = bytes[index];
      final second = bytes[index + 1];
      final value = littleEndian
          ? first | (second << 8)
          : (first << 8) | second;
      buffer.writeCharCode(value);
    }

    if (index < bytes.length) {
      _carry = bytes[index];
    }

    return buffer.toString();
  }

  String flush() {
    if (_carry == null) {
      return '';
    }
    final value = _carry!;
    _carry = null;
    return String.fromCharCode(value);
  }
}
