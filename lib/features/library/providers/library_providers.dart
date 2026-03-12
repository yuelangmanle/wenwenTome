import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/runtime_platform.dart';
import '../../../core/storage/app_storage_paths.dart';
import '../../logging/app_run_log_service.dart';
import '../data/book_model.dart';
import '../data/library_service.dart';

final libraryServiceProvider = Provider<LibraryService>(
  (ref) => LibraryService(),
);

final booksLoadIssueProvider = Provider<String?>((ref) {
  ref.watch(booksProvider);
  return ref.read(libraryServiceProvider).lastLoadIssue;
});

final booksLoadStatusProvider = Provider<LibraryLoadStatus>((ref) {
  ref.watch(booksProvider);
  return ref.read(libraryServiceProvider).lastLoadStatus;
});

final booksStartupTimeoutProvider = Provider<Duration>(
  (ref) => detectLocalRuntimePlatform() == LocalRuntimePlatform.android
      ? const Duration(seconds: 12)
      : const Duration(seconds: 3),
);
final booksBackgroundRetryDelayProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 1),
);
final booksBackgroundRetryTimeoutProvider = Provider<Duration>(
  (ref) => detectLocalRuntimePlatform() == LocalRuntimePlatform.android
      ? const Duration(seconds: 18)
      : const Duration(seconds: 8),
);

final booksProvider = AsyncNotifierProvider<BooksNotifier, List<Book>>(
  BooksNotifier.new,
);

class BooksNotifier extends AsyncNotifier<List<Book>> {
  bool _backgroundRetryScheduled = false;

  static const _storageUnavailableMessage = '存储暂时不可用，可重试';
  static const _libraryUnavailableMessage = '书架数据暂时不可用，可重试';

  @override
  Future<List<Book>> build() async {
    final service = ref.read(libraryServiceProvider);
    service.lastLoadIssue = null;
    service.lastLoadStatus = LibraryLoadStatus.empty;
    final startupTimeout = ref.read(booksStartupTimeoutProvider);

    try {
      final snapshot = await service
          .loadBooksSnapshot(returnEmptyOnError: false)
          .timeout(startupTimeout);
      return snapshot.books;
    } on TimeoutException {
      service.lastLoadIssue = _storageUnavailableMessage;
      service.lastLoadStatus = LibraryLoadStatus.warning;
      _scheduleBackgroundRetry();
      return const <Book>[];
    } catch (error, stackTrace) {
      service.lastLoadIssue = _libraryUnavailableMessage;
      service.lastLoadStatus = LibraryLoadStatus.corruptData;
      unawaited(
        AppRunLogService.instance.logError(
          'booksProvider:initial_load_failed; error=$error\n$stackTrace',
        ),
      );
      _scheduleBackgroundRetry();
      return const <Book>[];
    }
  }

  Future<void> retryLoad() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> importBook(
    String filePath, {
    ImportStorageMode mode = ImportStorageMode.sourceFile,
  }) async {
    final service = ref.read(libraryServiceProvider);
    await service.addBook(filePath, mode: mode);
    ref.invalidateSelf();
    await future;
  }

  Future<void> addWebNovel(
    String title,
    String sourceName,
    String bookUrl,
  ) async {
    final service = ref.read(libraryServiceProvider);
    await service.addWebNovel(title, sourceName, bookUrl);
    ref.invalidateSelf();
    await future;
  }

  Future<void> addManagedWebNovel(
    String title, {
    required String remoteBookId,
    String author = '网文连载',
    List<String> legacyAliases = const <String>[],
  }) async {
    final service = ref.read(libraryServiceProvider);
    await service.addManagedWebNovel(
      title,
      remoteBookId: remoteBookId,
      author: author,
      legacyAliases: legacyAliases,
    );
    ref.invalidateSelf();
    await future;
  }

  Future<void> removeBook(String bookId) async {
    final service = ref.read(libraryServiceProvider);
    await service.removeBook(bookId);
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateProgress(String bookId, int pos, double progress) async {
    final service = ref.read(libraryServiceProvider);
    await service.updateProgress(bookId, pos, progress);
    ref.invalidateSelf();
    await future;
  }

  Future<void> updateBook(Book updatedBook) async {
    final service = ref.read(libraryServiceProvider);
    await service.updateBook(updatedBook);
    ref.invalidateSelf();
    await future;
  }

  void _scheduleBackgroundRetry() {
    if (_backgroundRetryScheduled) {
      return;
    }
    _backgroundRetryScheduled = true;
    final service = ref.read(libraryServiceProvider);
    final retryDelay = ref.read(booksBackgroundRetryDelayProvider);
    final retryTimeout = ref.read(booksBackgroundRetryTimeoutProvider);
    var cancelled = false;
    ref.onDispose(() {
      cancelled = true;
      _backgroundRetryScheduled = false;
    });

    unawaited(
      Future<void>(() async {
        await Future<void>.delayed(retryDelay);
        if (cancelled) {
          return;
        }
        try {
          final snapshot = await service
              .loadBooksSnapshot(returnEmptyOnError: false)
              .timeout(retryTimeout);
          if (cancelled) {
            return;
          }
          state = AsyncData(snapshot.books);
        } catch (_) {
          if (cancelled) {
            return;
          }
          service.lastLoadIssue ??= _storageUnavailableMessage;
          service.lastLoadStatus = LibraryLoadStatus.warning;
        } finally {
          _backgroundRetryScheduled = false;
        }
      }),
    );
  }
}

Future<List<String>?> pickBookFiles() async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: ['epub', 'pdf', 'mobi', 'azw3', 'txt', 'cbz', 'cbr'],
    withData: false,
    withReadStream: true,
  );
  if (result == null) {
    return null;
  }

  final docsDir = await getSafeApplicationDocumentsDirectory();
  final bytesImportDir = Directory(
    p.join(docsDir.path, 'wenwen_tome', 'imports'),
  );

  final paths = await normalizePickedBookFiles(
    result.files,
    bytesImportDir: bytesImportDir,
  );

  if (paths.isEmpty) {
    return null;
  }
  return paths;
}

Future<List<String>> normalizePickedBookFiles(
  List<PlatformFile> files, {
  required Directory bytesImportDir,
}) async {
  final paths = <String>[];
  await bytesImportDir.create(recursive: true);

  for (final file in files) {
    final filePath = file.path?.trim() ?? '';
    if (filePath.isNotEmpty) {
      if (filePath.startsWith('content://')) {
        // Prefer readStream/bytes for content URIs.
      } else {
        var resolvedPath = filePath;
        if (resolvedPath.startsWith('file://')) {
          try {
            resolvedPath = Uri.parse(resolvedPath).toFilePath();
          } catch (_) {}
        }
        if (resolvedPath.isNotEmpty) {
          paths.add(resolvedPath);
          continue;
        }
      }
    }

    final readStream = file.readStream;
    if (readStream != null) {
      final outFile = await _allocateImportOutputFile(
        bytesImportDir,
        file.name,
      );
      final sink = outFile.openWrite();
      try {
        await sink.addStream(readStream);
      } finally {
        await sink.close();
      }
      if (await outFile.length() > 0) {
        paths.add(outFile.path);
      } else {
        await outFile.delete();
      }
      continue;
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      continue;
    }

    final outFile = await _allocateImportOutputFile(bytesImportDir, file.name);
    await outFile.writeAsBytes(bytes, flush: true);
    paths.add(outFile.path);
  }

  return paths;
}

Future<File> _allocateImportOutputFile(
  Directory outputDir,
  String rawName,
) async {
  final cleanName = rawName.trim().isEmpty
      ? 'imported_book.bin'
      : rawName.trim();
  final base = p.basenameWithoutExtension(cleanName);
  final ext = p.extension(cleanName);

  var index = 0;
  late File outFile;
  do {
    final suffix = index == 0 ? '' : '_$index';
    final fileName = '$base$suffix$ext';
    outFile = File(p.join(outputDir.path, fileName));
    index++;
  } while (await outFile.exists());
  return outFile;
}
