import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../logging/app_run_log_service.dart';

enum WebDownloadTaskType { book, chapter }

enum WebDownloadTaskStatus { queued, running, paused, failed, completed }

enum WebDownloadFailureType { http, parse, rateLimit, rule, unknown }

@immutable
class WebDownloadTask {
  const WebDownloadTask({
    required this.id,
    required this.type,
    required this.status,
    required this.webBookId,
    required this.parentTaskId,
    required this.startIndex,
    required this.endIndex,
    required this.chapterIndex,
    required this.forceRefresh,
    required this.priority,
    required this.attempt,
    required this.totalCount,
    required this.completedCount,
    required this.failedCount,
    required this.createdAt,
    required this.updatedAt,
    required this.nextRunAt,
    required this.lastErrorType,
    required this.lastErrorMessage,
  });

  final String id;
  final WebDownloadTaskType type;
  final WebDownloadTaskStatus status;
  final String webBookId;
  final String parentTaskId;
  final int? startIndex;
  final int? endIndex;
  final int? chapterIndex;
  final bool forceRefresh;
  final int priority;
  final int attempt;
  final int totalCount;
  final int completedCount;
  final int failedCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime nextRunAt;
  final WebDownloadFailureType? lastErrorType;
  final String lastErrorMessage;

  bool get isTerminal =>
      status == WebDownloadTaskStatus.completed ||
      status == WebDownloadTaskStatus.failed;
}

@immutable
class WebDownloadEnqueueResult {
  const WebDownloadEnqueueResult({
    required this.bookTaskId,
    required this.enqueuedChapters,
    required this.startIndex,
    required this.endIndex,
  });

  final String bookTaskId;
  final int enqueuedChapters;
  final int startIndex;
  final int endIndex;
}

typedef WebChapterDownloader =
    Future<void> Function(
      String webBookId,
      int chapterIndex, {
      required bool forceRefresh,
    });

class WebNovelDownloadManager {
  WebNovelDownloadManager({
    required Future<Database> Function() database,
    required WebChapterDownloader downloadChapter,
    DateTime Function()? now,
    Future<void> Function(Duration)? delay,
  }) : _database = database,
       _downloadChapter = downloadChapter,
       _now = now ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed;

  static const String tableTasks = 'web_download_tasks';
  static const String tableSettings = 'web_download_settings';

  static const String _settingPaused = 'download_paused';

  static const String _statusQueued = 'queued';
  static const String _statusRunning = 'running';
  static const String _statusPaused = 'paused';
  static const String _statusFailed = 'failed';
  static const String _statusCompleted = 'completed';

  static const String _typeBook = 'book';
  static const String _typeChapter = 'chapter';

  final Future<Database> Function() _database;
  final WebChapterDownloader _downloadChapter;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;

  final StreamController<int> _events = StreamController<int>.broadcast();
  int _eventCounter = 0;

  bool _started = false;
  bool _pumping = false;
  Timer? _timer;

  Stream<int> get events => _events.stream;

  Future<void> start({bool enableTimer = true}) async {
    if (_started) {
      return;
    }
    _started = true;
    await _recoverRunningTasks();
    if (enableTimer) {
      _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
        unawaited(pumpOnce());
      });
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _events.close();
  }

  void _notify() {
    if (_events.isClosed) {
      return;
    }
    _eventCounter += 1;
    _events.add(_eventCounter);
  }

  Future<int> _getIntSetting(String key, int fallback) async {
    final db = await _database();
    final rows = await db.query(
      tableSettings,
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) {
      return fallback;
    }
    return int.tryParse(rows.first['value']?.toString() ?? '') ?? fallback;
  }

  Future<void> setIntSetting(String key, int value) async {
    final db = await _database();
    await db.insert(
      tableSettings,
      {'key': key, 'value': value.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  Future<void> _recoverRunningTasks() async {
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    final paused = await _isPaused();
    await db.update(
      tableTasks,
      {
        'status': paused ? _statusPaused : _statusQueued,
        'updated_at': now,
      },
      where: 'status = ?',
      whereArgs: [_statusRunning],
    );
  }

  Future<bool> _isPaused() async {
    return (await _getIntSetting(_settingPaused, 0)) == 1;
  }

  Future<void> _setPaused(bool value) async {
    await setIntSetting(_settingPaused, value ? 1 : 0);
  }

  Future<WebDownloadEnqueueResult> enqueueBookCache(
    String webBookId, {
    int startIndex = 0,
    int? endIndex,
    bool forceRefresh = false,
    int priority = 0,
  }) async {
    final db = await _database();
    final now = _now();
    final paused = await _isPaused();

    final countRow =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(1) FROM web_chapters WHERE web_book_id = ?',
            [webBookId],
          ),
        ) ??
        0;
    if (countRow <= 0) {
      throw Exception('未同步到目录，无法创建缓存任务');
    }

    final safeStart = startIndex.clamp(0, countRow - 1);
    final safeEnd = (endIndex ?? (countRow - 1)).clamp(safeStart, countRow - 1);

    final active = await db.query(
      tableTasks,
      where: 'type = ? AND web_book_id = ? AND status IN (?, ?, ?)',
      whereArgs: [_typeBook, webBookId, _statusQueued, _statusRunning, _statusPaused],
      orderBy: 'created_at DESC',
      limit: 1,
    );

    if (active.isNotEmpty) {
      final task = _taskFromRow(active.first);
      final existingStart = task.startIndex ?? safeStart;
      final existingEnd = task.endIndex ?? safeEnd;
      final mergedStart = math.min(existingStart, safeStart);
      final mergedEnd = math.max(existingEnd, safeEnd);
      final mergedForceRefresh = task.forceRefresh || forceRefresh;
      final mergedPriority = math.max(task.priority, priority);
      final shouldQueue = !paused && task.status != WebDownloadTaskStatus.paused;

      await db.update(
        tableTasks,
        {
          'start_index': mergedStart,
          'end_index': mergedEnd,
          'force_refresh': mergedForceRefresh ? 1 : 0,
          'priority': mergedPriority,
          'updated_at': now.millisecondsSinceEpoch,
          if (shouldQueue) 'status': _statusQueued,
          if (shouldQueue) 'next_run_at': now.millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [task.id],
      );

      _notify();
      return WebDownloadEnqueueResult(
        bookTaskId: task.id,
        enqueuedChapters: mergedEnd - mergedStart + 1,
        startIndex: mergedStart,
        endIndex: mergedEnd,
      );
    }

    final taskId = '${webBookId}_${now.microsecondsSinceEpoch}_book';
    await db.insert(
      tableTasks,
      {
        'id': taskId,
        'type': _typeBook,
        'status': paused ? _statusPaused : _statusQueued,
        'web_book_id': webBookId,
        'parent_task_id': '',
        'start_index': safeStart,
        'end_index': safeEnd,
        'chapter_index': null,
        'force_refresh': forceRefresh ? 1 : 0,
        'priority': priority,
        'attempt': 0,
        'total_count': 0,
        'completed_count': 0,
        'failed_count': 0,
        'next_run_at': now.millisecondsSinceEpoch,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
        'last_error_type': '',
        'last_error_message': '',
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );

    _notify();
    return WebDownloadEnqueueResult(
      bookTaskId: taskId,
      enqueuedChapters: safeEnd - safeStart + 1,
      startIndex: safeStart,
      endIndex: safeEnd,
    );
  }

  Future<List<WebDownloadTask>> listTasks({
    String webBookId = '',
    bool includeCompleted = true,
    int limit = 200,
  }) async {
    final db = await _database();
    final where = <String>[];
    final args = <Object?>[];
    if (webBookId.trim().isNotEmpty) {
      where.add('web_book_id = ?');
      args.add(webBookId.trim());
    }
    if (!includeCompleted) {
      where.add('status != ?');
      args.add(_statusCompleted);
    }
    final rows = await db.query(
      tableTasks,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_taskFromRow).toList(growable: false);
  }

  Future<void> pauseAll() async {
    await _setPaused(true);
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    await db.update(
      tableTasks,
      {'status': _statusPaused, 'updated_at': now},
      where: 'status IN (?, ?)',
      whereArgs: [_statusQueued, _statusRunning],
    );
    _notify();
  }

  Future<void> resumeAll() async {
    await _setPaused(false);
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    await db.update(
      tableTasks,
      {'status': _statusQueued, 'updated_at': now, 'next_run_at': now},
      where: 'status = ?',
      whereArgs: [_statusPaused],
    );
    _notify();
  }

  Future<void> clearTerminalTasks() async {
    final db = await _database();
    await db.delete(
      tableTasks,
      where: 'status IN (?, ?)',
      whereArgs: [_statusCompleted, _statusFailed],
    );
    _notify();
  }

  Future<void> clearAllTasks() async {
    final db = await _database();
    await db.delete(tableTasks);
    _notify();
  }

  Future<void> pumpOnce() async {
    if (_pumping) {
      return;
    }
    if (await _isPaused()) {
      return;
    }
    _pumping = true;
    try {
      if (!await _pumpBookQueue()) {
        await _pumpChapterQueue();
      }
    } catch (error, stackTrace) {
      await AppRunLogService.instance.logError(
        'download pump failed: $error\n$stackTrace',
      );
    } finally {
      _pumping = false;
    }
  }

  Future<bool> _pumpBookQueue() async {
    final db = await _database();
    final now = _now();
    final rows = await db.query(
      tableTasks,
      where: 'type = ? AND status = ? AND next_run_at <= ?',
      whereArgs: [_typeBook, _statusQueued, now.millisecondsSinceEpoch],
      orderBy: 'priority DESC, created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return false;
    }
    final task = _taskFromRow(rows.first);
    await _markRunning(task.id);
    await _expandBookTask(task.id);
    return true;
  }

  Future<void> _pumpChapterQueue() async {
    final db = await _database();
    final now = _now();
    final maxConcurrent = await _getIntSetting('download_max_concurrent', 2);
    final rows = await db.query(
      tableTasks,
      where: 'type = ? AND status = ? AND next_run_at <= ?',
      whereArgs: [_typeChapter, _statusQueued, now.millisecondsSinceEpoch],
      orderBy: 'priority DESC, created_at ASC',
      limit: maxConcurrent.clamp(1, 8),
    );
    if (rows.isEmpty) {
      return;
    }

    final tasks = rows.map(_taskFromRow).toList(growable: false);
    await Future.wait(tasks.map(_processChapterTask));
  }

  Future<void> _markRunning(String taskId) async {
    final db = await _database();
    await db.update(
      tableTasks,
      {
        'status': _statusRunning,
        'updated_at': _now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
    _notify();
  }

  Future<void> _expandBookTask(String bookTaskId) async {
    final trimmed = bookTaskId.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final db = await _database();
    final now = _now();
    final rows = await db.query(
      tableTasks,
      where: 'id = ?',
      whereArgs: [trimmed],
      limit: 1,
    );
    if (rows.isEmpty) {
      return;
    }
    final task = _taskFromRow(rows.first);
    if (task.type != WebDownloadTaskType.book) {
      return;
    }

    final paused = await _isPaused();
    final targetStatus =
        paused || task.status == WebDownloadTaskStatus.paused
            ? _statusPaused
            : _statusQueued;

    final start = task.startIndex ?? 0;
    final end = task.endIndex ?? start;
    final forceRefresh = task.forceRefresh;

    final chapterCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(1) FROM web_chapters WHERE web_book_id = ?',
            [task.webBookId],
          ),
        ) ??
        0;
    if (chapterCount <= 0) {
      await _markFailed(
        task.id,
        WebDownloadFailureType.rule,
        '未同步到目录，无法展开章节任务',
      );
      return;
    }

    final safeStart = start.clamp(0, chapterCount - 1);
    final safeEnd = end.clamp(safeStart, chapterCount - 1);

    final batch = db.batch();
    for (var index = safeStart; index <= safeEnd; index++) {
      final chapterTaskId = '${task.id}_$index';
      batch.insert(
        tableTasks,
        {
          'id': chapterTaskId,
          'type': _typeChapter,
          'status': targetStatus,
          'web_book_id': task.webBookId,
          'parent_task_id': task.id,
          'start_index': null,
          'end_index': null,
          'chapter_index': index,
          'force_refresh': forceRefresh ? 1 : 0,
          'priority': task.priority,
          'attempt': 0,
          'total_count': 1,
          'completed_count': 0,
          'failed_count': 0,
          'next_run_at': now.millisecondsSinceEpoch,
          'created_at': now.millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
          'last_error_type': '',
          'last_error_message': '',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);

    final childCount =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(1) FROM $tableTasks WHERE parent_task_id = ?',
            [task.id],
          ),
        ) ??
        0;
    if (childCount <= 0) {
      await _markFailed(task.id, WebDownloadFailureType.unknown, '未创建任何章节任务');
      return;
    }

    await db.update(
      tableTasks,
      {
        'status': targetStatus,
        'updated_at': now.millisecondsSinceEpoch,
        if (targetStatus == _statusQueued) 'next_run_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [task.id],
    );

    await _updateParentProgress(task.id);
    _notify();
  }

  Future<void> _processChapterTask(WebDownloadTask task) async {
    final db = await _database();
    final now = _now();
    final chapterIndex = task.chapterIndex ?? -1;
    if (chapterIndex < 0) {
      await _markFailed(task.id, WebDownloadFailureType.rule, '缺少章节索引');
      return;
    }

    await db.update(
      tableTasks,
      {
        'status': _statusRunning,
        'updated_at': now.millisecondsSinceEpoch,
      },
      where: 'id = ? AND status = ?',
      whereArgs: [task.id, _statusQueued],
    );

    try {
      final chapterIdRows = await db.query(
        'web_chapters',
        columns: ['id'],
        where: 'web_book_id = ? AND chapter_index = ?',
        whereArgs: [task.webBookId, chapterIndex],
        limit: 1,
      );
      if (chapterIdRows.isEmpty) {
        throw Exception('未找到章节记录（index=$chapterIndex）');
      }
      final chapterId = chapterIdRows.first['id'] as String? ?? '';
      if (chapterId.isEmpty) {
        throw Exception('未找到章节记录（index=$chapterIndex）');
      }

      if (!task.forceRefresh) {
        final cachedRows = await db.query(
          'web_chapter_cache',
          columns: ['chapter_id', 'text', 'is_complete'],
          where: 'chapter_id = ?',
          whereArgs: [chapterId],
          limit: 1,
        );
        if (cachedRows.isNotEmpty) {
          final text = cachedRows.first['text'] as String? ?? '';
          final isComplete = (cachedRows.first['is_complete'] as int? ?? 1) == 1;
          if (isComplete && text.trim().isNotEmpty) {
            await _markChapterTaskCompleted(task.id, skipped: true);
            await _updateParentProgress(task.parentTaskId);
            return;
          }
        }
      }

      await _downloadChapter(
        task.webBookId,
        chapterIndex,
        forceRefresh: task.forceRefresh,
      );
      await _markChapterTaskCompleted(task.id);
      await _updateParentProgress(task.parentTaskId);
    } catch (error, stackTrace) {
      final classified = _classifyFailure(error);
      await AppRunLogService.instance.logError(
        'download chapter failed: ${task.webBookId}#$chapterIndex; $error\n$stackTrace',
      );
      await _handleChapterFailure(task, classified.$1, classified.$2);
      await _updateParentProgress(task.parentTaskId);
    } finally {
      _notify();
    }
  }

  (WebDownloadFailureType, String) _classifyFailure(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('http') || lower.contains('socket') || lower.contains('timeout')) {
      if (lower.contains('429') || lower.contains('too many') || lower.contains('rate')) {
        return (WebDownloadFailureType.rateLimit, message);
      }
      return (WebDownloadFailureType.http, message);
    }
    if (message.contains('解析') || lower.contains('parse')) {
      return (WebDownloadFailureType.parse, message);
    }
    if (message.contains('规则')) {
      return (WebDownloadFailureType.rule, message);
    }
    return (WebDownloadFailureType.unknown, message);
  }

  Future<void> _handleChapterFailure(
    WebDownloadTask task,
    WebDownloadFailureType type,
    String message,
  ) async {
    final db = await _database();
    final now = _now();
    final paused = await _isPaused();

    final nextAttempt = task.attempt + 1;
    final retryable =
        type == WebDownloadFailureType.http ||
        type == WebDownloadFailureType.rateLimit ||
        type == WebDownloadFailureType.unknown;
    final maxAttempts = 3;

    if (retryable && nextAttempt < maxAttempts) {
      final delaySeconds = switch (nextAttempt) {
        1 => type == WebDownloadFailureType.rateLimit ? 20 : 6,
        2 => type == WebDownloadFailureType.rateLimit ? 45 : 18,
        _ => 60,
      };
      await db.update(
        tableTasks,
        {
          'status': paused ? _statusPaused : _statusQueued,
          'attempt': nextAttempt,
          'next_run_at':
              now.add(Duration(seconds: delaySeconds)).millisecondsSinceEpoch,
          'updated_at': now.millisecondsSinceEpoch,
          'last_error_type': type.name,
          'last_error_message': message,
        },
        where: 'id = ?',
        whereArgs: [task.id],
      );
      await _delay(const Duration(milliseconds: 10));
      return;
    }

    await db.update(
      tableTasks,
      {
        'status': _statusFailed,
        'attempt': nextAttempt,
        'failed_count': 1,
        'updated_at': now.millisecondsSinceEpoch,
        'next_run_at': now.millisecondsSinceEpoch,
        'last_error_type': type.name,
        'last_error_message': message,
      },
      where: 'id = ?',
      whereArgs: [task.id],
    );
  }

  Future<void> _markChapterTaskCompleted(
    String taskId, {
    bool skipped = false,
  }) async {
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    await db.update(
      tableTasks,
      {
        'status': _statusCompleted,
        'completed_count': 1,
        'failed_count': 0,
        'updated_at': now,
        'last_error_type': '',
        'last_error_message': skipped ? '已缓存，跳过' : '',
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
  }

  Future<void> _markFailed(
    String taskId,
    WebDownloadFailureType type,
    String message,
  ) async {
    final db = await _database();
    final now = _now().millisecondsSinceEpoch;
    await db.update(
      tableTasks,
      {
        'status': _statusFailed,
        'failed_count': 1,
        'updated_at': now,
        'next_run_at': now,
        'last_error_type': type.name,
        'last_error_message': message,
      },
      where: 'id = ?',
      whereArgs: [taskId],
    );
    _notify();
  }

  Future<void> _updateParentProgress(String parentTaskId) async {
    final trimmed = parentTaskId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final db = await _database();

    final parentRows = await db.query(
      tableTasks,
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [trimmed],
      limit: 1,
    );
    final parentPaused =
        parentRows.isNotEmpty &&
        (parentRows.first['status'] as String? ?? '') == _statusPaused;
    final paused = parentPaused || await _isPaused();

    final counts = await db.rawQuery(
      '''
      SELECT
        SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) AS completed,
        SUM(CASE WHEN status = ? THEN 1 ELSE 0 END) AS failed,
        COUNT(1) AS total
      FROM $tableTasks
      WHERE parent_task_id = ?
      ''',
      [_statusCompleted, _statusFailed, trimmed],
    );
    final row = counts.isEmpty ? const <String, Object?>{} : counts.first;
    final completed = (row['completed'] as int? ?? 0);
    final failed = (row['failed'] as int? ?? 0);
    final total = (row['total'] as int? ?? 0);

    final now = _now().millisecondsSinceEpoch;
    final status = total > 0 && completed + failed >= total
        ? (failed > 0 ? _statusFailed : _statusCompleted)
        : (paused ? _statusPaused : _statusRunning);

    await db.update(
      tableTasks,
      {
        'status': status,
        'total_count': total,
        'completed_count': completed,
        'failed_count': failed,
        'updated_at': now,
        if (!paused) 'next_run_at': now,
      },
      where: 'id = ?',
      whereArgs: [trimmed],
    );
  }

  WebDownloadTask _taskFromRow(Map<String, Object?> row) {
    WebDownloadTaskType parseType(String raw) =>
        raw == _typeBook ? WebDownloadTaskType.book : WebDownloadTaskType.chapter;

    WebDownloadTaskStatus parseStatus(String raw) {
      return switch (raw) {
        _statusQueued => WebDownloadTaskStatus.queued,
        _statusRunning => WebDownloadTaskStatus.running,
        _statusPaused => WebDownloadTaskStatus.paused,
        _statusFailed => WebDownloadTaskStatus.failed,
        _statusCompleted => WebDownloadTaskStatus.completed,
        _ => WebDownloadTaskStatus.queued,
      };
    }

    WebDownloadFailureType? parseFailure(String raw) {
      if (raw.trim().isEmpty) {
        return null;
      }
      for (final value in WebDownloadFailureType.values) {
        if (value.name == raw) {
          return value;
        }
      }
      return WebDownloadFailureType.unknown;
    }

    final createdAtMs = row['created_at'] as int? ?? 0;
    final updatedAtMs = row['updated_at'] as int? ?? createdAtMs;
    final nextRunMs = row['next_run_at'] as int? ?? createdAtMs;
    return WebDownloadTask(
      id: row['id'] as String? ?? '',
      type: parseType(row['type'] as String? ?? _typeChapter),
      status: parseStatus(row['status'] as String? ?? _statusQueued),
      webBookId: row['web_book_id'] as String? ?? '',
      parentTaskId: row['parent_task_id'] as String? ?? '',
      startIndex: row['start_index'] as int?,
      endIndex: row['end_index'] as int?,
      chapterIndex: row['chapter_index'] as int?,
      forceRefresh: (row['force_refresh'] as int? ?? 0) == 1,
      priority: row['priority'] as int? ?? 0,
      attempt: row['attempt'] as int? ?? 0,
      totalCount: row['total_count'] as int? ?? 0,
      completedCount: row['completed_count'] as int? ?? 0,
      failedCount: row['failed_count'] as int? ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      nextRunAt: DateTime.fromMillisecondsSinceEpoch(nextRunMs),
      lastErrorType: parseFailure(row['last_error_type'] as String? ?? ''),
      lastErrorMessage: row['last_error_message'] as String? ?? '',
    );
  }
}
