import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../library/data/book_model.dart';
import '../library/data/library_service.dart';

/// 在线元数据补全服务（豆瓣 + OpenLibrary）
class MetadataService {
  static const _doubanBase = 'https://api.douban.com/v2/book/search';
  static const _openLibraryBase = 'https://openlibrary.org/search.json';

  final _client = HttpClient();

  /// 按 ISBN / 书名 搜索豆瓣元数据
  Future<BookMeta?> searchDouban(String query) async {
    try {
      final uri = Uri.parse('$_doubanBase?q=${Uri.encodeComponent(query)}&count=1');
      final req = await _client.getUrl(uri);
      req.headers.set('User-Agent', 'WenwenTome/1.0');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final books = json['books'] as List?;
      if (books == null || books.isEmpty) return null;
      final b = books.first as Map<String, dynamic>;
      return BookMeta(
        title: b['title'] ?? query,
        author: (b['author'] as List?)?.join(', ') ?? '',
        description: b['summary'] ?? '',
        coverUrl: b['images']?['large'],
        isbn: b['isbn13'] ?? b['isbn10'] ?? '',
        publisher: b['publisher'] ?? '',
        publishDate: b['pubdate'] ?? '',
        tags: (b['tags'] as List?)?.map((t) => t['name'] as String).toList() ?? [],
      );
    } catch (_) {
      return null;
    }
  }

  /// OpenLibrary 查询（英文书籍兜底）
  Future<BookMeta?> searchOpenLibrary(String query) async {
    try {
      final uri = Uri.parse('$_openLibraryBase?q=${Uri.encodeComponent(query)}&limit=1');
      final req = await _client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final docs = json['docs'] as List?;
      if (docs == null || docs.isEmpty) return null;
      final d = docs.first as Map<String, dynamic>;
      final coverId = d['cover_i'];
      return BookMeta(
        title: d['title'] ?? query,
        author: (d['author_name'] as List?)?.join(', ') ?? '',
        description: '',
        coverUrl: coverId != null
            ? 'https://covers.openlibrary.org/b/id/$coverId-L.jpg'
            : null,
        isbn: (d['isbn'] as List?)?.firstOrNull ?? '',
        publisher: (d['publisher'] as List?)?.firstOrNull ?? '',
        publishDate: d['first_publish_year']?.toString() ?? '',
        tags: (d['subject'] as List?)?.take(5).cast<String>().toList() ?? [],
      );
    } catch (_) {
      return null;
    }
  }

  /// 下载封面并缓存到本地
  Future<String?> downloadCover(String coverUrl, String bookId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final coverDir = Directory('${dir.path}/wenwen_tome/covers');
      await coverDir.create(recursive: true);
      final filePath = '${coverDir.path}/$bookId.jpg';
      final file = File(filePath);
      if (await file.exists()) return filePath;

      final req = await _client.getUrl(Uri.parse(coverUrl));
      final resp = await req.close().timeout(const Duration(seconds: 15));
      final sink = file.openWrite();
      await resp.pipe(sink);
      await sink.close();
      return filePath;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}

/// 书籍元数据载体
class BookMeta {
  final String title;
  final String author;
  final String description;
  final String? coverUrl;
  final String isbn;
  final String publisher;
  final String publishDate;
  final List<String> tags;

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
}
