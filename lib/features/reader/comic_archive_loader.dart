import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart' as archive_io;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../library/data/book_model.dart';

class ComicArchiveLoader {
  ComicArchiveLoader({
    Future<Directory> Function()? cacheDirProvider,
    Future<List<String>> Function(String archivePath)? windowsRarListFiles,
    Future<void> Function(String archivePath, String outputDir)?
    windowsRarExtractAll,
  }) : _cacheDirProvider = cacheDirProvider ?? getApplicationSupportDirectory,
       _windowsRarListFiles = windowsRarListFiles,
       _windowsRarExtractAll = windowsRarExtractAll;

  final Future<Directory> Function() _cacheDirProvider;
  final Future<List<String>> Function(String archivePath)? _windowsRarListFiles;
  final Future<void> Function(String archivePath, String outputDir)?
  _windowsRarExtractAll;

  Future<List<String>> resolveComicPages(Book book) async {
    if (book.format != BookFormat.cbz && book.format != BookFormat.cbr) {
      throw ArgumentError('Only CBZ/CBR formats are supported');
    }

    final sourceFile = File(book.filePath);
    if (!await sourceFile.exists()) {
      throw Exception('${book.format.name.toUpperCase()} file does not exist');
    }

    final cacheDir = await _resolveCacheDir(book, sourceFile);
    final cachedPages = await _collectImageFiles(cacheDir);
    if (cachedPages.isNotEmpty) {
      return cachedPages;
    }

    await _resetDirectory(cacheDir);
    if (book.format == BookFormat.cbz) {
      await _extractCbz(sourceFile, cacheDir);
    } else {
      await _extractCbr(sourceFile, cacheDir);
    }

    final pages = await _collectImageFiles(cacheDir);
    if (pages.isEmpty) {
      throw Exception(
        '${book.format.name.toUpperCase()} archive does not contain images',
      );
    }
    return pages;
  }

  Future<Directory> _resolveCacheDir(Book book, File sourceFile) async {
    final baseDir = await _cacheDirProvider();
    final stat = await sourceFile.stat();
    final versionKey = '${stat.size}_${stat.modified.millisecondsSinceEpoch}'
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
    final root = Directory(
      p.join(baseDir.path, 'wenwen_tome', 'comic_cache', book.id),
    );
    await root.create(recursive: true);

    final target = Directory(p.join(root.path, versionKey));
    await target.create(recursive: true);

    await for (final entity in root.list()) {
      if (entity is Directory && entity.path != target.path) {
        await entity.delete(recursive: true);
      }
    }
    return target;
  }

  Future<void> _resetDirectory(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      return;
    }
    await for (final entity in dir.list()) {
      await entity.delete(recursive: true);
    }
  }

  Future<void> _extractCbz(File archiveFile, Directory outputDir) async {
    final input = archive_io.InputFileStream(archiveFile.path);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      await archive_io.extractArchiveToDisk(archive, outputDir.path);
    } finally {
      await input.close();
    }
  }

  Future<void> _extractCbr(File archiveFile, Directory outputDir) async {
    if (Platform.isAndroid) {
      throw Exception(
        'Android currently does not support CBR. Convert it to CBZ first.',
      );
    }

    if (Platform.isWindows) {
      final listFiles = _windowsRarListFiles ?? _defaultWindowsRarListFiles;
      final extractAll = _windowsRarExtractAll ?? _defaultWindowsRarExtractAll;
      final files = await listFiles(archiveFile.path);
      if (!files.any(_isImageFile)) {
        throw Exception('CBR archive does not contain images');
      }
      await extractAll(archiveFile.path, outputDir.path);
      return;
    }

    throw Exception('Current platform does not support CBR');
  }

  Future<List<String>> _defaultWindowsRarListFiles(String archivePath) async {
    final result = await Process.run('tar', ['-tf', archivePath]);
    if (result.exitCode != 0) {
      throw Exception('Failed to inspect RAR archive: ${result.stderr}');
    }

    return result.stdout
        .toString()
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
  }

  Future<void> _defaultWindowsRarExtractAll(
    String archivePath,
    String outputDir,
  ) async {
    final result = await Process.run('tar', [
      '-xf',
      archivePath,
      '-C',
      outputDir,
    ]);
    if (result.exitCode != 0) {
      throw Exception('Failed to extract RAR archive: ${result.stderr}');
    }
  }

  Future<List<String>> _collectImageFiles(Directory dir) async {
    if (!await dir.exists()) {
      return const <String>[];
    }

    final files = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && _isImageFile(entity.path)) {
        files.add(entity.path);
      }
    }
    files.sort(_naturalPathCompare);
    return files;
  }

  bool _isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp');
  }

  int _naturalPathCompare(String a, String b) {
    final aBase = p.basename(a).toLowerCase();
    final bBase = p.basename(b).toLowerCase();
    final aParts = RegExp(
      r'(\d+|\D+)',
    ).allMatches(aBase).map((m) => m.group(0)!).toList();
    final bParts = RegExp(
      r'(\d+|\D+)',
    ).allMatches(bBase).map((m) => m.group(0)!).toList();
    final limit = aParts.length < bParts.length ? aParts.length : bParts.length;

    for (var i = 0; i < limit; i++) {
      final aPart = aParts[i];
      final bPart = bParts[i];
      final aNumber = int.tryParse(aPart);
      final bNumber = int.tryParse(bPart);
      if (aNumber != null && bNumber != null) {
        final numberCompare = aNumber.compareTo(bNumber);
        if (numberCompare != 0) {
          return numberCompare;
        }
        continue;
      }

      final textCompare = aPart.compareTo(bPart);
      if (textCompare != 0) {
        return textCompare;
      }
    }

    return aParts.length.compareTo(bParts.length);
  }
}
