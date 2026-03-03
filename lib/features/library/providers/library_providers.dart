import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../data/book_model.dart';
import '../data/library_service.dart';

final libraryServiceProvider = Provider<LibraryService>((ref) => LibraryService());

final booksProvider = AsyncNotifierProvider<BooksNotifier, List<Book>>(BooksNotifier.new);

class BooksNotifier extends AsyncNotifier<List<Book>> {
  @override
  Future<List<Book>> build() async {
    return ref.read(libraryServiceProvider).loadBooks();
  }

  Future<void> importBook(String filePath) async {
    final service = ref.read(libraryServiceProvider);
    await service.importBook(filePath);
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
}

/// 通用文件选择器 - 支持所有书籍格式
Future<List<String>?> pickBookFiles() async {
  final result = await FilePicker.platform.pickFiles(
    allowMultiple: true,
    type: FileType.custom,
    allowedExtensions: ['epub', 'pdf', 'mobi', 'azw3', 'txt', 'cbz', 'cbr'],
  );
  return result?.files.map((f) => f.path!).toList();
}
