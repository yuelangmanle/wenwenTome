import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../core/storage/app_storage_paths.dart';
import '../../logging/app_run_log_service.dart';
import '../mobi_converter_service.dart';
import 'book_model.dart';

enum ImportStorageMode { sourceFile, appCopy }

enum LibraryLoadStatus { ready, empty, warning, recoveredData, corruptData }

class LibraryLoadSnapshot {
  const LibraryLoadSnapshot({
    required this.books,
    required this.status,
    this.message,
    this.droppedEntries = 0,
  });

  final List<Book> books;
  final LibraryLoadStatus status;
  final String? message;
  final int droppedEntries;

  bool get hasIssue =>
      status == LibraryLoadStatus.warning ||
      status == LibraryLoadStatus.recoveredData ||
      status == LibraryLoadStatus.corruptData;
}

class LibraryService {
  LibraryService({Future<Directory> Function()? documentsDirProvider})
    : _documentsDirProvider =
          documentsDirProvider ?? getSafeApplicationDocumentsDirectory;

  static const _booksFile = 'books.json';
  static final _uuid = Uuid();
  static const Set<String> _supportedExtensions = {
    'epub',
    'pdf',
    'mobi',
    'azw3',
    'txt',
    'cbz',
    'cbr',
  };

  static String normalizeImportPath(String input) {
    final trimmed = input.trim();
    if (trimmed.startsWith('file://')) {
      try {
        return Uri.parse(trimmed).toFilePath();
      } catch (_) {}
    }
    return trimmed;
  }

  final Future<Directory> Function() _documentsDirProvider;

  String? lastLoadIssue;
  LibraryLoadStatus lastLoadStatus = LibraryLoadStatus.empty;

  static bool isSupportedImportPath(String path) {
    final ext = _ext(normalizeImportPath(path));
    return ext != null && _supportedExtensions.contains(ext);
  }

  static bool shouldForceAppCopy(String path) {
    final normalized =
        normalizeImportPath(path).replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/cache/file_picker/') ||
        normalized.contains('/cache/filepicker/') ||
        normalized.contains('/tmp/file_picker/') ||
        normalized.contains('/tmp/filepicker/');
  }

  static String? _ext(String path) {
    final dot = path.lastIndexOf('.');
    if (dot <= 0 || dot == path.length - 1) {
      return null;
    }
    return path.substring(dot + 1).toLowerCase();
  }

  Future<File> _getDbFile() async {
    final dir = await _documentsDirProvider();
    return File(p.join(dir.path, 'wenwen_tome', _booksFile));
  }

  Future<File> _getBackupFile() async {
    final file = await _getDbFile();
    return File('${file.path}.bak');
  }

  Future<File> _getPartFile() async {
    final file = await _getDbFile();
    return File('${file.path}.part');
  }

  Future<List<Book>> loadBooks({bool returnEmptyOnError = true}) async {
    final snapshot = await loadBooksSnapshot(
      returnEmptyOnError: returnEmptyOnError,
    );
    return snapshot.books.toList(growable: true);
  }

  Future<LibraryLoadSnapshot> loadBooksSnapshot({
    bool returnEmptyOnError = true,
  }) async {
    try {
      final file = await _getDbFile();
      final backup = await _getBackupFile();
      final primary = await _readSnapshotFromFile(file);
      if (primary != null) {
        return _remember(primary);
      }

      final recovered = await _readSnapshotFromFile(
        backup,
        recoveredFromBackup: true,
      );
      if (recovered != null) {
        return _remember(recovered);
      }

      if (!await file.exists() && !await backup.exists()) {
        return _remember(
          const LibraryLoadSnapshot(
            books: <Book>[],
            status: LibraryLoadStatus.empty,
          ),
        );
      }

      return _remember(
        const LibraryLoadSnapshot(
          books: <Book>[],
          status: LibraryLoadStatus.corruptData,
          message: '书架数据损坏，当前无法完整恢复。',
        ),
      );
    } catch (_) {
      if (returnEmptyOnError) {
        return _remember(
          const LibraryLoadSnapshot(
            books: <Book>[],
            status: LibraryLoadStatus.corruptData,
            message: '书架数据暂时不可用，可稍后重试。',
          ),
        );
      }
      rethrow;
    }
  }

  LibraryLoadSnapshot _remember(LibraryLoadSnapshot snapshot) {
    lastLoadStatus = snapshot.status;
    lastLoadIssue = snapshot.message;
    return snapshot;
  }

  Future<LibraryLoadSnapshot?> _readSnapshotFromFile(
    File file, {
    bool recoveredFromBackup = false,
  }) async {
    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    if (content.trim().isEmpty) {
      return LibraryLoadSnapshot(
        books: const <Book>[],
        status: recoveredFromBackup
            ? LibraryLoadStatus.recoveredData
            : LibraryLoadStatus.empty,
        message: recoveredFromBackup ? '书架主数据损坏，已从备份恢复空书架。' : null,
      );
    }

    final decoded = jsonDecode(content);
    if (decoded is! List) {
      throw const FormatException('books.json root must be a list');
    }

    final books = <Book>[];
    var droppedEntries = 0;
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        droppedEntries++;
        continue;
      }

      try {
        books.add(Book.fromJson(item));
      } catch (_) {
        droppedEntries++;
      }
    }

    if (recoveredFromBackup) {
      return LibraryLoadSnapshot(
        books: books,
        status: books.isEmpty
            ? LibraryLoadStatus.recoveredData
            : LibraryLoadStatus.recoveredData,
        message: droppedEntries > 0
            ? '书架主数据损坏，已从备份恢复，并跳过 $droppedEntries 条异常记录。'
            : '书架主数据损坏，已从备份恢复。',
        droppedEntries: droppedEntries,
      );
    }

    if (books.isEmpty &&
        decoded.isNotEmpty &&
        droppedEntries == decoded.length) {
      return const LibraryLoadSnapshot(
        books: <Book>[],
        status: LibraryLoadStatus.corruptData,
        message: '书架数据损坏，当前无法完整恢复。',
      );
    }

    if (droppedEntries > 0) {
      return LibraryLoadSnapshot(
        books: books,
        status: LibraryLoadStatus.warning,
        message: '书架中有 $droppedEntries 条异常记录已被自动跳过。',
        droppedEntries: droppedEntries,
      );
    }

    return LibraryLoadSnapshot(
      books: books,
      status: books.isEmpty ? LibraryLoadStatus.empty : LibraryLoadStatus.ready,
    );
  }

  Future<void> replaceAllBooks(List<Book> books) async {
    await _saveBooks(books);
  }

  Future<void> _saveBooks(List<Book> books) async {
    final file = await _getDbFile();
    final backup = await _getBackupFile();
    final part = await _getPartFile();
    await file.parent.create(recursive: true);
    final jsonList = books.map((book) => book.toJson()).toList();
    if (await part.exists()) {
      await part.delete();
    }
    await part.writeAsString(jsonEncode(jsonList), flush: true);

    if (await file.exists()) {
      await file.copy(backup.path);
      await file.delete();
    }

    await part.rename(file.path);
  }

  Future<Directory> _getBooksStorageDir() async {
    final dir = await _documentsDirProvider();
    final booksDir = Directory(p.join(dir.path, 'wenwen_tome', 'books'));
    await booksDir.create(recursive: true);
    return booksDir;
  }

  Future<String> _copyToAppStorage(String sourcePath) async {
    final source = File(sourcePath);
    if (!await source.exists()) {
      throw Exception('导入失败：源文件不存在');
    }

    final booksDir = await _getBooksStorageDir();
    final originalName = p.basename(sourcePath);
    final baseName = p.basenameWithoutExtension(originalName);
    final ext = p.extension(originalName);

    var counter = 0;
    late File target;
    do {
      final suffix = counter == 0 ? '' : '_$counter';
      target = File(p.join(booksDir.path, '$baseName$suffix$ext'));
      counter++;
    } while (await target.exists());

    await source.copy(target.path);
    return target.path;
  }

  Future<Book> addBook(
    String filePath, {
    ImportStorageMode mode = ImportStorageMode.sourceFile,
  }) async {
    final books = await loadBooks();
    final normalizedPath = normalizeImportPath(filePath);
    if (!isSupportedImportPath(normalizedPath)) {
      throw Exception('不支持的文件类型，仅支持 EPUB/PDF/MOBI/AZW3/TXT/CBZ/CBR');
    }
    if (books.any((book) => book.filePath == normalizedPath)) {
      throw Exception('书籍已存在');
    }

    var finalPath = normalizedPath;
    final ext = _ext(normalizedPath)!;

    if (ext == 'mobi' || ext == 'azw3') {
      try {
        final converted = await MobiConverterService.convertToEpub(filePath);
        if (converted == null) {
          throw Exception('暂不支持直接读取该格式');
        }
        finalPath = converted.outputPath;
      } on MobiConvertFailure catch (e) {
        throw Exception(e.toString());
      }
      if (books.any((book) => book.filePath == finalPath)) {
        throw Exception('书籍已存在');
      }
    }

    final shouldCopy =
        mode == ImportStorageMode.appCopy || shouldForceAppCopy(finalPath);
    if (shouldCopy) {
      if (mode == ImportStorageMode.sourceFile &&
          shouldForceAppCopy(finalPath)) {
        await AppRunLogService.instance.logInfo(
          '检测到临时文件路径，自动改为另存到 App：$finalPath',
        );
      }
      finalPath = await _copyToAppStorage(finalPath);
    }

    final book = Book(
      id: _uuid.v4(),
      filePath: finalPath,
      title: p.basenameWithoutExtension(finalPath),
      author: '未知作者',
      format: Book.formatFromPath(finalPath),
      addedAt: DateTime.now(),
    );

    books.add(book);
    await _saveBooks(books);
    return book;
  }

  Future<Book> addWebNovel(
    String title,
    String sourceName,
    String bookUrl,
  ) async {
    final legacyPath = 'webnovel://$sourceName/$bookUrl';
    return addManagedWebNovel(
      title,
      remoteBookId: '$sourceName:${Uri.encodeComponent(bookUrl)}',
      author: '网文连载 · $sourceName',
      legacyAliases: [legacyPath],
    );
  }

  Future<Book> addManagedWebNovel(
    String title, {
    required String remoteBookId,
    String author = '网文连载',
    List<String> legacyAliases = const <String>[],
  }) async {
    final books = await loadBooks();
    final filePath = 'webnovel://book/$remoteBookId';
    if (books.any(
      (book) =>
          book.filePath == filePath || legacyAliases.contains(book.filePath),
    )) {
      throw Exception('该网文已在书架中');
    }

    final book = Book(
      id: _uuid.v4(),
      filePath: filePath,
      title: title,
      author: author,
      format: BookFormat.webnovel,
      addedAt: DateTime.now(),
    );

    books.add(book);
    await _saveBooks(books);
    return book;
  }

  Future<void> updateProgress(
    String bookId,
    int position,
    double progress,
  ) async {
    final books = await loadBooks();
    final index = books.indexWhere((book) => book.id == bookId);
    if (index == -1) {
      return;
    }

    books[index] = books[index].copyWith(
      lastPosition: position,
      readingProgress: progress,
    );
    await _saveBooks(books);
  }

  Future<void> updateBook(Book updatedBook) async {
    final books = await loadBooks();
    final index = books.indexWhere((book) => book.id == updatedBook.id);
    if (index == -1) {
      return;
    }

    books[index] = updatedBook;
    await _saveBooks(books);
  }

  Future<void> removeBook(String bookId) async {
    final books = await loadBooks();
    books.removeWhere((book) => book.id == bookId);
    await _saveBooks(books);
  }
}
