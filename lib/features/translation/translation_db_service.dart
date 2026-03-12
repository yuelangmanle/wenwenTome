import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database_factory.dart';

class TranslationDbService {
  static final TranslationDbService _instance = TranslationDbService._internal();
  factory TranslationDbService() => _instance;
  TranslationDbService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    final path = await getAppDatabasePath('wenwen_translation.db');

    return await appDatabaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE chapter_translations (
            id TEXT PRIMARY KEY,
            book_id TEXT NOT NULL,
            chapter_id TEXT NOT NULL,
            status TEXT NOT NULL, -- pending, translating, completed, failed
            original_text TEXT,
            translated_text TEXT,
            progress REAL DEFAULT 0.0,
            error_msg TEXT,
            updated_at INTEGER NOT NULL
          )
        ''');
        
        await db.execute(
          'CREATE INDEX idx_book_chapter ON chapter_translations(book_id, chapter_id)'
        );
        },
      ),
    );
  }

  /// 获取某本书的所有翻译记录
  Future<List<Map<String, dynamic>>> getTranslationsByBook(String bookId) async {
    final db = await database;
    return await db.query(
      'chapter_translations',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  /// 获取特定章节的翻译记录
  Future<Map<String, dynamic>?> getTranslationByChapter(String bookId, String chapterId) async {
    final db = await database;
    final results = await db.query(
      'chapter_translations',
      where: 'book_id = ? AND chapter_id = ?',
      whereArgs: [bookId, chapterId],
      limit: 1,
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// 保存或更新翻译进度/状态
  Future<void> saveTranslation({
    required String id,
    required String bookId,
    required String chapterId,
    required String status,
    String? originalText,
    String? translatedText,
    double progress = 0.0,
    String? errorMsg,
  }) async {
    final db = await database;
    
    final data = {
      'id': id,
      'book_id': bookId,
      'chapter_id': chapterId,
      'status': status,
      'original_text': originalText,
      'translated_text': translatedText,
      'progress': progress,
      'error_msg': errorMsg,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    
    // 如果是原文字段或译文字段为 null，且是更新操作，我们期望保留原有数据的部分值
    // 使用 INSERT OR REPLACE 配合事先查询来合并数据（或者使用特定 update）
    final existing = await getTranslationByChapter(bookId, chapterId);
    
    if (existing != null) {
      // 增量更新
      final updateData = Map<String, dynamic>.from(data);
      if (originalText == null) updateData.remove('original_text');
      if (translatedText == null) updateData.remove('translated_text');
      if (errorMsg == null) updateData.remove('error_msg');
      
      await db.update(
        'chapter_translations',
        updateData,
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.insert(
        'chapter_translations',
        data,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 清除某本书的所有翻译缓存
  Future<void> clearTranslations(String bookId) async {
    final db = await database;
    await db.delete(
      'chapter_translations',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }
}
