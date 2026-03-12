

enum BookFormat { epub, pdf, mobi, azw3, txt, cbz, cbr, webnovel, unknown }

class Book {
  final String id;
  final String filePath;
  final String title;
  final String author;
  final String? coverPath;
  final BookFormat format;
  final DateTime addedAt;
  final int lastPosition; // 上次阅读位置 (字符偏移 or 页码)
  final double readingProgress; // 0.0 ~ 1.0
  final List<String> tags;
  // 新增：沉浸式阅读时长与最后阅读日期
  final int readingTimeSeconds;
  final String? lastReadDay; // 格式: yyyy-MM-dd

  const Book({
    required this.id,
    required this.filePath,
    required this.title,
    required this.author,
    this.coverPath,
    required this.format,
    required this.addedAt,
    this.lastPosition = 0,
    this.readingProgress = 0.0,
    this.tags = const [],
    this.readingTimeSeconds = 0,
    this.lastReadDay,
  });

  /// 从文件扩展名判断格式
  static BookFormat formatFromPath(String path) {
    if (path.startsWith('webnovel://')) return BookFormat.webnovel;
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'epub': return BookFormat.epub;
      case 'pdf':  return BookFormat.pdf;
      case 'mobi': return BookFormat.mobi;
      case 'azw3': return BookFormat.azw3;
      case 'txt':  return BookFormat.txt;
      case 'cbz':  return BookFormat.cbz;
      case 'cbr':  return BookFormat.cbr;
      default:     return BookFormat.unknown;
    }
  }

  Book copyWith({
    String? id,
    String? filePath,
    String? title,
    String? author,
    String? coverPath,
    BookFormat? format,
    DateTime? addedAt,
    int? lastPosition,
    double? readingProgress,
    List<String>? tags,
    int? readingTimeSeconds,
    String? lastReadDay,
  }) {
    return Book(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      title: title ?? this.title,
      author: author ?? this.author,
      coverPath: coverPath ?? this.coverPath,
      format: format ?? this.format,
      addedAt: addedAt ?? this.addedAt,
      lastPosition: lastPosition ?? this.lastPosition,
      readingProgress: readingProgress ?? this.readingProgress,
      tags: tags ?? this.tags,
      readingTimeSeconds: readingTimeSeconds ?? this.readingTimeSeconds,
      lastReadDay: lastReadDay ?? this.lastReadDay,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'filePath': filePath,
    'title': title,
    'author': author,
    'coverPath': coverPath,
    'format': format.name,
    'addedAt': addedAt.toIso8601String(),
    'lastPosition': lastPosition,
    'readingProgress': readingProgress,
    'tags': tags,
    'readingTimeSeconds': readingTimeSeconds,
    'lastReadDay': lastReadDay,
  };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'],
    filePath: json['filePath'],
    title: json['title'],
    author: json['author'],
    coverPath: json['coverPath'],
    format: BookFormat.values.firstWhere(
      (f) => f.name == json['format'],
      orElse: () => BookFormat.unknown,
    ),
    addedAt: DateTime.parse(json['addedAt']),
    lastPosition: json['lastPosition'] ?? 0,
    readingProgress: (json['readingProgress'] ?? 0.0).toDouble(),
    tags: List<String>.from(json['tags'] ?? []),
    readingTimeSeconds: json['readingTimeSeconds'] ?? 0,
    lastReadDay: json['lastReadDay'],
  );
}
