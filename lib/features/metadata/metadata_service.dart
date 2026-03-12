import 'dart:convert';
import 'dart:io';

import '../../core/storage/app_storage_paths.dart';

/// 在线元数据补全服务。
class MetadataService {
  static const _googleBooksBase = 'https://www.googleapis.com/books/v1/volumes';
  static const _doubanBase = 'https://api.douban.com/v2/book/search';
  static const _openLibraryBase = 'https://openlibrary.org/search.json';

  final _client = HttpClient();

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final request = await _client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'WenwenTome/2.1');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode >= 400) {
      return null;
    }
    final body = await response.transform(utf8.decoder).join();
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  Future<BookMeta?> searchBestEffort(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) {
      return null;
    }

    return await searchGoogleBooks(normalized) ??
        await searchOpenLibrary(normalized) ??
        await searchDouban(normalized);
  }

  Future<BookMeta?> searchGoogleBooks(String query) async {
    try {
      final uri = Uri.parse(
        '$_googleBooksBase?q=${Uri.encodeQueryComponent(query)}&langRestrict=zh&maxResults=1&printType=books',
      );
      final json = await _getJson(uri);
      final items = json?['items'] as List?;
      if (items == null || items.isEmpty) {
        return null;
      }
      final volume = items.first as Map<String, dynamic>;
      final info = volume['volumeInfo'] as Map<String, dynamic>? ?? const {};
      final identifiers = (info['industryIdentifiers'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => item['identifier']?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      final imageLinks =
          info['imageLinks'] as Map<String, dynamic>? ?? const {};
      return BookMeta(
        title: info['title']?.toString() ?? query,
        author: (info['authors'] as List?)?.join(', ') ?? '',
        description: info['description']?.toString() ?? '',
        coverUrl:
            imageLinks['thumbnail']?.toString() ??
            imageLinks['smallThumbnail']?.toString(),
        isbn: identifiers.isEmpty ? '' : identifiers.first,
        publisher: info['publisher']?.toString() ?? '',
        publishDate: info['publishedDate']?.toString() ?? '',
        tags:
            (info['categories'] as List?)
                ?.map((item) => '$item')
                .toList(growable: false) ??
            const <String>[],
      );
    } catch (_) {
      return null;
    }
  }

  Future<BookMeta?> searchDouban(String query) async {
    try {
      final uri = Uri.parse(
        '$_doubanBase?q=${Uri.encodeQueryComponent(query)}&count=1',
      );
      final json = await _getJson(uri);
      final books = json?['books'] as List?;
      if (books == null || books.isEmpty) {
        return null;
      }
      final book = books.first as Map<String, dynamic>;
      return BookMeta(
        title: book['title']?.toString() ?? query,
        author: (book['author'] as List?)?.join(', ') ?? '',
        description: book['summary']?.toString() ?? '',
        coverUrl: (book['images'] as Map<String, dynamic>?)?['large']
            ?.toString(),
        isbn: book['isbn13']?.toString() ?? book['isbn10']?.toString() ?? '',
        publisher: book['publisher']?.toString() ?? '',
        publishDate: book['pubdate']?.toString() ?? '',
        tags:
            (book['tags'] as List?)
                ?.whereType<Map>()
                .map((item) => item['name']?.toString() ?? '')
                .where((item) => item.isNotEmpty)
                .toList(growable: false) ??
            const <String>[],
      );
    } catch (_) {
      return null;
    }
  }

  Future<BookMeta?> searchOpenLibrary(String query) async {
    try {
      final uri = Uri.parse(
        '$_openLibraryBase?q=${Uri.encodeQueryComponent(query)}&limit=1',
      );
      final json = await _getJson(uri);
      final docs = json?['docs'] as List?;
      if (docs == null || docs.isEmpty) {
        return null;
      }
      final doc = docs.first as Map<String, dynamic>;
      final coverId = doc['cover_i'];
      return BookMeta(
        title: doc['title']?.toString() ?? query,
        author: (doc['author_name'] as List?)?.join(', ') ?? '',
        description: '',
        coverUrl: coverId == null
            ? null
            : 'https://covers.openlibrary.org/b/id/$coverId-L.jpg',
        isbn: (doc['isbn'] as List?)?.firstOrNull?.toString() ?? '',
        publisher: (doc['publisher'] as List?)?.firstOrNull?.toString() ?? '',
        publishDate: doc['first_publish_year']?.toString() ?? '',
        tags:
            (doc['subject'] as List?)
                ?.take(5)
                .map((item) => '$item')
                .toList(growable: false) ??
            const <String>[],
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> downloadCover(String coverUrl, String bookId) async {
    try {
      final dir = await getSafeApplicationDocumentsDirectory();
      final coverDir = Directory('${dir.path}/wenwen_tome/covers');
      await coverDir.create(recursive: true);
      final filePath = '${coverDir.path}/$bookId.jpg';
      final file = File(filePath);
      if (await file.exists()) {
        return filePath;
      }

      final request = await _client.getUrl(Uri.parse(coverUrl));
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode >= 400) {
        return null;
      }
      final sink = file.openWrite();
      await response.pipe(sink);
      await sink.close();
      return filePath;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}

class BookMeta {
  const BookMeta({
    required this.title,
    required this.author,
    required this.description,
    this.coverUrl,
    required this.isbn,
    required this.publisher,
    required this.publishDate,
    required this.tags,
  });

  final String title;
  final String author;
  final String description;
  final String? coverUrl;
  final String isbn;
  final String publisher;
  final String publishDate;
  final List<String> tags;
}
