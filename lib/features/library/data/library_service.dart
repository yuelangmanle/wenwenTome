import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'book_model.dart';

class LibraryService {
  static const _dbFileName = 'library.json';
  static final _uuid = Uuid();

  /// 获取本地持久化文件路径
  Future<File> _getDbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/wenwen_tome/$_dbFileName');
  }

  /// 读取全部书籍
  Future<List<Book>> loadBooks() async {
    try {
      final file = await _getDbFile();
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      return jsonList.map((j) => Book.fromJson(j)).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存全部书籍
  Future<void> _saveBooks(List<Book> books) async {
    final file = await _getDbFile();
    await file.parent.create(recursive: true);
    final jsonList = books.map((b) => b.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList));
  }

  /// 导入一本书（通过文件路径）
  Future<Book> importBook(String filePath) async {
    final books = await loadBooks();
    // 检查重复
    final exists = books.any((b) => b.filePath == filePath);
    if (exists) throw Exception('该书籍已在书库中');

    final file = File(filePath);
    final fileName = filePath.split(Platform.pathSeparator).last;
    final titleWithoutExt = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;

    final book = Book(
      id: _uuid.v4(),
      filePath: filePath,
      title: titleWithoutExt,
      author: '未知作者',
      format: Book.formatFromPath(filePath),
      addedAt: DateTime.now(),
    );

    books.add(book);
    await _saveBooks(books);
    return book;
  }

  /// 更新阅读进度
  Future<void> updateProgress(String bookId, int position, double progress) async {
    final books = await loadBooks();
    final idx = books.indexWhere((b) => b.id == bookId);
    if (idx == -1) return;
    books[idx] = books[idx].copyWith(
      lastPosition: position,
      readingProgress: progress,
    );
    await _saveBooks(books);
  }

  /// 删除书籍（仅删除记录，不删除文件）
  Future<void> removeBook(String bookId) async {
    final books = await loadBooks();
    books.removeWhere((b) => b.id == bookId);
    await _saveBooks(books);
  }
}
