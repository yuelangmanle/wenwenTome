import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wenwen_tome/features/webnovel/webnovel_download_manager.dart';

Future<Database> _openTestDatabase() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);

  await db.execute('''
    CREATE TABLE web_chapters (
      id TEXT PRIMARY KEY,
      web_book_id TEXT NOT NULL,
      chapter_index INTEGER NOT NULL
    )
  ''');
  await db.execute('''
    CREATE UNIQUE INDEX idx_web_chapters_book_index
    ON web_chapters(web_book_id, chapter_index)
  ''');

  await db.execute('''
    CREATE TABLE web_chapter_cache (
      chapter_id TEXT PRIMARY KEY,
      text TEXT NOT NULL,
      is_complete INTEGER NOT NULL DEFAULT 1
    )
  ''');

  await db.execute('''
    CREATE TABLE web_download_tasks (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      status TEXT NOT NULL,
      web_book_id TEXT NOT NULL,
      parent_task_id TEXT NOT NULL,
      start_index INTEGER,
      end_index INTEGER,
      chapter_index INTEGER,
      force_refresh INTEGER NOT NULL DEFAULT 0,
      priority INTEGER NOT NULL DEFAULT 0,
      attempt INTEGER NOT NULL DEFAULT 0,
      total_count INTEGER NOT NULL DEFAULT 0,
      completed_count INTEGER NOT NULL DEFAULT 0,
      failed_count INTEGER NOT NULL DEFAULT 0,
      next_run_at INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL DEFAULT 0,
      last_error_type TEXT NOT NULL DEFAULT '',
      last_error_message TEXT NOT NULL DEFAULT ''
    )
  ''');
  await db.execute('''
    CREATE INDEX idx_web_download_tasks_due
    ON web_download_tasks(status, type, next_run_at, priority, created_at)
  ''');

  await db.execute('''
    CREATE TABLE web_download_settings (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
  ''');

  return db;
}

Future<void> _seedBook(Database db, String bookId, int chapterCount) async {
  for (var index = 0; index < chapterCount; index++) {
    await db.insert('web_chapters', {
      'id': '$bookId-c$index',
      'web_book_id': bookId,
      'chapter_index': index,
    });
  }
}

void main() {
  test('deduplicates active book tasks by merging ranges', () async {
    final db = await _openTestDatabase();
    addTearDown(db.close);

    const bookId = 'book-1';
    await _seedBook(db, bookId, 5);

    final downloaded = <int>[];
    var clock = DateTime(2026, 3, 10);
    DateTime tick() {
      clock = clock.add(const Duration(microseconds: 10));
      return clock;
    }

    final manager = WebNovelDownloadManager(
      database: () async => db,
      now: tick,
      delay: (_) async {},
      downloadChapter: (
        String webBookId,
        int chapterIndex, {
        required bool forceRefresh,
      }) async {
        downloaded.add(chapterIndex);
        await db.insert(
          'web_chapter_cache',
          {
            'chapter_id': '$bookId-c$chapterIndex',
            'text': 'content $chapterIndex',
            'is_complete': 1,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      },
    );

    final first = await manager.enqueueBookCache(
      bookId,
      startIndex: 0,
      endIndex: 1,
    );
    final second = await manager.enqueueBookCache(
      bookId,
      startIndex: 1,
      endIndex: 3,
    );

    expect(second.bookTaskId, first.bookTaskId);
    expect(second.startIndex, 0);
    expect(second.endIndex, 3);

    final activeBookTasks = Sqflite.firstIntValue(
      await db.rawQuery(
        '''
        SELECT COUNT(1) FROM web_download_tasks
        WHERE type = 'book' AND web_book_id = ? AND status IN ('queued','running','paused')
        ''',
        [bookId],
      ),
    );
    expect(activeBookTasks, 1);

    await manager.pumpOnce(); // expand
    await manager.pumpOnce(); // download 2 chapters
    await manager.pumpOnce(); // download remaining chapters

    downloaded.sort();
    expect(downloaded, [0, 1, 2, 3]);

    final bookStatus = (await db.query(
      'web_download_tasks',
      columns: ['status', 'total_count', 'completed_count', 'failed_count'],
      where: 'id = ?',
      whereArgs: [first.bookTaskId],
      limit: 1,
    ))
        .single;
    expect(bookStatus['status'], 'completed');
    expect(bookStatus['total_count'], 4);
    expect(bookStatus['completed_count'], 4);
    expect(bookStatus['failed_count'], 0);
  });

  test('keeps newly enqueued tasks paused when paused globally', () async {
    final db = await _openTestDatabase();
    addTearDown(db.close);

    const bookId = 'book-2';
    await _seedBook(db, bookId, 3);

    final downloaded = <int>[];
    var clock = DateTime(2026, 3, 10, 1);
    DateTime tick() {
      clock = clock.add(const Duration(microseconds: 10));
      return clock;
    }

    final manager = WebNovelDownloadManager(
      database: () async => db,
      now: tick,
      delay: (_) async {},
      downloadChapter: (
        String webBookId,
        int chapterIndex, {
        required bool forceRefresh,
      }) async {
        downloaded.add(chapterIndex);
      },
    );

    await manager.pauseAll();
    final enqueued = await manager.enqueueBookCache(bookId, startIndex: 0, endIndex: 2);

    final taskRow = (await db.query(
      'web_download_tasks',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [enqueued.bookTaskId],
      limit: 1,
    ))
        .single;
    expect(taskRow['status'], 'paused');

    await manager.pumpOnce();
    expect(downloaded, isEmpty);

    await manager.resumeAll();
    await manager.pumpOnce(); // expand
    await manager.pumpOnce(); // download
    await manager.pumpOnce(); // download
    downloaded.sort();
    expect(downloaded, [0, 1, 2]);
  });

  test('skips cached chapters unless forceRefresh is true', () async {
    final db = await _openTestDatabase();
    addTearDown(db.close);

    const bookId = 'book-3';
    await _seedBook(db, bookId, 2);

    await db.insert(
      'web_chapter_cache',
      {
        'chapter_id': '$bookId-c0',
        'text': 'cached',
        'is_complete': 1,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    final downloaded = <int>[];
    var clock = DateTime(2026, 3, 10, 2);
    DateTime tick() {
      clock = clock.add(const Duration(microseconds: 10));
      return clock;
    }

    final manager = WebNovelDownloadManager(
      database: () async => db,
      now: tick,
      delay: (_) async {},
      downloadChapter: (
        String webBookId,
        int chapterIndex, {
        required bool forceRefresh,
      }) async {
        downloaded.add(chapterIndex);
      },
    );

    await manager.enqueueBookCache(bookId, startIndex: 0, endIndex: 0);
    await manager.pumpOnce(); // expand
    await manager.pumpOnce(); // process chapter task
    expect(downloaded, isEmpty);

    await manager.enqueueBookCache(bookId, startIndex: 0, endIndex: 0, forceRefresh: true);
    await manager.pumpOnce(); // expand (merged into same task)
    await manager.pumpOnce(); // process chapter task
    expect(downloaded, [0]);
  });
}

