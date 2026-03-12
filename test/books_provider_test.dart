import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/library/data/book_model.dart';
import 'package:wenwen_tome/features/library/data/library_service.dart';
import 'package:wenwen_tome/features/library/providers/library_providers.dart';

class _FakeLibraryService extends LibraryService {
  _FakeLibraryService(this._loader);

  final Future<List<Book>> Function({required bool returnEmptyOnError}) _loader;

  @override
  Future<LibraryLoadSnapshot> loadBooksSnapshot({
    bool returnEmptyOnError = true,
  }) async {
    final books = await _loader(returnEmptyOnError: returnEmptyOnError);
    final snapshot = LibraryLoadSnapshot(
      books: books,
      status: books.isEmpty ? LibraryLoadStatus.empty : LibraryLoadStatus.ready,
    );
    lastLoadIssue = snapshot.message;
    lastLoadStatus = snapshot.status;
    return snapshot;
  }

  @override
  Future<List<Book>> loadBooks({bool returnEmptyOnError = true}) {
    return _loader(returnEmptyOnError: returnEmptyOnError);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'booksProvider falls back quickly and refreshes in background',
    () async {
      var loadCount = 0;
      final sampleBook = Book(
        id: 'book-1',
        filePath: 'sample.epub',
        title: '示例书籍',
        author: '作者',
        format: BookFormat.epub,
        addedAt: DateTime(2026, 3, 7),
      );

      final container = ProviderContainer(
        overrides: [
          libraryServiceProvider.overrideWithValue(
            _FakeLibraryService(({required returnEmptyOnError}) async {
              loadCount++;
              if (loadCount == 1) {
                await Future<void>.delayed(const Duration(milliseconds: 120));
              }
              return [sampleBook];
            }),
          ),
          booksStartupTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 20),
          ),
          booksBackgroundRetryDelayProvider.overrideWithValue(
            const Duration(milliseconds: 10),
          ),
          booksBackgroundRetryTimeoutProvider.overrideWithValue(
            const Duration(milliseconds: 80),
          ),
        ],
      );
      addTearDown(container.dispose);

      final initialBooks = await container.read(booksProvider.future);
      expect(initialBooks, isEmpty);
      expect(container.read(booksLoadIssueProvider), isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 40));

      final refreshedBooks = container.read(booksProvider).asData?.value;
      expect(refreshedBooks, isNotNull);
      expect(refreshedBooks, hasLength(1));
      expect(refreshedBooks!.first.title, '示例书籍');
      expect(container.read(booksLoadIssueProvider), isNull);
    },
  );
}
