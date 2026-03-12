import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/utils/text_sanitizer.dart';
import '../../core/storage/app_storage_paths.dart';

class ImportedReaderFont {
  const ImportedReaderFont({
    required this.family,
    required this.displayName,
    required this.path,
  });

  final String family;
  final String displayName;
  final String path;
}

class ReaderCustomFontManager {
  static final Set<String> _loadedFamilies = <String>{};

  static Future<ImportedReaderFont?> pickAndImportFont() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['ttf', 'otf'],
      withData: true,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }

    return importPlatformFile(result.files.first);
  }

  static Future<ImportedReaderFont?> importPlatformFile(
    PlatformFile file,
  ) async {
    final bytes = file.bytes ?? await _readPlatformFileBytes(file);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    final originalName = file.name.trim().isEmpty
        ? 'reader_font.ttf'
        : file.name.trim();
    final ext = p.extension(originalName).isEmpty
        ? '.ttf'
        : p.extension(originalName);
    final rawDisplayName = p.basenameWithoutExtension(originalName);
    final baseName = rawDisplayName.replaceAll(
      RegExp(r'[^A-Za-z0-9._-]+'),
      '_',
    );
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final family = 'reader_font_$stamp';

    final docsDir = await getSafeApplicationDocumentsDirectory();
    final fontDir = Directory(
      p.join(docsDir.path, 'wenwen_tome', 'reader_fonts'),
    );
    await fontDir.create(recursive: true);

    final outPath = p.join(fontDir.path, '${baseName}_$stamp$ext');
    final outFile = File(outPath);
    await outFile.writeAsBytes(bytes, flush: true);

    final loaded = await ensureFontLoaded(path: outPath, family: family);
    if (!loaded) {
      return null;
    }

    return ImportedReaderFont(
      family: family,
      displayName: sanitizeUiText(rawDisplayName, fallback: baseName),
      path: outPath,
    );
  }

  static Future<bool> ensureFontLoaded({
    required String path,
    required String family,
  }) async {
    if (_loadedFamilies.contains(family)) {
      return true;
    }

    final file = File(path);
    if (!await file.exists()) {
      return false;
    }

    try {
      final bytes = await file.readAsBytes();
      final loader = FontLoader(family);
      loader.addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loadedFamilies.add(family);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<Uint8List?> _readPlatformFileBytes(PlatformFile file) async {
    final filePath = file.path;
    if (filePath == null || filePath.trim().isEmpty) {
      return null;
    }
    return File(filePath).readAsBytes();
  }

}
