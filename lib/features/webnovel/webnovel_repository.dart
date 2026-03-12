import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:charset/charset.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../app/runtime_platform.dart';
import '../../core/async/app_timeouts.dart';
import '../../core/database/app_database_factory.dart';
import '../library/data/book_model.dart';
import '../library/data/library_service.dart';
import '../logging/app_run_log_service.dart';
import '../translation/translation_config.dart';
import '../translation/translation_service.dart';
import 'defaults.dart';
import 'models.dart';
import 'webnovel_download_manager.dart';

class SourceImportReport {
  const SourceImportReport({
    required this.importedSources,
    required this.totalEntries,
    required this.importedCount,
    required this.updatedCount,
    required this.legacyMappedCount,
    required this.skippedCount,
    required this.warnings,
    required this.entries,
  });

  final List<WebNovelSource> importedSources;
  final int totalEntries;
  final int importedCount;
  final int updatedCount;
  final int legacyMappedCount;
  final int skippedCount;
  final List<String> warnings;
  final List<SourceImportEntryReport> entries;
}

enum SourceImportEntryStatus { imported, updated, skipped, failed }

class SourceImportEntryReport {
  const SourceImportEntryReport({
    required this.index,
    required this.status,
    this.sourceId = '',
    this.sourceName = '',
    this.legacyMapped = false,
    this.message = '',
    this.warnings = const <String>[],
  });

  final int index;
  final SourceImportEntryStatus status;
  final String sourceId;
  final String sourceName;
  final bool legacyMapped;
  final String message;
  final List<String> warnings;
}

class _ImportedSourceParseResult {
  const _ImportedSourceParseResult({
    required this.source,
    this.legacyMapped = false,
    this.warnings = const <String>[],
  });

  final WebNovelSource source;
  final bool legacyMapped;
  final List<String> warnings;
}

class _LegadoRequestDescriptor {
  const _LegadoRequestDescriptor({
    required this.pathTemplate,
    required this.method,
    required this.queryField,
    this.charset = '',
    this.headers = const <String, String>{},
    this.fetchViaBrowserOnly = false,
  });

  final String pathTemplate;
  final HttpMethod method;
  final String queryField;
  final String charset;
  final Map<String, String> headers;
  final bool fetchViaBrowserOnly;
}

class _LegadoListSelectorResult {
  const _LegadoListSelectorResult({
    required this.selector,
    this.reverse = false,
  });

  final String selector;
  final bool reverse;
}

class _ChapterSyncTask {
  const _ChapterSyncTask({
    required this.webBookId,
    required this.status,
    required this.attempt,
    required this.nextRetryAt,
    required this.lastError,
    required this.updatedAt,
  });

  final String webBookId;
  final String status;
  final int attempt;
  final DateTime nextRetryAt;
  final String lastError;
  final DateTime updatedAt;
}

class _BookSourceCandidate {
  const _BookSourceCandidate({required this.source, required this.detailUrl});

  final WebNovelSource source;
  final String detailUrl;
}

class _BookDetailCandidate {
  const _BookDetailCandidate({required this.source, required this.detailUrl});

  final WebNovelSource source;
  final String detailUrl;
}

class _ResolvedBookDetail {
  const _ResolvedBookDetail({required this.source, required this.detail});

  final WebNovelSource source;
  final _BookDetail detail;
}

abstract class WebNovelRepositoryHandle {
  Future<void> prewarm();
  Future<List<WebNovelSource>> listSources();
  Future<List<WebSearchProvider>> listSearchProviders();
  Future<List<WebSession>> listSessions();
  Future<List<ReaderModeArticle>> listReaderHistory();
  Future<void> clearReaderHistory();
  Future<void> clearReaderHistoryEntry(String url);
  Future<List<WebNovelSearchResult>> searchBooks(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  });
  Future<WebNovelSearchReport> searchBooksWithReport(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  });
  Stream<WebNovelSearchUpdate> searchBooksStream(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  });
  Future<List<WebSearchHit>> webSearch(String query, {String? providerId});
  Future<ReaderModeDetectionResult> detectReaderMode(String url);
  Future<ReaderModeDetectionResult> detectReaderModeFromHtml({
    required String html,
    required String url,
  });
  Future<WebNovelBookMeta> addBookFromSearchResult(WebNovelSearchResult result);
  Future<WebNovelSearchResult> resolveSearchResultDetail(
    WebNovelSearchResult result,
  );
  Future<WebNovelBookMeta> addBookFromUrl(String url);
  Future<WebNovelBookMeta?> findBookMetaByUrl(String url);
  Future<List<WebChapterRecord>> getChapters(
    String webBookId, {
    bool refresh = false,
  });
  Future<List<WebSourceVersion>> listSourceVersions(String sourceId);
  Future<void> rollbackSourceVersion(String versionId);
  Future<AiSourcePatchSuggestion> repairSourceWithAi({
    required WebNovelSource source,
    required String sampleUrl,
    String sampleQuery = '',
    required TranslationConfig? config,
    AiSourceRepairMode mode = AiSourceRepairMode.suggest,
  });
  Future<int> cacheBookChapters(
    String webBookId, {
    int startIndex = 0,
    int? endIndex,
    bool forceRefresh = false,
    bool background = true,
  });
  Stream<int> watchDownloadTasks();
  Future<List<WebDownloadTask>> listDownloadTasks({
    String webBookId = '',
    bool includeCompleted = true,
    int limit = 200,
  });
  Future<void> pauseAllDownloads();
  Future<void> resumeAllDownloads();
  Future<void> clearTerminalDownloadTasks();
  Future<void> clearAllDownloadTasks();
  Future<int> clearCachedChapters({String webBookId = ''});
  Future<Map<String, int>> getChapterCacheStats();
  Future<int> getDownloadSettingInt(String key, int fallback);
  Future<void> setDownloadSettingInt(String key, int value);
  Future<SourceImportReport> importSourcesJsonWithReport(String jsonText);
  Future<SourceImportReport> importSourcesInputWithReport(String input);
  Future<String> exportSourcesJson();
  Future<void> saveManualCookies({
    required String sourceId,
    required String domain,
    required String cookieHeader,
    String userAgent = '',
  });
  Future<void> saveCookieMaps({
    required String sourceId,
    required String domain,
    required List<Map<String, dynamic>> cookies,
    String userAgent = '',
  });
  Future<void> clearSession(String sessionId);
  Future<void> setSourceEnabled(String sourceId, bool enabled);
  Future<int> removeCustomSources(Iterable<String> sourceIds);
  Future<SourceTestResult> testSource(WebNovelSource source);
}

class WebNovelRepository implements WebNovelRepositoryHandle {
  static const String _bundledSourcePackAsset =
      'assets/webnovel/bundled_sources.json';
  static const int _allSourcesDirectSearchBudget = 36;
  static const int _mobileDirectSearchBudget = 16;
  static const Duration _desktopSearchTimeout = Duration(seconds: 10);
  static const Duration _mobileSearchTimeout = Duration(seconds: 8);
  static const int _chapterSyncMaxAttempts = 3;
  static const String _chapterSyncTaskPending = 'pending';
  static const String _chapterSyncTaskRunning = 'running';
  static const String _chapterSyncTaskRetrying = 'retrying';
  static const String _chapterSyncTaskFailed = 'failed';
  static const String _readerModeSourceId = 'reader_mode';

  factory WebNovelRepository() => _instance;

  WebNovelRepository._internal({
    http.Client? client,
    Future<String> Function(String fileName)? databasePathProvider,
    Future<String?> Function()? bundledSourcePackLoader,
    Future<void> Function(Duration)? retryDelay,
    DateTime Function()? now,
    bool autoSyncOnAdd = true,
  }) : _client = client ?? http.Client(),
       _databasePathProvider = databasePathProvider,
       _bundledSourcePackLoader =
           bundledSourcePackLoader ?? _defaultBundledSourcePackLoader,
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _now = now ?? DateTime.now,
       _autoSyncOnAdd = autoSyncOnAdd;

  factory WebNovelRepository.test({
    http.Client? client,
    Future<String> Function(String fileName)? databasePathProvider,
    Future<void> Function(Duration)? retryDelay,
    DateTime Function()? now,
    bool autoSyncOnAdd = true,
  }) => WebNovelRepository._internal(
    client: client,
    databasePathProvider: databasePathProvider,
    bundledSourcePackLoader: () async => null,
    retryDelay: retryDelay,
    now: now,
    autoSyncOnAdd: autoSyncOnAdd,
  );

  static final WebNovelRepository _instance = WebNovelRepository._internal();
  static final Uuid _uuid = Uuid();

  final LibraryService _libraryService = LibraryService();
  final TranslationService _translationService = TranslationService();
  final http.Client _client;
  final Future<String> Function(String fileName)? _databasePathProvider;
  final Future<String?> Function() _bundledSourcePackLoader;
  final Future<void> Function(Duration) _retryDelay;
  final DateTime Function() _now;
  final bool _autoSyncOnAdd;
  Database? _db;
  Future<void>? _prewarmFuture;
  Future<void>? _legacyMigrationFuture;
  WebNovelDownloadManager? _downloadManager;
  DateTime? _lastCachePolicyEnforcedAt;
  final Set<String> _chapterSyncInFlight = <String>{};
  List<WebNovelSource>? _cachedSources;
  Map<String, List<WebNovelSource>>? _cachedSourcesByDomain;
  List<WebSearchProvider>? _cachedProviders;

  Future<Database> get database async {
    _db ??= await _openDatabase();
    return _db!;
  }

  Future<void> ensureInitialized() async {
    final db = await database;
    await _seedBuiltins(db);
    await _seedBundledSourcePackIfNeeded(db);
  }

  static Future<String?> _defaultBundledSourcePackLoader() async {
    try {
      return await rootBundle.loadString(_bundledSourcePackAsset);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> prewarm() {
    final inFlight = _prewarmFuture;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _doPrewarm();
    _prewarmFuture = future;
    future.whenComplete(() {
      if (identical(_prewarmFuture, future)) {
        _prewarmFuture = null;
      }
    });
    return future;
  }

  Future<void> _doPrewarm() async {
    await ensureInitialized();
    _scheduleLegacyMigration();
    _resumePendingChapterSyncTasks();
    await _ensureDownloadManagerStarted();
  }

  Future<WebNovelDownloadManager> _ensureDownloadManagerStarted() async {
    final existing = _downloadManager;
    if (existing != null) {
      await existing.start();
      return existing;
    }
    final manager = WebNovelDownloadManager(
      database: () async => database,
      downloadChapter: (
        String webBookId,
        int chapterIndex, {
        required bool forceRefresh,
      }) async {
        await getChapterContent(webBookId, chapterIndex, refresh: forceRefresh);
        await _enforceCachePolicies();
      },
    );
    _downloadManager = manager;
    await manager.start();
    return manager;
  }

  void _scheduleLegacyMigration() {
    final inFlight = _legacyMigrationFuture;
    if (inFlight != null) {
      return;
    }

    Future<void>? currentRef;
    Future<void> future() async {
      try {
        await migrateLegacyRecords();
      } catch (error, stackTrace) {
        await AppRunLogService.instance.logError(
          'webnovel legacy migration failed: $error\n$stackTrace',
        );
      } finally {
        if (identical(_legacyMigrationFuture, currentRef)) {
          _legacyMigrationFuture = null;
        }
      }
    }

    currentRef = future();
    _legacyMigrationFuture = currentRef;
  }

  Future<Database> _openDatabase() async {
    final path = await (_databasePathProvider ?? getAppDatabasePath)(
      'webnovel.db',
    );
    return appDatabaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE web_sources (
              id TEXT PRIMARY KEY,
              payload TEXT NOT NULL,
              builtin INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE web_books (
              id TEXT PRIMARY KEY,
              library_book_id TEXT NOT NULL,
              source_id TEXT NOT NULL,
              title TEXT NOT NULL,
              author TEXT NOT NULL,
              detail_url TEXT NOT NULL,
              origin_url TEXT NOT NULL,
              cover_url TEXT NOT NULL DEFAULT '',
              description TEXT NOT NULL DEFAULT '',
              last_chapter_title TEXT NOT NULL DEFAULT '',
              updated_at INTEGER,
              source_snapshot TEXT NOT NULL DEFAULT '',
              chapter_sync_status TEXT NOT NULL DEFAULT 'pending',
              chapter_sync_error TEXT NOT NULL DEFAULT '',
              chapter_sync_retry_count INTEGER NOT NULL DEFAULT 0,
              chapter_sync_updated_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE web_book_sources (
              id TEXT PRIMARY KEY,
              web_book_id TEXT NOT NULL,
              source_id TEXT NOT NULL,
              detail_url TEXT NOT NULL,
              title TEXT NOT NULL DEFAULT '',
              author TEXT NOT NULL DEFAULT '',
              cover_url TEXT NOT NULL DEFAULT '',
              UNIQUE(web_book_id, source_id)
            )
          ''');
          await db.execute('''
            CREATE TABLE web_chapters (
              id TEXT PRIMARY KEY,
              web_book_id TEXT NOT NULL,
              source_id TEXT NOT NULL,
              title TEXT NOT NULL,
              url TEXT NOT NULL,
              chapter_index INTEGER NOT NULL,
              updated_at INTEGER
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_web_chapters_book ON web_chapters(web_book_id, chapter_index)',
          );
          await db.execute('''
            CREATE TABLE web_chapter_sync_tasks (
              web_book_id TEXT PRIMARY KEY,
              status TEXT NOT NULL DEFAULT 'pending',
              attempt INTEGER NOT NULL DEFAULT 0,
              next_retry_at INTEGER NOT NULL DEFAULT 0,
              last_error TEXT NOT NULL DEFAULT '',
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_web_chapter_sync_tasks_due ON web_chapter_sync_tasks(status, next_retry_at)',
          );
          await db.execute('''
            CREATE TABLE web_chapter_cache (
              chapter_id TEXT PRIMARY KEY,
              source_id TEXT NOT NULL,
              title TEXT NOT NULL,
              text TEXT NOT NULL,
              html TEXT NOT NULL,
              fetched_at INTEGER NOT NULL,
              is_complete INTEGER NOT NULL DEFAULT 1,
              last_accessed_at INTEGER NOT NULL DEFAULT 0,
              size_bytes INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE web_download_tasks (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              status TEXT NOT NULL,
              web_book_id TEXT NOT NULL,
              parent_task_id TEXT NOT NULL DEFAULT '',
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
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              last_error_type TEXT NOT NULL DEFAULT '',
              last_error_message TEXT NOT NULL DEFAULT ''
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_web_download_tasks_due ON web_download_tasks(type, status, next_run_at, priority, created_at)',
          );
          await db.execute('''
            CREATE TABLE web_download_settings (
              key TEXT PRIMARY KEY,
              value TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE web_sessions (
              id TEXT PRIMARY KEY,
              source_id TEXT NOT NULL,
              domain TEXT NOT NULL,
              cookies_json TEXT NOT NULL,
              user_agent TEXT NOT NULL DEFAULT '',
              updated_at INTEGER NOT NULL,
              last_verified_at INTEGER
            )
          ''');
          await db.execute('''
            CREATE TABLE web_search_providers (
              id TEXT PRIMARY KEY,
              payload TEXT NOT NULL,
              builtin INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE web_reader_history (
              url TEXT PRIMARY KEY,
              payload TEXT NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE web_source_versions (
              id TEXT PRIMARY KEY,
              source_id TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              created_by TEXT NOT NULL,
              note TEXT NOT NULL DEFAULT ''
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_web_source_versions_source ON web_source_versions(source_id, created_at)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute(
              "ALTER TABLE web_books ADD COLUMN chapter_sync_status TEXT NOT NULL DEFAULT 'pending'",
            );
            await db.execute(
              "ALTER TABLE web_books ADD COLUMN chapter_sync_error TEXT NOT NULL DEFAULT ''",
            );
            await db.execute(
              'ALTER TABLE web_books ADD COLUMN chapter_sync_retry_count INTEGER NOT NULL DEFAULT 0',
            );
            await db.execute(
              'ALTER TABLE web_books ADD COLUMN chapter_sync_updated_at INTEGER',
            );
            await db.execute('''
              CREATE TABLE IF NOT EXISTS web_chapter_sync_tasks (
                web_book_id TEXT PRIMARY KEY,
                status TEXT NOT NULL DEFAULT 'pending',
                attempt INTEGER NOT NULL DEFAULT 0,
                next_retry_at INTEGER NOT NULL DEFAULT 0,
                last_error TEXT NOT NULL DEFAULT '',
                updated_at INTEGER NOT NULL
              )
            ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_web_chapter_sync_tasks_due ON web_chapter_sync_tasks(status, next_retry_at)',
            );
          }
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS web_download_tasks (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                status TEXT NOT NULL,
                web_book_id TEXT NOT NULL,
                parent_task_id TEXT NOT NULL DEFAULT '',
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
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                last_error_type TEXT NOT NULL DEFAULT '',
                last_error_message TEXT NOT NULL DEFAULT ''
              )
            ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_web_download_tasks_due ON web_download_tasks(type, status, next_run_at, priority, created_at)',
            );
            await db.execute('''
              CREATE TABLE IF NOT EXISTS web_download_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
              )
            ''');
            try {
              await db.execute(
                'ALTER TABLE web_chapter_cache ADD COLUMN last_accessed_at INTEGER NOT NULL DEFAULT 0',
              );
            } catch (_) {}
            try {
              await db.execute(
                'ALTER TABLE web_chapter_cache ADD COLUMN size_bytes INTEGER NOT NULL DEFAULT 0',
              );
            } catch (_) {}
          }
          if (oldVersion < 4) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS web_source_versions (
                id TEXT PRIMARY KEY,
                source_id TEXT NOT NULL,
                payload TEXT NOT NULL,
                created_at INTEGER NOT NULL,
                created_by TEXT NOT NULL,
                note TEXT NOT NULL DEFAULT ''
              )
            ''');
            await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_web_source_versions_source ON web_source_versions(source_id, created_at)',
            );
          }
        },
      ),
    );
  }

  Future<void> _seedBuiltins(Database db) async {
    for (final source in builtinBookSources) {
      await db.insert('web_sources', {
        'id': source.id,
        'payload': jsonEncode(source.toJson()),
        'builtin': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    for (final provider in builtinSearchProviders) {
      await db.insert('web_search_providers', {
        'id': provider.id,
        'payload': jsonEncode(provider.toJson()),
        'builtin': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> _seedBundledSourcePackIfNeeded(Database db) async {
    final customCount = await _currentCustomSourceCount(db);
    if (customCount > 0) {
      return;
    }

    final payload = await _bundledSourcePackLoader();
    if (payload == null || payload.trim().isEmpty) {
      return;
    }

    try {
      final report = await importSourcesInputWithReport(payload);
      await AppRunLogService.instance.logInfo(
        'bundled source pack imported: total=${report.totalEntries}; '
        'imported=${report.importedCount}; skipped=${report.skippedCount}; '
        'warnings=${report.warnings.length}',
      );
    } catch (error, stackTrace) {
      await AppRunLogService.instance.logError(
        'bundled source pack import failed: $error\n$stackTrace',
      );
    }
  }

  Future<int> _currentCustomSourceCount(Database db) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM web_sources WHERE builtin = 0',
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  void _invalidateSourceCache() {
    _cachedSources = null;
    _cachedSourcesByDomain = null;
  }

  void _invalidateProviderCache() {
    _cachedProviders = null;
  }

  Map<String, List<WebNovelSource>> _buildSourcesByDomainIndex(
    List<WebNovelSource> sources,
  ) {
    final index = <String, List<WebNovelSource>>{};
    for (final source in sources) {
      final domains = source.siteDomains.isEmpty
          ? _deriveSiteDomains(source.baseUrl)
          : source.siteDomains;
      for (final domain in domains) {
        final normalized = domain.toLowerCase().replaceFirst('www.', '');
        if (normalized.isEmpty) {
          continue;
        }
        index.putIfAbsent(normalized, () => <WebNovelSource>[]).add(source);
      }
    }
    return index;
  }

  List<WebNovelSource> _sourcesForHost(String host) {
    final index = _cachedSourcesByDomain;
    if (index == null || host.trim().isEmpty) {
      return const <WebNovelSource>[];
    }
    final normalized = host.toLowerCase().replaceFirst('www.', '');
    final matches = <WebNovelSource>[];
    final seen = <String>{};
    final segments = normalized.split('.');
    for (var offset = 0; offset < segments.length; offset++) {
      final candidate = segments.sublist(offset).join('.');
      for (final source in index[candidate] ?? const <WebNovelSource>[]) {
        if (seen.add(source.id)) {
          matches.add(source);
        }
      }
    }
    return matches;
  }

  @override
  Future<List<WebNovelSource>> listSources() async {
    final cached = _cachedSources;
    if (cached != null) {
      return List<WebNovelSource>.from(cached);
    }
    final db = await database;
    final rows = await db.query('web_sources');
    final items = rows
        .map(
          (row) => WebNovelSource.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
    items.sort((a, b) => b.priority.compareTo(a.priority));
    _cachedSources = List<WebNovelSource>.unmodifiable(items);
    _cachedSourcesByDomain = _buildSourcesByDomainIndex(items);
    return List<WebNovelSource>.from(items);
  }

  Future<WebNovelSource?> getSourceById(String sourceId) async {
    final db = await database;
    final rows = await db.query(
      'web_sources',
      where: 'id = ?',
      whereArgs: [sourceId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return WebNovelSource.fromJson(
      jsonDecode(rows.first['payload'] as String) as Map<String, dynamic>,
    );
  }

  Future<void> saveSource(WebNovelSource source) async {
    final db = await database;
    await db.insert('web_sources', {
      'id': source.id,
      'payload': jsonEncode(source.toJson()),
      'builtin': source.builtin ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _invalidateSourceCache();
  }

  Future<void> _saveSourceVersion(
    WebNovelSource source, {
    required String createdBy,
    String note = '',
  }) async {
    final db = await database;
    await db.insert('web_source_versions', {
      'id': _uuid.v4(),
      'source_id': source.id,
      'payload': jsonEncode(source.toJson()),
      'created_at': _now().millisecondsSinceEpoch,
      'created_by': createdBy,
      'note': note,
    });
  }

  @override
  Future<List<WebSourceVersion>> listSourceVersions(String sourceId) async {
    final db = await database;
    final rows = await db.query(
      'web_source_versions',
      where: 'source_id = ?',
      whereArgs: [sourceId],
      orderBy: 'created_at DESC',
      limit: 50,
    );
    return rows
        .map(
          (row) => WebSourceVersion(
            id: row['id'] as String,
            sourceId: row['source_id'] as String,
            payload: row['payload'] as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
            createdBy: row['created_by'] as String? ?? '',
            note: row['note'] as String? ?? '',
          ),
        )
        .toList();
  }

  @override
  Future<void> rollbackSourceVersion(String versionId) async {
    final db = await database;
    final rows = await db.query(
      'web_source_versions',
      where: 'id = ?',
      whereArgs: [versionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('未找到对应的版本记录');
    }
    final row = rows.first;
    final sourceId = row['source_id'] as String;
    final payload = row['payload'] as String;
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    final restored = WebNovelSource.fromJson(decoded);
    final current = await getSourceById(sourceId);
    if (current != null) {
      await _saveSourceVersion(
        current,
        createdBy: 'rollback',
        note: 'rollback_before:$versionId',
      );
    }
    final applied = restored.copyWith(
      id: sourceId,
      enabled: current?.enabled ?? restored.enabled,
      builtin: current?.builtin ?? restored.builtin,
    );
    await saveSource(applied);
  }

  @override
  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    final source = await getSourceById(sourceId);
    if (source == null) {
      return;
    }
    await saveSource(source.copyWith(enabled: enabled));
  }

  Future<void> removeCustomSource(String sourceId) async {
    final source = await getSourceById(sourceId);
    if (source == null || source.builtin) {
      return;
    }
    final db = await database;
    await db.delete('web_sources', where: 'id = ?', whereArgs: [sourceId]);
    _invalidateSourceCache();
  }

  @override
  Future<int> removeCustomSources(Iterable<String> sourceIds) async {
    final ids = sourceIds
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet();
    if (ids.isEmpty) {
      return 0;
    }

    final sources = await listSources();
    final removable = sources
        .where((source) => !source.builtin && ids.contains(source.id))
        .map((source) => source.id)
        .toList(growable: false);
    if (removable.isEmpty) {
      return 0;
    }

    final db = await database;
    final placeholders = List.filled(removable.length, '?').join(', ');
    final deleted = await db.delete(
      'web_sources',
      where: 'id IN ($placeholders)',
      whereArgs: removable,
    );
    _invalidateSourceCache();
    return deleted;
  }

  @override
  Future<List<WebSearchProvider>> listSearchProviders() async {
    final cached = _cachedProviders;
    if (cached != null) {
      return List<WebSearchProvider>.from(cached);
    }
    final db = await database;
    final rows = await db.query('web_search_providers');
    final items = rows
        .map(
          (row) => WebSearchProvider.fromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
    items.sort((a, b) => b.priority.compareTo(a.priority));
    _cachedProviders = List<WebSearchProvider>.unmodifiable(items);
    return List<WebSearchProvider>.from(items);
  }

  Future<void> saveSearchProvider(WebSearchProvider provider) async {
    final db = await database;
    await db.insert('web_search_providers', {
      'id': provider.id,
      'payload': jsonEncode(provider.toJson()),
      'builtin': provider.builtin ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _invalidateProviderCache();
  }

  Future<void> removeCustomSearchProvider(String providerId) async {
    final db = await database;
    final rows = await db.query(
      'web_search_providers',
      where: 'id = ?',
      whereArgs: [providerId],
      limit: 1,
    );
    if (rows.isEmpty || (rows.first['builtin'] as int? ?? 0) == 1) {
      return;
    }
    await db.delete(
      'web_search_providers',
      where: 'id = ?',
      whereArgs: [providerId],
    );
    _invalidateProviderCache();
  }

  @override
  Future<List<WebSession>> listSessions() async {
    final db = await database;
    final rows = await db.query('web_sessions', orderBy: 'updated_at DESC');
    return rows.map(_sessionFromRow).toList();
  }

  Future<WebSession?> getSessionForSource(String sourceId) async {
    final db = await database;
    final rows = await db.query(
      'web_sessions',
      where: 'source_id = ?',
      whereArgs: [sourceId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _sessionFromRow(rows.first);
  }

  Future<WebSession?> getSessionForDomain(String domain) async {
    final normalized = domain.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    final db = await database;
    final rows = await db.query(
      'web_sessions',
      where: 'domain = ?',
      whereArgs: [normalized],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _sessionFromRow(rows.first);
  }

  String _sessionKey(String sourceId, String domain) {
    final safeSource = Uri.encodeComponent(sourceId.trim());
    final safeDomain = Uri.encodeComponent(domain.trim().toLowerCase());
    return 'session:$safeSource@$safeDomain';
  }

  @override
  Future<void> saveManualCookies({
    required String sourceId,
    required String domain,
    required String cookieHeader,
    String userAgent = '',
  }) async {
    final normalizedDomain = domain.trim().toLowerCase();
    final cookies = <Map<String, dynamic>>[];
    for (final item in cookieHeader.split(';')) {
      final trimmed = item.trim();
      final eq = trimmed.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      cookies.add({
        'name': trimmed.substring(0, eq),
        'value': trimmed.substring(eq + 1),
        'domain': normalizedDomain,
        'path': '/',
      });
    }

    final session = WebSession(
      id: _sessionKey(sourceId, normalizedDomain),
      sourceId: sourceId,
      domain: normalizedDomain,
      cookiesJson: jsonEncode(cookies),
      userAgent: userAgent,
      updatedAt: DateTime.now(),
    );
    await _saveSession(session);
  }

  @override
  Future<void> saveCookieMaps({
    required String sourceId,
    required String domain,
    required List<Map<String, dynamic>> cookies,
    String userAgent = '',
  }) async {
    final normalizedDomain = domain.trim().toLowerCase();
    final filtered = <Map<String, dynamic>>[];
    for (final cookie in cookies) {
      final name = (cookie['name'] ?? '').toString().trim();
      if (name.isEmpty) {
        continue;
      }
      final value = (cookie['value'] ?? '').toString();
      final next = Map<String, dynamic>.from(cookie)
        ..['name'] = name
        ..['value'] = value
        ..['domain'] = (cookie['domain'] ?? normalizedDomain)
            .toString()
            .toLowerCase();
      filtered.add(next);
    }
    final session = WebSession(
      id: _sessionKey(sourceId, normalizedDomain),
      sourceId: sourceId,
      domain: normalizedDomain,
      cookiesJson: jsonEncode(filtered),
      userAgent: userAgent,
      updatedAt: DateTime.now(),
    );
    await _saveSession(session);
  }

  @override
  Future<void> clearSession(String sessionId) async {
    final db = await database;
    await db.delete('web_sessions', where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<void> _saveSession(WebSession session) async {
    final db = await database;
    await db.insert('web_sessions', {
      'id': session.id,
      'source_id': session.sourceId,
      'domain': session.domain,
      'cookies_json': session.cookiesJson,
      'user_agent': session.userAgent,
      'updated_at': session.updatedAt.millisecondsSinceEpoch,
      'last_verified_at': session.lastVerifiedAt?.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  WebSession _sessionFromRow(Map<String, Object?> row) => WebSession(
    id: row['id'] as String,
    sourceId: row['source_id'] as String,
    domain: row['domain'] as String,
    cookiesJson: row['cookies_json'] as String,
    userAgent: row['user_agent'] as String? ?? '',
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      row['updated_at'] as int? ?? 0,
    ),
    lastVerifiedAt: row['last_verified_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['last_verified_at'] as int),
  );

  @override
  Future<String> exportSourcesJson() async {
    final sources = (await listSources())
        .where((source) => !source.builtin)
        .toList(growable: false);
    return const JsonEncoder.withIndent(
      '  ',
    ).convert(sources.map((item) => item.toJson()).toList());
  }

  Future<List<WebNovelSource>> importSourcesJson(String text) async {
    final report = await importSourcesJsonWithReport(text);
    return report.importedSources;
  }

  @override
  Future<SourceImportReport> importSourcesInputWithReport(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('书源内容不能为空');
    }

    if (trimmed.startsWith('legado://import/')) {
      final uri = Uri.parse(trimmed);
      if (uri.pathSegments.isEmpty || uri.pathSegments.first != 'bookSource') {
        throw const FormatException('当前只支持导入 Legado 书源链接');
      }
      final src = uri.queryParameters['src']?.trim() ?? '';
      if (src.isEmpty) {
        throw const FormatException('Legado 导入链接缺少 src 参数');
      }
      final response = await _client
          .get(Uri.parse(src))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode} for $src');
      }
      final payload = utf8.decode(response.bodyBytes, allowMalformed: true);
      return importSourcesJsonWithReport(payload);
    }

    final asUri = Uri.tryParse(trimmed);
    if (asUri != null &&
        (asUri.scheme == 'http' || asUri.scheme == 'https') &&
        (trimmed.endsWith('.json') ||
            trimmed.contains('/sources') ||
            trimmed.contains('booksource') ||
            trimmed.contains('legado'))) {
      final response = await _client
          .get(asUri)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) {
        throw HttpException('HTTP ${response.statusCode} for $trimmed');
      }
      final payload = utf8.decode(response.bodyBytes, allowMalformed: true);
      return importSourcesJsonWithReport(payload);
    }

    return importSourcesJsonWithReport(trimmed);
  }

  @override
  Future<SourceImportReport> importSourcesJsonWithReport(String text) async {
    final decoded = jsonDecode(text);
    final entries = <dynamic>[];
    final warnings = <String>[];
    var legacyMapped = 0;
    var skipped = 0;
    var updated = 0;
    final entryReports = <SourceImportEntryReport>[];

    if (decoded is List) {
      entries.addAll(decoded);
    } else if (decoded is Map<String, dynamic>) {
      if (decoded['sources'] is List) {
        entries.addAll(decoded['sources'] as List<dynamic>);
      } else {
        entries.add(decoded);
      }
    } else {
      throw const FormatException('书源 JSON 格式错误：必须是数组或对象');
    }

    final imported = <WebNovelSource>[];
    final seenSourceIds = <String>{};
    for (var index = 0; index < entries.length; index++) {
      final raw = entries[index];
      if (raw is! Map<String, dynamic>) {
        skipped += 1;
        final message = '第 ${index + 1} 项不是对象，已跳过。';
        warnings.add(message);
        entryReports.add(
          SourceImportEntryReport(
            index: index + 1,
            status: SourceImportEntryStatus.skipped,
            message: message,
          ),
        );
        continue;
      }

      try {
        final parsed = _parseImportedSource(raw);
        final originalId = parsed.source.id;
        final existing = await getSourceById(originalId);
        final duplicatedIdInPayload = !seenSourceIds.add(originalId);
        final resolvedSource = await _ensureUniqueImportedSourceId(
          parsed.source,
          allowOverwrite: !duplicatedIdInPayload,
        );
        final status = existing == null
            ? SourceImportEntryStatus.imported
            : jsonEncode(existing.toJson()) == jsonEncode(parsed.source.toJson())
            ? SourceImportEntryStatus.skipped
            : (resolvedSource.id == originalId && !existing.builtin)
            ? SourceImportEntryStatus.updated
            : SourceImportEntryStatus.imported;

        if (status == SourceImportEntryStatus.skipped) {
          skipped += 1;
          final message = '已存在且内容一致，已跳过。';
          entryReports.add(
            SourceImportEntryReport(
              index: index + 1,
              status: status,
              sourceId: resolvedSource.id,
              sourceName: resolvedSource.name,
              legacyMapped: parsed.legacyMapped,
              message: message,
              warnings: parsed.warnings,
            ),
          );
          continue;
        }

        await saveSource(resolvedSource);
        imported.add(resolvedSource);
        if (status == SourceImportEntryStatus.updated) {
          updated += 1;
        }

        final entryWarnings = <String>[...parsed.warnings];
        final message = resolvedSource.id == originalId
            ? (status == SourceImportEntryStatus.updated
                  ? '已覆盖更新（同 id）'
                  : '导入成功')
            : 'id 冲突，已重命名为 ${resolvedSource.id}';
        warnings.addAll(
          entryWarnings.map((item) => '[${resolvedSource.name}] $item'),
        );
        entryReports.add(
          SourceImportEntryReport(
            index: index + 1,
            status: status,
            sourceId: resolvedSource.id,
            sourceName: resolvedSource.name,
            legacyMapped: parsed.legacyMapped,
            message: message,
            warnings: entryWarnings,
          ),
        );
        if (parsed.legacyMapped) {
          legacyMapped += 1;
        }
      } catch (error) {
        skipped += 1;
        final message = '第 ${index + 1} 项导入失败：$error';
        warnings.add(message);
        entryReports.add(
          SourceImportEntryReport(
            index: index + 1,
            status: SourceImportEntryStatus.failed,
            message: message,
          ),
        );
      }
    }

    return SourceImportReport(
      importedSources: imported,
      totalEntries: entries.length,
      importedCount: imported.length,
      updatedCount: updated,
      legacyMappedCount: legacyMapped,
      skippedCount: skipped,
      warnings: warnings,
      entries: entryReports,
    );
  }

  // ignore: unused_element
  WebNovelSource _parseImportedSourceLegacy(Map<String, dynamic> json) {
    if (json.containsKey('bookSourceName') ||
        json.containsKey('bookSourceUrl')) {
      final name = json['bookSourceName'] as String? ?? '未命名书源';
      final baseUrl = _normalizeSourceBaseUrl(
        json['bookSourceUrl'] as String? ?? '',
      );
      return WebNovelSource(
        id: _slug(name),
        name: name,
        baseUrl: baseUrl,
        group: json['bookSourceGroup'] as String? ?? '导入',
        enabled: !(json['enabled'] == false),
        priority: json['weight'] as int? ?? 0,
        builtin: false,
        search: BookSourceSearchRule(
          method: HttpMethod.get,
          pathTemplate: json['searchUrl'] as String? ?? '',
          itemSelector: '',
          useSearchProviderFallback: true,
        ),
      );
    }

    return WebNovelSource.fromJson(<String, dynamic>{
      ...json,
      'builtin': false,
    });
  }

  _ImportedSourceParseResult _parseImportedSource(Map<String, dynamic> json) {
    if (_looksLikeLegadoSource(json)) {
      return _parseLegadoSource(json);
    }

    final warnings = <String>[];
    var source = WebNovelSource.fromJson(<String, dynamic>{
      ...json,
      'builtin': false,
    });
    if (source.baseUrl.isNotEmpty) {
      final normalizedBaseUrl = _normalizeSourceBaseUrl(source.baseUrl);
      if (normalizedBaseUrl.isNotEmpty && normalizedBaseUrl != source.baseUrl) {
        source = source.copyWith(baseUrl: normalizedBaseUrl);
      }
    }
    if (source.siteDomains.isEmpty && source.baseUrl.isNotEmpty) {
      final derived = _deriveSiteDomains(source.baseUrl);
      if (derived.isNotEmpty) {
        source = source.copyWith(siteDomains: derived);
        warnings.add('未提供 siteDomains，已从 baseUrl 推断域名。');
      }
    }
    return _ImportedSourceParseResult(source: source, warnings: warnings);
  }

  String _buildImportedSourceId(
    Map<String, dynamic> json, {
    required String name,
    required String baseUrl,
  }) {
    final comment = (json['bookSourceComment'] as String? ?? '').trim();
    final group = (json['bookSourceGroup'] as String? ?? '').trim();
    final searchUrl = (json['searchUrl'] ?? '').toString().trim();
    final label = _slug(
      [
        comment,
        name,
        group,
        baseUrl,
      ].where((item) => item.isNotEmpty).join('_'),
      fallback: 'source',
    );
    final fingerprint = _uuid
        .v5(
          Namespace.url.value,
          [
            comment,
            name,
            group,
            baseUrl,
            searchUrl,
            (json['bookSourceType'] ?? '').toString(),
          ].join('|'),
        )
        .replaceAll('-', '');
    return '${label}_${fingerprint.substring(0, 12)}';
  }

  Future<WebNovelSource> _ensureUniqueImportedSourceId(
    WebNovelSource source, {
    bool allowOverwrite = true,
  }) async {
    final existing = await getSourceById(source.id);
    if (existing == null ||
        jsonEncode(existing.toJson()) == jsonEncode(source.toJson())) {
      return source;
    }

    if (allowOverwrite &&
        !existing.builtin &&
        _shouldOverwriteImportedSource(existing, source)) {
      return source;
    }

    final fingerprint = _uuid
        .v5(
          Namespace.url.value,
          [
            source.name,
            source.baseUrl,
            source.group,
            source.search.pathTemplate,
            source.search.itemSelector,
          ].join('|'),
        )
        .replaceAll('-', '')
        .substring(0, 12);
    final baseId = '${source.id}_$fingerprint';

    for (var index = 0; index < 4; index++) {
      final candidateId = index == 0 ? baseId : '${baseId}_$index';
      final candidate = source.copyWith(id: candidateId);
      final candidateExisting = await getSourceById(candidateId);
      if (candidateExisting == null ||
          jsonEncode(candidateExisting.toJson()) ==
              jsonEncode(candidate.toJson())) {
        return candidate;
      }
    }

    return source.copyWith(
      id: '${baseId}_${DateTime.now().microsecondsSinceEpoch}',
    );
  }

  bool _shouldOverwriteImportedSource(
    WebNovelSource existing,
    WebNovelSource incoming,
  ) {
    String normalizeHost(String host) =>
        host.trim().toLowerCase().replaceFirst('www.', '');

    final existingBaseHost =
        normalizeHost(Uri.tryParse(existing.baseUrl)?.host ?? '');
    final incomingBaseHost =
        normalizeHost(Uri.tryParse(incoming.baseUrl)?.host ?? '');
    if (existingBaseHost.isNotEmpty &&
        incomingBaseHost.isNotEmpty &&
        existingBaseHost == incomingBaseHost) {
      return true;
    }

    final existingDomains =
        existing.siteDomains.map(normalizeHost).where((item) => item.isNotEmpty);
    final incomingDomains =
        incoming.siteDomains.map(normalizeHost).where((item) => item.isNotEmpty);
    final existingSet = existingDomains.toSet();
    final incomingSet = incomingDomains.toSet();
    if (existingSet.isNotEmpty &&
        incomingSet.isNotEmpty &&
        existingSet.intersection(incomingSet).isNotEmpty) {
      return true;
    }

    return false;
  }

  bool _looksLikeLegadoSource(Map<String, dynamic> json) {
    if (json.containsKey('bookSourceName') ||
        json.containsKey('bookSourceUrl')) {
      return true;
    }
    return json.containsKey('searchUrl') ||
        json.containsKey('ruleSearch') ||
        json.containsKey('ruleBookInfo') ||
        json.containsKey('ruleToc') ||
        json.containsKey('ruleContent') ||
        json.containsKey('header') ||
        json.containsKey('loginUrl');
  }

  _ImportedSourceParseResult _parseLegadoSource(Map<String, dynamic> json) {
    final warnings = <String>[];
    final name =
        (json['bookSourceName'] as String?)?.trim().ifEmpty('未命名书源') ?? '未命名书源';
    final baseUrl = _normalizeSourceBaseUrl(
      (json['bookSourceUrl'] as String?)?.trim().ifEmpty(
            json['baseUrl'] as String? ?? '',
          ) ??
          '',
    );
    final searchRequest = _parseLegadoRequestDescriptorCompat(
      baseUrl,
      json['searchUrl'],
      warnings,
      fieldName: 'searchUrl',
    );
    final searchRuleMap = _asJsonMap(json['ruleSearch']);
    final detailRuleMap = _asJsonMap(json['ruleBookInfo']);
    final tocRuleMap = _asJsonMap(json['ruleToc']);
    final contentRuleMap = _asJsonMap(json['ruleContent']);
    final chapterList = _translateLegadoListSelector(
      tocRuleMap['chapterList'],
      warnings,
      fieldName: 'ruleToc.chapterList',
    );
    final mergedHeaders = <String, String>{
      ..._decodeHeaderMap(json['header'], warnings),
      ...searchRequest.headers,
    };
    final userAgent =
        (json['httpUserAgent'] as String?)?.trim().ifEmpty(
          mergedHeaders.remove('User-Agent') ??
              mergedHeaders.remove('user-agent') ??
              '',
        ) ??
        '';
    final loginUrl = (json['loginUrl'] as String? ?? '').trim();
    final source = WebNovelSource(
      id: _slug(
        (json['bookSourceComment'] as String?)?.trim().isNotEmpty == true
            ? "${json['bookSourceComment']}_$name"
            : name,
        fallback: _buildImportedSourceId(json, name: name, baseUrl: baseUrl),
      ),
      name: name,
      baseUrl: baseUrl,
      group: (json['bookSourceGroup'] as String?)?.trim().ifEmpty('导入') ?? '导入',
      charset: searchRequest.charset,
      userAgent: userAgent,
      headers: mergedHeaders,
      enabled: !(json['enabled'] == false),
      priority: _asInt(json['weight']),
      supportsWebViewLogin: loginUrl.isNotEmpty,
      supportsCookieImport: true,
      search: BookSourceSearchRule(
        method: searchRequest.method,
        pathTemplate: searchRequest.pathTemplate,
        queryField: searchRequest.queryField,
        itemSelector: _translateLegadoListSelector(
          searchRuleMap['bookList'],
          warnings,
          fieldName: 'ruleSearch.bookList',
        ).selector,
        titleRule: _translateLegadoSelectorRule(
          searchRuleMap['name'],
          warnings,
          fieldName: 'ruleSearch.name',
        ),
        urlRule: _translateLegadoSelectorRule(
          searchRuleMap['bookUrl'],
          warnings,
          fieldName: 'ruleSearch.bookUrl',
          absoluteUrl: true,
        ),
        authorRule: _translateLegadoSelectorRule(
          searchRuleMap['author'],
          warnings,
          fieldName: 'ruleSearch.author',
        ),
        coverRule: _translateLegadoSelectorRule(
          searchRuleMap['coverUrl'],
          warnings,
          fieldName: 'ruleSearch.coverUrl',
          absoluteUrl: true,
        ),
        descriptionRule: _translateLegadoSelectorRule(
          searchRuleMap['intro'],
          warnings,
          fieldName: 'ruleSearch.intro',
        ),
        useSearchProviderFallback: true,
      ),
      detail: BookSourceDetailRule(
        titleRule: _translateLegadoSelectorRule(
          detailRuleMap['name'],
          warnings,
          fieldName: 'ruleBookInfo.name',
        ),
        authorRule: _translateLegadoSelectorRule(
          detailRuleMap['author'],
          warnings,
          fieldName: 'ruleBookInfo.author',
        ),
        coverRule: _translateLegadoSelectorRule(
          detailRuleMap['coverUrl'],
          warnings,
          fieldName: 'ruleBookInfo.coverUrl',
          absoluteUrl: true,
        ),
        descriptionRule: _translateLegadoSelectorRule(
          detailRuleMap['intro'],
          warnings,
          fieldName: 'ruleBookInfo.intro',
        ),
        firstChapterRule: _translateLegadoSelectorRule(
          detailRuleMap['tocUrl'],
          warnings,
          fieldName: 'ruleBookInfo.tocUrl',
          absoluteUrl: true,
        ),
        chapterListUrlRule: _translateLegadoSelectorRule(
          detailRuleMap['tocUrl'],
          warnings,
          fieldName: 'ruleBookInfo.tocUrl',
          absoluteUrl: true,
        ),
      ),
      chapters: BookSourceChapterRule(
        itemSelector: chapterList.selector,
        titleRule: _translateLegadoSelectorRule(
          tocRuleMap['chapterName'],
          warnings,
          fieldName: 'ruleToc.chapterName',
        ),
        urlRule: _translateLegadoSelectorRule(
          tocRuleMap['chapterUrl'],
          warnings,
          fieldName: 'ruleToc.chapterUrl',
          absoluteUrl: true,
        ),
        reverse: chapterList.reverse,
      ),
      content: BookSourceContentRule(
        titleRule: _translateLegadoSelectorRule(
          contentRuleMap['title'],
          warnings,
          fieldName: 'ruleContent.title',
        ),
        contentRule: _translateLegadoSelectorRule(
          contentRuleMap['content'],
          warnings,
          fieldName: 'ruleContent.content',
        ),
        nextPageRule: _translateLegadoSelectorRule(
          contentRuleMap['nextContentUrl'],
          warnings,
          fieldName: 'ruleContent.nextContentUrl',
          absoluteUrl: true,
        ),
        nextPageKeyword: '下一章',
      ),
      login: BookSourceLoginRule(
        loginUrl: loginUrl,
        checkUrl: (json['loginCheckJs'] as String? ?? '').trim(),
        loggedInKeyword: '退出',
        expiredKeyword: '登录',
        domain: _deriveDomain(baseUrl),
      ),
      tags: <String>[
        'Legado',
        if (chapterList.selector.isNotEmpty) '目录',
        if (searchRequest.fetchViaBrowserOnly) '浏览器优先',
      ],
      siteDomains: _deriveSiteDomains(baseUrl),
      fetchViaBrowserOnly: searchRequest.fetchViaBrowserOnly,
      builtin: false,
    );

    _appendLegadoCompatibilityWarnings(
      warnings,
      searchRuleMap,
      detailRuleMap,
      tocRuleMap,
      contentRuleMap,
    );
    return _ImportedSourceParseResult(
      source: source,
      legacyMapped: true,
      warnings: warnings,
    );
  }

  Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String && value.trim().startsWith('{')) {
      try {
        return jsonDecode(value) as Map<String, dynamic>;
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  int _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value') ?? 0;
  }

  Map<String, String> _decodeHeaderMap(dynamic value, List<String> warnings) {
    if (value == null) {
      return const <String, String>{};
    }
    if (value is Map) {
      return {
        for (final entry in value.entries)
          entry.key.toString(): entry.value.toString(),
      };
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return const <String, String>{};
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          return {
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value.toString(),
          };
        }
      } catch (_) {
        warnings.add('header 不是有效的 JSON，已忽略。');
      }
    }
    return const <String, String>{};
  }

  // ignore: unused_element
  _LegadoRequestDescriptor _parseLegadoRequestDescriptor(
    String baseUrl,
    dynamic rawValue,
    List<String> warnings, {
    required String fieldName,
  }) {
    final raw = (rawValue as String? ?? '').trim();
    if (raw.isEmpty) {
      return const _LegadoRequestDescriptor(
        pathTemplate: '',
        method: HttpMethod.get,
        queryField: 'q',
      );
    }

    var urlPart = raw;
    Map<String, dynamic> options = const <String, dynamic>{};
    final optionIndex = raw.indexOf(',{');
    if (optionIndex > 0) {
      urlPart = raw.substring(0, optionIndex).trim();
      final optionPart = raw.substring(optionIndex + 1).trim();
      try {
        options = jsonDecode(optionPart) as Map<String, dynamic>;
      } catch (_) {
        warnings.add('$fieldName 的请求配置解析失败，已忽略附加配置。');
      }
    }

    final normalizedUrl = urlPart.replaceAllMapped(
      RegExp(r'\{\{([^{}]+)\}\}'),
      (match) {
        final token = (match.group(1) ?? '').toLowerCase();
        if (token.contains('key')) {
          return '{query}';
        }
        if (token.contains('page')) {
          return '1';
        }
        return '';
      },
    );
    final body = (options['body'] as String? ?? '').trim();
    final method = (options['method'] as String? ?? '').toUpperCase() == 'POST'
        ? HttpMethod.post
        : HttpMethod.get;

    return _LegadoRequestDescriptor(
      pathTemplate: normalizedUrl.isEmpty ? baseUrl : normalizedUrl,
      method: method,
      queryField: _parseLegadoBodyQueryField(body) ?? 'q',
      charset: (options['charset'] as String? ?? '').trim(),
      headers: _decodeHeaderMap(options['headers'], warnings),
      fetchViaBrowserOnly: options['webView'] == true,
    );
  }

  _LegadoRequestDescriptor _parseLegadoRequestDescriptorCompat(
    String baseUrl,
    dynamic rawValue,
    List<String> warnings, {
    required String fieldName,
  }) {
    final raw = (rawValue as String? ?? '').trim();
    if (raw.isEmpty) {
      return const _LegadoRequestDescriptor(
        pathTemplate: '',
        method: HttpMethod.get,
        queryField: 'q',
      );
    }

    var urlPart = raw;
    Map<String, dynamic> options = const <String, dynamic>{};
    final optionIndex = raw.indexOf(',{');
    if (optionIndex > 0) {
      urlPart = raw.substring(0, optionIndex).trim();
      options = _decodeLegadoOptionObjects(
        raw.substring(optionIndex + 1).trim(),
        warnings,
        fieldName: fieldName,
      );
    }

    final normalizedUrl = urlPart.replaceAllMapped(
      RegExp(r'\{\{([^{}]+)\}\}'),
      (match) {
        final token = (match.group(1) ?? '').toLowerCase();
        if (token.contains('key')) {
          return '{query}';
        }
        if (token.contains('page')) {
          return '1';
        }
        return '';
      },
    );

    final body = (options['body'] as String? ?? '').trim();
    final method = (options['method'] as String? ?? '').toUpperCase() == 'POST'
        ? HttpMethod.post
        : HttpMethod.get;

    return _LegadoRequestDescriptor(
      pathTemplate: normalizedUrl.isEmpty ? baseUrl : normalizedUrl,
      method: method,
      queryField: _parseLegadoBodyQueryField(body) ?? 'q',
      charset: (options['charset'] as String? ?? '').trim(),
      headers: _decodeHeaderMap(options['headers'], warnings),
      fetchViaBrowserOnly: options['webView'] == true,
    );
  }

  Map<String, dynamic> _decodeLegadoOptionObjects(
    String raw,
    List<String> warnings, {
    required String fieldName,
  }) {
    final merged = <String, dynamic>{};
    var index = 0;

    while (index < raw.length) {
      while (index < raw.length &&
          (raw[index] == ',' || raw[index].trim().isEmpty)) {
        index++;
      }
      if (index >= raw.length || raw[index] != '{') {
        break;
      }

      final end = _findMatchingBrace(raw, index);
      if (end < 0) {
        warnings.add('$fieldName 的请求配置解析失败，已忽略附加配置。');
        break;
      }

      try {
        final decoded = jsonDecode(raw.substring(index, end + 1));
        if (decoded is Map) {
          merged.addAll(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      } catch (_) {
        warnings.add('$fieldName 的请求配置解析失败，已忽略附加配置。');
        break;
      }
      index = end + 1;
    }

    return merged;
  }

  int _findMatchingBrace(String raw, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var index = start; index < raw.length; index++) {
      final char = raw[index];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (char == r'\') {
        escaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (inString) {
        continue;
      }
      if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return index;
        }
      }
    }

    return -1;
  }

  String? _parseLegadoBodyQueryField(String body) {
    if (body.isEmpty) {
      return null;
    }
    for (final segment in body.split('&')) {
      final eq = segment.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      final key = segment.substring(0, eq).trim();
      final value = segment.substring(eq + 1).toLowerCase();
      if (value.contains('{{key}}') || value.contains('{query}')) {
        return key;
      }
    }
    return null;
  }

  _LegadoListSelectorResult _translateLegadoListSelector(
    dynamic rawValue,
    List<String> warnings, {
    required String fieldName,
  }) {
    final raw = (rawValue as String? ?? '').trim();
    if (raw.isEmpty) {
      return const _LegadoListSelectorResult(selector: '');
    }

    var reverse = false;
    var working = raw;
    if (working.startsWith('-')) {
      reverse = true;
      working = working.substring(1).trim();
    }
    final selector =
        _translateLegadoSelectorExpression(
              working,
              warnings,
              fieldName: fieldName,
              allowOnlyCssSelector: true,
            )
            as String;
    return _LegadoListSelectorResult(selector: selector, reverse: reverse);
  }

  SelectorRule _translateLegadoSelectorRule(
    dynamic rawValue,
    List<String> warnings, {
    required String fieldName,
    bool absoluteUrl = false,
  }) {
    final raw = (rawValue as String? ?? '').trim();
    if (raw.isEmpty) {
      return const SelectorRule(expression: '');
    }
    return _translateLegadoSelectorExpression(
          raw,
          warnings,
          fieldName: fieldName,
          absoluteUrl: absoluteUrl,
        )
        as SelectorRule;
  }

  Object _translateLegadoSelectorExpression(
    String raw,
    List<String> warnings, {
    required String fieldName,
    bool absoluteUrl = false,
    bool allowOnlyCssSelector = false,
  }) {
    final preservedRaw = raw.trim();
    if (_shouldPreserveLegadoRawRule(
      preservedRaw,
      allowOnlyCssSelector: allowOnlyCssSelector,
    )) {
      return allowOnlyCssSelector
          ? preservedRaw
          : SelectorRule(
              type: RuleSelectorType.legado,
              expression: preservedRaw,
              absoluteUrl: absoluteUrl,
            );
    }

    for (final candidate in raw.split('||')) {
      final trimmed = candidate.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (_looksLikeUnsupportedXPath(trimmed)) {
        warnings.add('$fieldName 使用了 XPath，当前仍需手工改成 CSS。');
        continue;
      }
      if (trimmed.startsWith('@json:') || trimmed.startsWith(r'$.')) {
        warnings.add('$fieldName 使用了 JSONPath，当前仍需手工改成 CSS/HTML。');
        continue;
      }
      if (trimmed.startsWith('<js>') || trimmed.startsWith('@js:')) {
        warnings.add('$fieldName 使用了 JS 规则，当前暂不支持。');
        continue;
      }

      final regexRule = _parseLegadoRegexRule(trimmed);
      if (regexRule != null && !allowOnlyCssSelector) {
        return regexRule;
      }

      final parsed = _parseLegadoCssLikeRule(
        trimmed,
        absoluteUrl: absoluteUrl,
        allowOnlyCssSelector: allowOnlyCssSelector,
      );
      if (parsed != null) {
        return parsed;
      }
    }

    warnings.add('$fieldName 暂未兼容，导入后可能仍需手工调整。');
    return allowOnlyCssSelector ? '' : const SelectorRule(expression: '');
  }

  bool _shouldPreserveLegadoRawRule(
    String raw, {
    required bool allowOnlyCssSelector,
  }) {
    if (raw.isEmpty || _looksLikeUnsupportedXPath(raw)) {
      return false;
    }
    return raw.contains('<js>') ||
        raw.contains('@js:') ||
        _looksLikeJsonSelector(raw) ||
        raw.contains('{{') ||
        raw.contains('##') ||
        raw.contains('\n') ||
        (allowOnlyCssSelector && raw.contains('||'));
  }

  bool _looksLikeUnsupportedXPath(String raw) {
    return raw.startsWith('@XPath:') ||
        raw.startsWith('@xpath:') ||
        (raw.startsWith('//') && !raw.startsWith('//@'));
  }

  bool _looksLikeJsonSelector(String raw) {
    final trimmed = raw.trimLeft();
    return trimmed.startsWith('@json:') ||
        trimmed.startsWith(r'$.') ||
        trimmed.startsWith(r'$[') ||
        trimmed.startsWith(r'$..');
  }

  SelectorRule? _parseLegadoRegexRule(String raw) {
    if (!raw.startsWith('##')) {
      return null;
    }
    final match = RegExp(r'^##(.+?)##').firstMatch(raw);
    if (match == null) {
      return null;
    }
    return SelectorRule(
      type: RuleSelectorType.regex,
      expression: '',
      regex: match.group(1),
    );
  }

  Object? _parseLegadoCssLikeRule(
    String raw, {
    required bool absoluteUrl,
    required bool allowOnlyCssSelector,
  }) {
    var working = raw;
    if (working.startsWith('@css:')) {
      working = working.substring(5).trim();
    }

    final selectors = <String>[];
    String? attr;
    for (final part in working.split('@').map((item) => item.trim())) {
      if (part.isEmpty) {
        continue;
      }
      final lowered = part.toLowerCase();
      if (lowered == 'text' ||
          lowered == 'owntext' ||
          lowered == 'html' ||
          lowered == 'all') {
        attr = null;
        continue;
      }
      if (lowered == 'href' ||
          lowered == 'src' ||
          lowered == 'content' ||
          lowered == 'value') {
        attr = lowered;
        continue;
      }

      final selector = _convertLegadoTokenToCss(part);
      if (selector == null) {
        if (!part.contains(' ') &&
            !part.startsWith('.') &&
            !part.startsWith('#') &&
            !part.startsWith('[') &&
            !part.contains('>') &&
            !RegExp(r'^[a-zA-Z][\\w-]*$').hasMatch(part)) {
          return null;
        }
        selectors.add(part);
      } else {
        selectors.add(selector);
      }
    }

    final expression = selectors.join(' ').trim();
    if (expression.isEmpty) {
      return null;
    }
    if (allowOnlyCssSelector) {
      return expression;
    }
    return SelectorRule(
      expression: expression,
      attr: attr,
      absoluteUrl: absoluteUrl,
    );
  }

  String? _convertLegadoTokenToCss(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if (trimmed.startsWith('class.')) {
      final parts = trimmed.split('.');
      final name = parts
          .skip(1)
          .firstWhere(
            (item) => item.isNotEmpty && int.tryParse(item) == null,
            orElse: () => '',
          );
      return name.isEmpty ? null : '.${name.replaceAll(':', r'\\:')}';
    }
    if (trimmed.startsWith('id.')) {
      final parts = trimmed.split('.');
      final name = parts
          .skip(1)
          .firstWhere(
            (item) => item.isNotEmpty && int.tryParse(item) == null,
            orElse: () => '',
          );
      return name.isEmpty ? null : '#${name.replaceAll(':', r'\\:')}';
    }
    if (trimmed.startsWith('tag.')) {
      final parts = trimmed.split('.');
      return parts
          .skip(1)
          .firstWhere(
            (item) => item.isNotEmpty && int.tryParse(item) == null,
            orElse: () => '',
          );
    }
    if (trimmed.startsWith('.') ||
        trimmed.startsWith('#') ||
        trimmed.startsWith('[') ||
        trimmed.contains(' ') ||
        trimmed.contains('>')) {
      return trimmed;
    }
    if (RegExp(r'^[a-zA-Z][\\w-]*$').hasMatch(trimmed)) {
      return trimmed;
    }
    return null;
  }

  String _deriveDomain(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    return uri == null ? '' : '.${uri.host.replaceFirst('www.', '')}';
  }

  String _normalizeSourceBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    var normalized = trimmed;
    final legadoSuffixIndex = normalized.indexOf('##');
    if (legadoSuffixIndex > 0) {
      normalized = normalized.substring(0, legadoSuffixIndex).trim();
    }

    final absoluteMatch = RegExp(
      r'https?://[^\s,]+',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (absoluteMatch != null) {
      return absoluteMatch.group(0) ?? '';
    }
    return normalized.startsWith('http://') || normalized.startsWith('https://')
        ? normalized
        : '';
  }

  List<String> _deriveSiteDomains(String baseUrl) {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || uri.host.isEmpty) {
      return const <String>[];
    }
    final host = uri.host;
    final stripped = host.replaceFirst('www.', '');
    return {host, stripped}.where((item) => item.isNotEmpty).toList();
  }

  void _appendLegadoCompatibilityWarnings(
    List<String> warnings,
    Map<String, dynamic> searchRuleMap,
    Map<String, dynamic> detailRuleMap,
    Map<String, dynamic> tocRuleMap,
    Map<String, dynamic> contentRuleMap,
  ) {
    final unsupportedKeys = <String>[
      if (searchRuleMap.containsKey('checkKeyWord')) 'ruleSearch.checkKeyWord',
      if (detailRuleMap.containsKey('init')) 'ruleBookInfo.init',
      if (tocRuleMap.containsKey('nextTocUrl')) 'ruleToc.nextTocUrl',
      if (contentRuleMap.containsKey('webJs')) 'ruleContent.webJs',
      if (contentRuleMap.containsKey('replaceRegex'))
        'ruleContent.replaceRegex',
    ];
    if (unsupportedKeys.isNotEmpty) {
      warnings.add('以下 Legado 字段当前只做保留，不会完整执行：${unsupportedKeys.join('、')}');
    }
  }

  String _slug(String value, {String fallback = ''}) {
    final lower = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return lower
        .replaceAll(RegExp(r'^_+|_+$'), '')
        .ifEmpty(fallback.ifEmpty(_uuid.v4()));
  }

  Future<void> migrateLegacyRecords() async {
    final books = await _libraryService.loadBooks();
    var changed = false;

    for (final book in books.where(
      (item) => item.format == BookFormat.webnovel,
    )) {
      if (book.filePath.startsWith('webnovel://book/')) {
        await _ensureBookShellExists(book);
        continue;
      }

      final parsed = _parseLegacyPath(book.filePath);
      if (parsed == null) {
        continue;
      }

      final source = await _findSourceFromLegacy(parsed.$1);
      final metaId = _uuid.v4();
      final meta = WebNovelBookMeta(
        id: metaId,
        libraryBookId: book.id,
        sourceId: source?.id ?? _slug(parsed.$1),
        title: book.title,
        author: book.author,
        detailUrl: parsed.$2,
        originUrl: parsed.$2,
        sourceSnapshot: source == null ? '' : jsonEncode(source.toJson()),
      );
      await _upsertBookMeta(meta);
      await _upsertBookSource(
        webBookId: meta.id,
        sourceId: meta.sourceId,
        detailUrl: meta.detailUrl,
        title: meta.title,
        author: meta.author,
        coverUrl: meta.coverUrl,
      );

      final updated = book.copyWith(filePath: 'webnovel://book/${meta.id}');
      await _libraryService.updateBook(updated);
      changed = true;
    }

    if (changed) {
      await AppRunLogService.instance.logInfo(
        'legacy webnovel records migrated',
      );
    }
  }

  (String, String)? _parseLegacyPath(String path) {
    if (!path.startsWith('webnovel://') ||
        path.startsWith('webnovel://book/')) {
      return null;
    }
    final payload = path.substring('webnovel://'.length);
    final slashIndex = payload.indexOf('/');
    if (slashIndex <= 0 || slashIndex >= payload.length - 1) {
      return null;
    }
    return (
      payload.substring(0, slashIndex),
      payload.substring(slashIndex + 1),
    );
  }

  Future<WebNovelSource?> _findSourceFromLegacy(String sourceName) async {
    final sources = await listSources();
    for (final source in sources) {
      if (source.id == sourceName || source.name == sourceName) {
        return source;
      }
    }
    return null;
  }

  Future<void> _ensureBookShellExists(Book book) async {
    final webBookId = book.filePath.substring('webnovel://book/'.length);
    final existing = await getBookMeta(webBookId);
    if (existing != null) {
      return;
    }
    await _upsertBookMeta(
      WebNovelBookMeta(
        id: webBookId,
        libraryBookId: book.id,
        sourceId: '',
        title: book.title,
        author: book.author,
        detailUrl: '',
        originUrl: '',
      ),
    );
  }

  Future<void> _upsertBookMeta(WebNovelBookMeta meta) async {
    final db = await database;
    await db.insert('web_books', {
      'id': meta.id,
      'library_book_id': meta.libraryBookId,
      'source_id': meta.sourceId,
      'title': meta.title,
      'author': meta.author,
      'detail_url': meta.detailUrl,
      'origin_url': meta.originUrl,
      'cover_url': meta.coverUrl,
      'description': meta.description,
      'last_chapter_title': meta.lastChapterTitle,
      'updated_at': meta.updatedAt?.millisecondsSinceEpoch,
      'source_snapshot': meta.sourceSnapshot,
      'chapter_sync_status': meta.chapterSyncStatus.storageValue,
      'chapter_sync_error': meta.chapterSyncError,
      'chapter_sync_retry_count': meta.chapterSyncRetryCount,
      'chapter_sync_updated_at':
          meta.chapterSyncUpdatedAt?.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _upsertBookSource({
    required String webBookId,
    required String sourceId,
    required String detailUrl,
    required String title,
    required String author,
    required String coverUrl,
  }) async {
    final db = await database;
    await db.insert('web_book_sources', {
      'id': '$webBookId::$sourceId',
      'web_book_id': webBookId,
      'source_id': sourceId,
      'detail_url': detailUrl,
      'title': title,
      'author': author,
      'cover_url': coverUrl,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  WebNovelBookMeta _bookMetaFromRow(Map<String, Object?> row) =>
      WebNovelBookMeta(
        id: row['id'] as String,
        libraryBookId: row['library_book_id'] as String,
        sourceId: row['source_id'] as String,
        title: row['title'] as String,
        author: row['author'] as String,
        detailUrl: row['detail_url'] as String,
        originUrl: row['origin_url'] as String,
        coverUrl: row['cover_url'] as String? ?? '',
        description: row['description'] as String? ?? '',
        lastChapterTitle: row['last_chapter_title'] as String? ?? '',
        updatedAt: row['updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
        sourceSnapshot: row['source_snapshot'] as String? ?? '',
        chapterSyncStatus: WebChapterSyncStatusX.fromStorageValue(
          row['chapter_sync_status'] as String?,
        ),
        chapterSyncError: row['chapter_sync_error'] as String? ?? '',
        chapterSyncRetryCount: row['chapter_sync_retry_count'] as int? ?? 0,
        chapterSyncUpdatedAt: row['chapter_sync_updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                row['chapter_sync_updated_at'] as int,
              ),
      );

  Future<WebNovelBookMeta?> getBookMeta(String webBookId) async {
    final db = await database;
    final rows = await db.query(
      'web_books',
      where: 'id = ?',
      whereArgs: [webBookId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _bookMetaFromRow(rows.first);
  }

  @override
  Future<WebNovelBookMeta?> findBookMetaByUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final db = await database;
    final rows = await db.query(
      'web_books',
      where: 'origin_url = ? OR detail_url = ?',
      whereArgs: [trimmed, trimmed],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _bookMetaFromRow(rows.first);
  }

  @override
  Future<List<WebChapterRecord>> getChapters(
    String webBookId, {
    bool refresh = false,
  }) async {
    final meta = await getBookMeta(webBookId);
    if (meta == null) {
      return const <WebChapterRecord>[];
    }

    final db = await database;
    if (meta.sourceId == _readerModeSourceId) {
      final cached = await db.query(
        'web_chapters',
        where: 'web_book_id = ?',
        whereArgs: [webBookId],
        orderBy: 'chapter_index ASC',
      );
      return cached.map(_chapterFromRow).toList();
    }
    if (!refresh) {
      final cached = await db.query(
        'web_chapters',
        where: 'web_book_id = ?',
        whereArgs: [webBookId],
        orderBy: 'chapter_index ASC',
      );
      if (cached.isNotEmpty) {
        return cached.map(_chapterFromRow).toList();
      }
    }

    if (meta.detailUrl.isEmpty) {
      return const <WebChapterRecord>[];
    }

    await _upsertChapterSyncTask(
      webBookId: webBookId,
      status: _chapterSyncTaskPending,
      attempt: refresh ? 0 : meta.chapterSyncRetryCount,
      nextRetryAt: _now(),
      lastError: refresh ? '' : meta.chapterSyncError,
    );
    await _runChapterSyncTask(webBookId, force: true);

    final synced = await db.query(
      'web_chapters',
      where: 'web_book_id = ?',
      whereArgs: [webBookId],
      orderBy: 'chapter_index ASC',
    );
    return synced.map(_chapterFromRow).toList();
  }

  Future<WebChapterContent?> getCachedChapterContent(String chapterId) async {
    final db = await database;
    final rows = await db.query(
      'web_chapter_cache',
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    final text = row['text'] as String? ?? '';
    final html = row['html'] as String? ?? '';
    final nowMs = _now().millisecondsSinceEpoch;
    final currentSizeBytes = row['size_bytes'] as int? ?? 0;
    final computedSizeBytes = currentSizeBytes > 0
        ? currentSizeBytes
        : utf8.encode(text).length + utf8.encode(html).length;
    await db.update(
      'web_chapter_cache',
      {
        'last_accessed_at': nowMs,
        if (currentSizeBytes <= 0) 'size_bytes': computedSizeBytes,
      },
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
    );
    return WebChapterContent(
      chapterId: row['chapter_id'] as String,
      sourceId: row['source_id'] as String,
      title: row['title'] as String,
      text: text,
      html: html,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(row['fetched_at'] as int),
      isComplete: (row['is_complete'] as int? ?? 1) == 1,
    );
  }

  Future<WebChapterContent> getChapterContent(
    String webBookId,
    int chapterIndex, {
    bool refresh = false,
  }) async {
    final chapters = await getChapters(webBookId, refresh: refresh);
    if (chapters.isEmpty ||
        chapterIndex < 0 ||
        chapterIndex >= chapters.length) {
      throw Exception('未找到章节');
    }

    final chapter = chapters[chapterIndex];
    if (!refresh) {
      final cached = await getCachedChapterContent(chapter.id);
      if (cached != null) {
        return cached;
      }
    }

    final meta = await getBookMeta(webBookId);
    final source = meta == null ? null : await _sourceForMeta(meta);
    if (meta == null) {
      throw Exception('未找到网文来源');
    }
    if (meta.sourceId == _readerModeSourceId) {
      final readerSource =
          source ?? _buildReaderModeSource(Uri.tryParse(meta.originUrl));
      final page = await _requestPage(
        chapter.url,
        source: readerSource,
        referer: meta.originUrl,
      );
      final article = _extractReaderMode(page.document, page.requestUrl);
      final content = WebChapterContent(
        chapterId: chapter.id,
        sourceId: readerSource.id,
        title: article.pageTitle.ifEmpty(chapter.title),
        text: article.contentText,
        html: article.contentHtml,
        fetchedAt: DateTime.now(),
        isComplete: true,
      );
      final sizeBytes =
          utf8.encode(content.text).length + utf8.encode(content.html).length;
      final db = await database;
      await db.insert('web_chapter_cache', {
        'chapter_id': content.chapterId,
        'source_id': content.sourceId,
        'title': content.title,
        'text': content.text,
        'html': content.html,
        'fetched_at': content.fetchedAt.millisecondsSinceEpoch,
        'is_complete': content.isComplete ? 1 : 0,
        'last_accessed_at': content.fetchedAt.millisecondsSinceEpoch,
        'size_bytes': sizeBytes,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return content;
    }
    if (source == null) {
      throw Exception('未找到网文来源');
    }

    final page = await _requestPage(
      chapter.url,
      source: source,
      referer: meta.detailUrl,
    );
    final parsed = _extractChapter(page, source, chapter.title);
    final content = WebChapterContent(
      chapterId: chapter.id,
      sourceId: source.id,
      title: parsed.$1,
      text: parsed.$2,
      html: parsed.$3,
      fetchedAt: DateTime.now(),
      isComplete: parsed.$4,
    );

    final sizeBytes =
        utf8.encode(content.text).length + utf8.encode(content.html).length;
    final db = await database;
    await db.insert('web_chapter_cache', {
      'chapter_id': content.chapterId,
      'source_id': content.sourceId,
      'title': content.title,
      'text': content.text,
      'html': content.html,
      'fetched_at': content.fetchedAt.millisecondsSinceEpoch,
      'is_complete': content.isComplete ? 1 : 0,
      'last_accessed_at': content.fetchedAt.millisecondsSinceEpoch,
      'size_bytes': sizeBytes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return content;
  }

  @override
  Future<int> cacheBookChapters(
    String webBookId, {
    int startIndex = 0,
    int? endIndex,
    bool forceRefresh = false,
    bool background = true,
  }) async {
    await getChapters(webBookId, refresh: forceRefresh);
    final manager = await _ensureDownloadManagerStarted();
    final enqueue = await manager.enqueueBookCache(
      webBookId,
      startIndex: startIndex,
      endIndex: endIndex,
      forceRefresh: forceRefresh,
      priority: 10,
    );
    if (background) {
      return enqueue.enqueuedChapters;
    }

    final db = await database;
    final deadline = DateTime.now().add(AppTimeouts.webnovelCacheForegroundWait);
    while (DateTime.now().isBefore(deadline)) {
      await manager.pumpOnce();
      final rows = await db.query(
        WebNovelDownloadManager.tableTasks,
        columns: ['status', 'completed_count'],
        where: 'id = ?',
        whereArgs: [enqueue.bookTaskId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final status = rows.first['status']?.toString() ?? '';
        final completed = rows.first['completed_count'] as int? ?? 0;
        if (status == 'completed' || status == 'failed') {
          return completed;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    final finalRows = await db.query(
      WebNovelDownloadManager.tableTasks,
      columns: ['completed_count'],
      where: 'id = ?',
      whereArgs: [enqueue.bookTaskId],
      limit: 1,
    );
    return finalRows.isEmpty ? 0 : (finalRows.first['completed_count'] as int? ?? 0);
  }

  @override
  Stream<int> watchDownloadTasks() {
    final manager = _downloadManager ??= WebNovelDownloadManager(
      database: () async => database,
      downloadChapter: (
        String webBookId,
        int chapterIndex, {
        required bool forceRefresh,
      }) async {
        await getChapterContent(webBookId, chapterIndex, refresh: forceRefresh);
        await _enforceCachePolicies();
      },
    );
    unawaited(manager.start());
    return manager.events;
  }

  @override
  Future<List<WebDownloadTask>> listDownloadTasks({
    String webBookId = '',
    bool includeCompleted = true,
    int limit = 200,
  }) async {
    final manager = await _ensureDownloadManagerStarted();
    return manager.listTasks(
      webBookId: webBookId,
      includeCompleted: includeCompleted,
      limit: limit,
    );
  }

  @override
  Future<void> pauseAllDownloads() async {
    final manager = await _ensureDownloadManagerStarted();
    await manager.pauseAll();
  }

  @override
  Future<void> resumeAllDownloads() async {
    final manager = await _ensureDownloadManagerStarted();
    await manager.resumeAll();
  }

  @override
  Future<void> clearTerminalDownloadTasks() async {
    final manager = await _ensureDownloadManagerStarted();
    await manager.clearTerminalTasks();
  }

  @override
  Future<void> clearAllDownloadTasks() async {
    final manager = await _ensureDownloadManagerStarted();
    await manager.clearAllTasks();
  }

  @override
  Future<int> clearCachedChapters({String webBookId = ''}) async {
    final db = await database;
    if (webBookId.trim().isEmpty) {
      return db.delete('web_chapter_cache');
    }
    final chapterRows = await db.query(
      'web_chapters',
      columns: ['id'],
      where: 'web_book_id = ?',
      whereArgs: [webBookId.trim()],
    );
    final ids = chapterRows
        .map((row) => row['id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (ids.isEmpty) {
      return 0;
    }
    final placeholders = List.filled(ids.length, '?').join(', ');
    return db.delete(
      'web_chapter_cache',
      where: 'chapter_id IN ($placeholders)',
      whereArgs: ids,
    );
  }

  @override
  Future<Map<String, int>> getChapterCacheStats() async {
    final db = await database;
    final cachedCount =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(1) FROM web_chapter_cache'),
        ) ??
        0;
    final cachedBytes =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COALESCE(SUM(size_bytes), 0) FROM web_chapter_cache',
          ),
        ) ??
        0;
    final cachedBooks =
        Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COUNT(DISTINCT ch.web_book_id)
            FROM web_chapter_cache c
            JOIN web_chapters ch ON ch.id = c.chapter_id
            ''',
          ),
        ) ??
        0;
    return <String, int>{
      'cachedChapters': cachedCount,
      'cachedBytes': cachedBytes,
      'cachedBooks': cachedBooks,
    };
  }

  Future<int> _getDownloadSettingInt(String key, int fallback) async {
    final db = await database;
    final rows = await db.query(
      WebNovelDownloadManager.tableSettings,
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

  @override
  Future<int> getDownloadSettingInt(String key, int fallback) =>
      _getDownloadSettingInt(key, fallback);

  @override
  Future<void> setDownloadSettingInt(String key, int value) async {
    final manager = await _ensureDownloadManagerStarted();
    await manager.setIntSetting(key, value);
  }

  Future<void> _enforceCachePolicies() async {
    final lastRun = _lastCachePolicyEnforcedAt;
    final now = _now();
    if (lastRun != null && now.difference(lastRun) < const Duration(seconds: 3)) {
      return;
    }
    _lastCachePolicyEnforcedAt = now;

    final maxBytes = await _getDownloadSettingInt('cache_quota_bytes', 0);
    final maxBooks = await _getDownloadSettingInt('cache_max_books', 0);
    final maxDays = await _getDownloadSettingInt('cache_max_days', 0);
    if (maxBytes <= 0 && maxBooks <= 0 && maxDays <= 0) {
      return;
    }

    final db = await database;
    final nowMs = now.millisecondsSinceEpoch;

    if (maxDays > 0) {
      final cutoffMs =
          now.subtract(Duration(days: maxDays)).millisecondsSinceEpoch;
      await db.delete(
        'web_chapter_cache',
        where: 'last_accessed_at > 0 AND last_accessed_at < ?',
        whereArgs: [cutoffMs],
      );
    }

    final bookRows = await db.rawQuery(
      '''
      SELECT
        ch.web_book_id AS book_id,
        MAX(CASE WHEN c.last_accessed_at > 0 THEN c.last_accessed_at ELSE c.fetched_at END) AS last_at,
        COALESCE(SUM(c.size_bytes), 0) AS bytes
      FROM web_chapter_cache c
      JOIN web_chapters ch ON ch.id = c.chapter_id
      GROUP BY ch.web_book_id
      ORDER BY last_at DESC
      ''',
    );
    if (bookRows.isEmpty) {
      return;
    }

    final books = bookRows
        .map(
          (row) => (
            (row['book_id'] as String? ?? ''),
            (row['last_at'] as int? ?? 0),
            (row['bytes'] as int? ?? 0),
          ),
        )
        .where((tuple) => tuple.$1.trim().isNotEmpty)
        .toList(growable: false);
    if (books.isEmpty) {
      return;
    }

    final toDelete = <String>{};
    if (maxBooks > 0 && books.length > maxBooks) {
      for (final tuple in books.skip(maxBooks)) {
        toDelete.add(tuple.$1);
      }
    }

    if (maxBytes > 0) {
      var totalBytes = 0;
      for (final tuple in books) {
        totalBytes += tuple.$3;
      }
      var cursor = books.length - 1;
      while (totalBytes > maxBytes && cursor >= 0) {
        final bookId = books[cursor].$1;
        if (toDelete.add(bookId)) {
          totalBytes -= books[cursor].$3;
        }
        cursor -= 1;
      }
    }

    if (toDelete.isEmpty) {
      return;
    }

    var deletedChapters = 0;
    for (final bookId in toDelete) {
      deletedChapters += await clearCachedChapters(webBookId: bookId);
      await db.delete(
        WebNovelDownloadManager.tableTasks,
        where: 'web_book_id = ? AND status IN (?, ?)',
        whereArgs: [bookId, 'queued', 'running'],
      );
    }

    await AppRunLogService.instance.logInfo(
      'webnovel cache policy applied: deletedBooks=${toDelete.length}; deletedChapters=$deletedChapters; now=$nowMs',
    );
  }

  @override
  Future<List<WebNovelSearchResult>> searchBooks(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) async {
    final report = await searchBooksWithReport(
      query,
      sourceId: sourceId,
      maxConcurrent: maxConcurrent,
      requiredTags: requiredTags,
      enableQueryExpansion: enableQueryExpansion,
      enableWebFallback: enableWebFallback,
    );
    return report.results;
  }

  @override
  Future<WebNovelSearchReport> searchBooksWithReport(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) async {
    final sources = await listSources();
    var enabled = sources
        .where(
          (item) => item.enabled && (sourceId == null || item.id == sourceId),
        )
        .toList();
    if (sourceId == null && requiredTags.isNotEmpty) {
      final normalizedTags = requiredTags
          .map((tag) => tag.trim().toLowerCase())
          .where((tag) => tag.isNotEmpty)
          .toSet();
      if (normalizedTags.isNotEmpty) {
        enabled = enabled
            .where(
              (source) => source.tags.any(
                (tag) => normalizedTags.contains(tag.toLowerCase()),
              ),
            )
            .toList();
      }
    }

    final failures = <WebNovelSearchFailure>[];
    final failureKeys = <String>{};
    final scopedSourceSearch = sourceId != null;
    final allowWebFallback = enableWebFallback;
    final directCandidates = scopedSourceSearch
        ? enabled
        : _selectDirectSearchCandidates(enabled);

    final directResults = scopedSourceSearch
        ? enabled.isEmpty
              ? const <WebNovelSearchResult>[]
              : await _searchSourceWithReport(
                  enabled.first,
                  query,
                  allowProviderFallback: allowWebFallback,
                  enableQueryExpansion: enableQueryExpansion,
                  failures: failures,
                  failureKeys: failureKeys,
                )
        : await _searchSourcesWithConcurrency(
            directCandidates,
            query,
            maxConcurrent: maxConcurrent,
            useProviderFallback: false,
            enableQueryExpansion: enableQueryExpansion,
            stopWhenEnough: false,
            failures: failures,
            failureKeys: failureKeys,
          );

    final normalizedQuery = query.trim().toLowerCase();
    final normalizedQueryKey = _normalizeSearchKey(query);
    final sourcePriority = <String, int>{
      for (final source in enabled) source.id: source.priority,
    };
    final sourceById = <String, WebNovelSource>{
      for (final source in enabled) source.id: source,
    };
    final dedup = <String, WebNovelSearchResult>{};

    void addResult(WebNovelSearchResult item) {
      final key = _searchResultFingerprint(item);
      final existing = dedup[key];
      if (existing == null) {
        dedup[key] = item;
        return;
      }
      final nextScore =
          _searchResultScore(
            item,
            normalizedQuery: normalizedQuery,
            normalizedQueryKey: normalizedQueryKey,
            source: sourceById[item.sourceId],
          ) +
          (sourcePriority[item.sourceId] ?? 0);
      final existingScore =
          _searchResultScore(
            existing,
            normalizedQuery: normalizedQuery,
            normalizedQueryKey: normalizedQueryKey,
            source: sourceById[existing.sourceId],
          ) +
          (sourcePriority[existing.sourceId] ?? 0);
      if (nextScore > existingScore) {
        dedup[key] = item;
      }
    }

    for (final item in directResults) {
      addResult(item);
    }

    final minimumDesiredResults = scopedSourceSearch ? 12 : 36;
    if (allowWebFallback &&
        !scopedSourceSearch &&
        dedup.length < minimumDesiredResults) {
      final fallbackEligible =
          enabled
              .where((source) => source.search.useSearchProviderFallback)
              .toList(growable: false);
      final fallback = await _searchSourcesByProviderFallbackBulk(
        fallbackEligible,
        query,
        enableQueryExpansion: enableQueryExpansion,
        failures: failures,
        failureKeys: failureKeys,
      );
      for (final item in fallback) {
        addResult(item);
      }
    }

    if (dedup.isEmpty) {
      if (allowWebFallback && scopedSourceSearch && enabled.isNotEmpty) {
        final timeout =
            detectLocalRuntimePlatform() == LocalRuntimePlatform.android
                ? _mobileSearchTimeout
                : _desktopSearchTimeout;
        try {
          final fallback = await _searchSourceByProviderFallback(
            enabled.first,
            query,
            enableQueryExpansion: enableQueryExpansion,
          ).timeout(timeout);
          for (final item in fallback) {
            addResult(item);
          }
        } catch (error, stackTrace) {
          _recordSearchFailure(
            failures: failures,
            failureKeys: failureKeys,
            stage: WebNovelSearchFailureStage.providerFallback,
            error: error,
            source: enabled.first,
          );
          await AppRunLogService.instance.logError(
            'search scoped fallback failed: ${enabled.first.id}; $error\n$stackTrace',
          );
        }
      }
    }

    if (!scopedSourceSearch &&
        dedup.length < (minimumDesiredResults ~/ 2) &&
        directCandidates.length < enabled.length) {
      final selectedIds = {for (final source in directCandidates) source.id};
      final remaining = enabled
          .where((source) => !selectedIds.contains(source.id))
          .toList(growable: false);
      final supplemental = await _searchSourcesWithConcurrency(
        remaining,
        query,
        maxConcurrent: maxConcurrent,
        useProviderFallback: false,
        enableQueryExpansion: enableQueryExpansion,
        stopWhenEnough: false,
        failures: failures,
        failureKeys: failureKeys,
      );
      for (final item in supplemental) {
        addResult(item);
      }
    }

    final ranked = _rankSearchResults(
      results: dedup.values,
      normalizedQuery: normalizedQuery,
      normalizedQueryKey: normalizedQueryKey,
      sourcePriority: sourcePriority,
      sourceById: sourceById,
    );

    return WebNovelSearchReport(
      query: query,
      results: ranked,
      totalSources: enabled.length,
      directCandidates: directCandidates.length,
      failures: failures,
      enableQueryExpansion: enableQueryExpansion,
    );
  }

  @override
  Stream<WebNovelSearchUpdate> searchBooksStream(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) {
    final controller = StreamController<WebNovelSearchUpdate>();
    unawaited(() async {
      final startedAt = DateTime.now();
      final failures = <WebNovelSearchFailure>[];
      final failureKeys = <String>{};
      try {
        await AppRunLogService.instance.logEvent(
          action: 'webnovel.search',
          result: 'start',
          context: <String, Object?>{
            'query': query,
            'source_id': sourceId ?? '',
            'max_concurrent': maxConcurrent,
            'enable_web_fallback': enableWebFallback,
            'required_tags': requiredTags,
          },
        );
        final sources = await listSources();
        var enabled = sources
            .where(
              (item) => item.enabled && (sourceId == null || item.id == sourceId),
            )
            .toList();
        if (sourceId == null && requiredTags.isNotEmpty) {
          final normalizedTags = requiredTags
              .map((tag) => tag.trim().toLowerCase())
              .where((tag) => tag.isNotEmpty)
              .toSet();
          if (normalizedTags.isNotEmpty) {
            enabled = enabled
                .where(
                  (source) => source.tags.any(
                    (tag) => normalizedTags.contains(tag.toLowerCase()),
                  ),
                )
                .toList();
          }
        }

        final scopedSourceSearch = sourceId != null;
        final allowWebFallback = enableWebFallback;
        final directCandidates = scopedSourceSearch
            ? enabled
            : _selectDirectSearchCandidates(enabled);

        final normalizedQuery = query.trim().toLowerCase();
        final normalizedQueryKey = _normalizeSearchKey(query);
        final sourcePriority = <String, int>{
          for (final source in enabled) source.id: source.priority,
        };
        final sourceById = <String, WebNovelSource>{
          for (final source in enabled) source.id: source,
        };
        final dedup = <String, WebNovelSearchResult>{};

        void addResult(WebNovelSearchResult item) {
          final key = _searchResultFingerprint(item);
          final existing = dedup[key];
          if (existing == null) {
            dedup[key] = item;
            return;
          }
          final nextScore =
              _searchResultScore(
                item,
                normalizedQuery: normalizedQuery,
                normalizedQueryKey: normalizedQueryKey,
                source: sourceById[item.sourceId],
              ) +
              (sourcePriority[item.sourceId] ?? 0);
          final existingScore =
              _searchResultScore(
                existing,
                normalizedQuery: normalizedQuery,
                normalizedQueryKey: normalizedQueryKey,
                source: sourceById[existing.sourceId],
              ) +
              (sourcePriority[existing.sourceId] ?? 0);
          if (nextScore > existingScore) {
            dedup[key] = item;
          }
        }

        void emitUpdate({required bool isFinal}) {
          if (controller.isClosed) {
            return;
          }
          final ranked = _rankSearchResults(
            results: dedup.values,
            normalizedQuery: normalizedQuery,
            normalizedQueryKey: normalizedQueryKey,
            sourcePriority: sourcePriority,
            sourceById: sourceById,
          );
          final aggregated = _aggregateSearchResults(
            results: ranked,
            normalizedQuery: normalizedQuery,
            normalizedQueryKey: normalizedQueryKey,
            sourcePriority: sourcePriority,
            sourceById: sourceById,
          );
          controller.add(
            WebNovelSearchUpdate(
              query: query,
              results: ranked,
              aggregatedResults: aggregated,
              totalSources: enabled.length,
              directCandidates: directCandidates.length,
              failures: List<WebNovelSearchFailure>.from(failures),
              enableQueryExpansion: enableQueryExpansion,
              isFinal: isFinal,
            ),
          );
        }

        if (scopedSourceSearch) {
          if (enabled.isNotEmpty) {
            final partial = await _searchSourceWithReport(
              enabled.first,
              query,
              allowProviderFallback: allowWebFallback,
              enableQueryExpansion: enableQueryExpansion,
              failures: failures,
              failureKeys: failureKeys,
            );
            for (final item in partial) {
              addResult(item);
            }
            emitUpdate(isFinal: false);
          }
        } else {
          final queue = Queue<WebNovelSource>.from(directCandidates);
          final workerCount = math.max(1, math.min(maxConcurrent, queue.length));
          final timeout =
              detectLocalRuntimePlatform() == LocalRuntimePlatform.android
                  ? _mobileSearchTimeout
                  : _desktopSearchTimeout;

          Future<void> worker() async {
            while (queue.isNotEmpty) {
              final source = queue.removeFirst();
              try {
                final partial = await _searchSource(
                  source,
                  query,
                  allowProviderFallback: false,
                  enableQueryExpansion: enableQueryExpansion,
                ).timeout(timeout);
                if (partial.isNotEmpty) {
                  for (final item in partial) {
                    addResult(item);
                  }
                  emitUpdate(isFinal: false);
                }
              } catch (error, stackTrace) {
                _recordSearchFailure(
                  failures: failures,
                  failureKeys: failureKeys,
                  stage: WebNovelSearchFailureStage.directSearch,
                  error: error,
                  source: source,
                );
                await AppRunLogService.instance.logError(
                  'search source failed: ${source.id}; $error\n$stackTrace',
                );
              }
            }
          }

          await Future.wait<void>([
            for (var index = 0; index < workerCount; index++) worker(),
          ]);
        }

        final minimumDesiredResults = scopedSourceSearch ? 12 : 36;
        if (allowWebFallback &&
            !scopedSourceSearch &&
            dedup.length < minimumDesiredResults) {
          final fallbackEligible =
              enabled
                  .where((source) => source.search.useSearchProviderFallback)
                  .toList(growable: false);
          final fallback = await _searchSourcesByProviderFallbackBulk(
            fallbackEligible,
            query,
            enableQueryExpansion: enableQueryExpansion,
            failures: failures,
            failureKeys: failureKeys,
          );
          for (final item in fallback) {
            addResult(item);
          }
          emitUpdate(isFinal: false);
        }

        if (dedup.isEmpty) {
          if (allowWebFallback && scopedSourceSearch && enabled.isNotEmpty) {
            final timeout =
                detectLocalRuntimePlatform() == LocalRuntimePlatform.android
                    ? _mobileSearchTimeout
                    : _desktopSearchTimeout;
            try {
              final fallback = await _searchSourceByProviderFallback(
                enabled.first,
                query,
                enableQueryExpansion: enableQueryExpansion,
              ).timeout(timeout);
              for (final item in fallback) {
                addResult(item);
              }
              emitUpdate(isFinal: false);
            } catch (error, stackTrace) {
              _recordSearchFailure(
                failures: failures,
                failureKeys: failureKeys,
                stage: WebNovelSearchFailureStage.providerFallback,
                error: error,
                source: enabled.first,
              );
              await AppRunLogService.instance.logError(
                'search scoped fallback failed: ${enabled.first.id}; $error\n$stackTrace',
              );
            }
          }
        }

        if (!scopedSourceSearch &&
            dedup.length < (minimumDesiredResults ~/ 2) &&
            directCandidates.length < enabled.length) {
          final selectedIds = {for (final source in directCandidates) source.id};
          final remaining = enabled
              .where((source) => !selectedIds.contains(source.id))
              .toList(growable: false);
          final supplemental = await _searchSourcesWithConcurrency(
            remaining,
            query,
            maxConcurrent: maxConcurrent,
            useProviderFallback: false,
            enableQueryExpansion: enableQueryExpansion,
            stopWhenEnough: false,
            failures: failures,
            failureKeys: failureKeys,
          );
          for (final item in supplemental) {
            addResult(item);
          }
          emitUpdate(isFinal: false);
        }

        emitUpdate(isFinal: true);
        await AppRunLogService.instance.logEvent(
          action: 'webnovel.search',
          result: 'ok',
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          context: <String, Object?>{
            'query': query,
            'result_count': dedup.length,
            'failure_count': failures.length,
            'enable_web_fallback': allowWebFallback,
          },
        );
      } catch (error, stackTrace) {
        await AppRunLogService.instance.logError(
          'search stream failed: $query; $error\n$stackTrace',
        );
        await AppRunLogService.instance.logEvent(
          action: 'webnovel.search',
          result: 'error',
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          error: error,
          stackTrace: stackTrace,
          level: 'ERROR',
          context: <String, Object?>{'query': query},
        );
      } finally {
        await controller.close();
      }
    }());
    return controller.stream;
  }

  List<WebNovelSearchResult> _rankSearchResults({
    required Iterable<WebNovelSearchResult> results,
    required String normalizedQuery,
    required String normalizedQueryKey,
    required Map<String, int> sourcePriority,
    required Map<String, WebNovelSource> sourceById,
  }) {
    if (results.isEmpty) {
      return const <WebNovelSearchResult>[];
    }

    int scoreOf(WebNovelSearchResult item) {
      return _searchResultScore(
            item,
            normalizedQuery: normalizedQuery,
            normalizedQueryKey: normalizedQueryKey,
            source: sourceById[item.sourceId],
          ) +
          (sourcePriority[item.sourceId] ?? 0);
    }

    final grouped = <String, List<WebNovelSearchResult>>{};
    for (final item in results) {
      grouped
          .putIfAbsent(_groupKeyForSearchResult(item), () => <WebNovelSearchResult>[])
          .add(item);
    }

    final groupScores = <String, int>{};
    for (final entry in grouped.entries) {
      var maxScore = -1;
      for (final item in entry.value) {
        final score = scoreOf(item);
        if (score > maxScore) {
          maxScore = score;
        }
      }
      groupScores[entry.key] = maxScore;
    }

    final sortedGroupKeys = grouped.keys.toList()
      ..sort((left, right) {
        final rightScore = groupScores[right] ?? 0;
        final leftScore = groupScores[left] ?? 0;
        final scoreDiff = rightScore - leftScore;
        if (scoreDiff != 0) {
          return scoreDiff;
        }
        return left.compareTo(right);
      });

    final ranked = <WebNovelSearchResult>[];
    for (final key in sortedGroupKeys) {
      final bucket = grouped[key] ?? const <WebNovelSearchResult>[];
      final sortedBucket = List<WebNovelSearchResult>.from(bucket)
        ..sort((left, right) {
          final scoreDiff = scoreOf(right) - scoreOf(left);
          if (scoreDiff != 0) {
            return scoreDiff;
          }
          final titleLengthDiff = left.title.length - right.title.length;
          if (titleLengthDiff != 0) {
            return titleLengthDiff;
          }
          return left.title.compareTo(right.title);
        });
      ranked.addAll(sortedBucket);
    }

    return ranked;
  }

  List<WebNovelAggregatedResult> _aggregateSearchResults({
    required Iterable<WebNovelSearchResult> results,
    required String normalizedQuery,
    required String normalizedQueryKey,
    required Map<String, int> sourcePriority,
    required Map<String, WebNovelSource> sourceById,
  }) {
    if (results.isEmpty) {
      return const <WebNovelAggregatedResult>[];
    }

    int scoreOf(WebNovelSearchResult item) {
      return _searchResultScore(
            item,
            normalizedQuery: normalizedQuery,
            normalizedQueryKey: normalizedQueryKey,
            source: sourceById[item.sourceId],
          ) +
          (sourcePriority[item.sourceId] ?? 0);
    }

    final grouped = <String, List<WebNovelSearchResult>>{};
    for (final item in results) {
      grouped
          .putIfAbsent(_groupKeyForSearchResult(item), () => <WebNovelSearchResult>[])
          .add(item);
    }

    final aggregates = <WebNovelAggregatedResult>[];
    final groupScores = <String, int>{};
    for (final entry in grouped.entries) {
      final bucket = List<WebNovelSearchResult>.from(entry.value)
        ..sort((left, right) => scoreOf(right) - scoreOf(left));
      final primary = bucket.first;
      final aliases = <String>{};
      for (final item in bucket) {
        final title = item.title.trim();
        if (title.isNotEmpty && title != primary.title) {
          aliases.add(title);
        }
      }
      aggregates.add(
        WebNovelAggregatedResult(
          key: entry.key,
          title: primary.title,
          author: primary.author,
          coverUrl: primary.coverUrl,
          description: primary.description,
          sources: bucket,
          aliases: aliases.toList(growable: false),
        ),
      );
      groupScores[entry.key] = bucket.isEmpty ? 0 : scoreOf(primary);
    }

    aggregates.sort((left, right) {
      final rightScore = groupScores[right.key] ?? 0;
      final leftScore = groupScores[left.key] ?? 0;
      final scoreDiff = rightScore - leftScore;
      if (scoreDiff != 0) {
        return scoreDiff;
      }
      return left.title.compareTo(right.title);
    });
    return aggregates;
  }

  String _groupKeyForSearchResult(WebNovelSearchResult item) {
    final mergedKey = _normalizeSearchKey('${item.title} ${item.author}');
    if (mergedKey.isNotEmpty) {
      return mergedKey;
    }
    final titleKey = _normalizeSearchKey(item.title);
    if (titleKey.isNotEmpty) {
      return titleKey;
    }
    return item.detailUrl.ifEmpty('${item.sourceId}:${item.title}');
  }

  WebNovelSearchFailureType _classifySearchFailureType(Object error) {
    if (error is TimeoutException) {
      return WebNovelSearchFailureType.timeout;
    }
    if (error is SocketException || error is HandshakeException) {
      return WebNovelSearchFailureType.network;
    }
    if (error is http.ClientException) {
      return WebNovelSearchFailureType.network;
    }
    if (error is HttpException) {
      return WebNovelSearchFailureType.http;
    }
    if (error is FormatException) {
      return WebNovelSearchFailureType.parse;
    }
    return WebNovelSearchFailureType.unknown;
  }

  void _recordSearchFailure({
    required List<WebNovelSearchFailure> failures,
    required Set<String> failureKeys,
    required WebNovelSearchFailureStage stage,
    required Object error,
    WebNovelSource? source,
  }) {
    final type = _classifySearchFailureType(error);
    final message = error.toString();
    final key = '${source?.id ?? ''}|$stage|$type|$message';
    if (!failureKeys.add(key)) {
      return;
    }
    failures.add(
      WebNovelSearchFailure(
        stage: stage,
        type: type,
        message: message,
        sourceId: source?.id ?? '',
        sourceName: source?.name ?? '',
      ),
    );
  }

  Future<List<WebNovelSearchResult>> _searchSourceWithReport(
    WebNovelSource source,
    String query, {
    bool allowProviderFallback = true,
    required bool enableQueryExpansion,
    required List<WebNovelSearchFailure> failures,
    required Set<String> failureKeys,
  }) async {
    final results = <WebNovelSearchResult>[];
    if (!source.fetchViaBrowserOnly && source.search.pathTemplate.isNotEmpty) {
      try {
        results.addAll(await _searchSourceDirect(source, query));
      } catch (error, stackTrace) {
        _recordSearchFailure(
          failures: failures,
          failureKeys: failureKeys,
          stage: WebNovelSearchFailureStage.directSearch,
          error: error,
          source: source,
        );
        await AppRunLogService.instance.logError(
          'search source direct failed: ${source.id}; $error\n$stackTrace',
        );
      }
    }

    if (results.isNotEmpty ||
        !allowProviderFallback ||
        !source.search.useSearchProviderFallback) {
      return results;
    }

    try {
      return await _searchSourceByProviderFallback(
        source,
        query,
        enableQueryExpansion: enableQueryExpansion,
      );
    } catch (error, stackTrace) {
      _recordSearchFailure(
        failures: failures,
        failureKeys: failureKeys,
        stage: WebNovelSearchFailureStage.providerFallback,
        error: error,
        source: source,
      );
      await AppRunLogService.instance.logError(
        'search source provider fallback failed: ${source.id}; $error\n$stackTrace',
      );
      return const <WebNovelSearchResult>[];
    }
  }

  bool _looksLikeBookDetailUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    final path = (uri?.path ?? url).toLowerCase();
    if (path.contains('/book/') || path.contains('/novel/')) {
      return true;
    }
    if (path.endsWith('.html') || path.endsWith('.htm')) {
      return true;
    }
    return RegExp(r'/\d+/?$', caseSensitive: false).hasMatch(path);
  }

  bool _looksLikeSearchOrIndexUrl(String url) {
    final normalized = url.trim().toLowerCase();
    if (normalized.contains('/search') ||
        normalized.contains('search?') ||
        normalized.contains('search=') ||
        normalized.contains('keyword=') ||
        normalized.contains('q=') ||
        normalized.contains('wd=') ||
        normalized.contains('query=')) {
      return true;
    }
    return false;
  }

  bool _detailUrlHostMatchesSource(String detailUrl, WebNovelSource source) {
    final uri = Uri.tryParse(detailUrl.trim());
    if (uri == null || uri.host.isEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase().replaceFirst('www.', '');
    final baseHost =
        Uri.tryParse(source.baseUrl)?.host.toLowerCase().replaceFirst('www.', '') ??
        '';
    if (baseHost.isNotEmpty && host == baseHost) {
      return true;
    }
    for (final domain in source.siteDomains) {
      final normalized = domain.trim().toLowerCase().replaceFirst('www.', '');
      if (normalized.isEmpty) {
        continue;
      }
      if (host == normalized || host.endsWith('.$normalized')) {
        return true;
      }
    }
    return false;
  }

  int _searchResultScore(
    WebNovelSearchResult result, {
    required String normalizedQuery,
    required String normalizedQueryKey,
    WebNovelSource? source,
  }) {
    if (normalizedQueryKey.isEmpty) {
      return 0;
    }
    final title = result.title.toLowerCase();
    final author = result.author.toLowerCase();
    final description = result.description.toLowerCase();
    final titleKey = _normalizeSearchKey(result.title);
    final authorKey = _normalizeSearchKey(result.author);

    var score = 0;
    if (titleKey.isNotEmpty && titleKey == normalizedQueryKey) {
      score += 280;
    } else if (title.contains(normalizedQuery) ||
        (titleKey.isNotEmpty && titleKey.contains(normalizedQueryKey))) {
      score += 180;
    }

    if (author.contains(normalizedQuery) ||
        (authorKey.isNotEmpty && authorKey.contains(normalizedQueryKey))) {
      score += 60;
    }
    if (description.contains(normalizedQuery)) {
      score += 40;
    }

    if (result.origin == WebNovelSearchResultOrigin.direct) {
      score += 160;
    } else {
      score += 40;
    }

    if (_looksLikeBookDetailUrl(result.detailUrl)) {
      score += 40;
    }
    if (_looksLikeSearchOrIndexUrl(result.detailUrl)) {
      score -= 80;
    }

    final matchedSource = source;
    if (matchedSource != null &&
        _detailUrlHostMatchesSource(result.detailUrl, matchedSource)) {
      score += 40;
    }

    return score;
  }

  String _searchResultFingerprint(WebNovelSearchResult result) {
    final titleKey = _normalizeSearchKey(result.title);
    final authorKey = _normalizeSearchKey(result.author);
    final detailKey = _normalizeDetailUrl(result.detailUrl);
    return '$titleKey|$authorKey|$detailKey';
  }

  String _normalizeSearchKey(String raw) {
    if (raw.trim().isEmpty) {
      return '';
    }
    final normalized = raw
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[·•・\-\_]+'), '')
        .replaceAll(RegExp(r'[\\(\\)\\[\\]\\{\\}<>《》“”]+'), '');
    return normalized;
  }

  String _normalizeDetailUrl(String raw) {
    if (raw.trim().isEmpty) {
      return '';
    }
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) {
      return raw.trim().toLowerCase();
    }
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final query = uri.query.trim();
    return query.isEmpty ? '$host$path' : '$host$path?$query';
  }

  List<WebNovelSource> _selectDirectSearchCandidates(
    List<WebNovelSource> sources,
  ) {
    final budget = detectLocalRuntimePlatform() == LocalRuntimePlatform.android
        ? _mobileDirectSearchBudget
        : _allSourcesDirectSearchBudget;
    if (sources.length <= budget) {
      return sources;
    }
    final ranked = List<WebNovelSource>.from(sources)
      ..sort((a, b) => _compareDirectSearchPriority(b, a));
    return ranked.take(budget).toList(growable: false);
  }

  int _compareDirectSearchPriority(WebNovelSource left, WebNovelSource right) {
    final scoreDelta =
        _directSearchPriorityScore(left) - _directSearchPriorityScore(right);
    if (scoreDelta != 0) {
      return scoreDelta;
    }
    return left.name.compareTo(right.name);
  }

  int _directSearchPriorityScore(WebNovelSource source) {
    var score = source.priority;
    if (source.search.pathTemplate.isNotEmpty) {
      score += 4000;
    }
    if (source.search.itemSelector.isNotEmpty) {
      score += 800;
    }
    if (!source.fetchViaBrowserOnly) {
      score += 400;
    }
    if (source.siteDomains.isNotEmpty) {
      score += 120;
    }
    if (source.search.useSearchProviderFallback) {
      score += 80;
    }
    return score;
  }

  Future<List<WebNovelSearchResult>> _searchSourcesWithConcurrency(
    List<WebNovelSource> sources,
    String query, {
    required int maxConcurrent,
    required bool useProviderFallback,
    required bool enableQueryExpansion,
    bool stopWhenEnough = true,
    List<WebNovelSearchFailure>? failures,
    Set<String>? failureKeys,
  }) async {
    if (sources.isEmpty) {
      return const <WebNovelSearchResult>[];
    }

    final queue = Queue<WebNovelSource>.from(sources);
    final results = <WebNovelSearchResult>[];
    final workerCount = math.max(1, math.min(maxConcurrent, queue.length));
    final enoughResults = stopWhenEnough
        ? math.max(24, math.min(sources.length * 6, 180))
        : 0;
    final timeout = detectLocalRuntimePlatform() == LocalRuntimePlatform.android
        ? _mobileSearchTimeout
        : _desktopSearchTimeout;
    var stopRequested = false;

    Future<void> worker() async {
      while (queue.isNotEmpty && !stopRequested) {
        final source = queue.removeFirst();
        try {
          final partial = useProviderFallback
              ? await _searchSourceByProviderFallback(
                  source,
                  query,
                  enableQueryExpansion: enableQueryExpansion,
                ).timeout(timeout)
              : await _searchSource(
                  source,
                  query,
                  allowProviderFallback: false,
                  enableQueryExpansion: enableQueryExpansion,
                ).timeout(timeout);
          if (partial.isEmpty) {
            continue;
          }
          results.addAll(partial);
          if (stopWhenEnough && results.length >= enoughResults) {
            stopRequested = true;
          }
        } catch (error, stackTrace) {
          final scope = useProviderFallback
              ? 'search scoped fallback failed'
              : 'search source failed';
          if (failures != null && failureKeys != null) {
            _recordSearchFailure(
              failures: failures,
              failureKeys: failureKeys,
              stage: useProviderFallback
                  ? WebNovelSearchFailureStage.providerFallback
                  : WebNovelSearchFailureStage.directSearch,
              error: error,
              source: source,
            );
          }
          await AppRunLogService.instance.logError(
            '$scope: ${source.id}; $error\n$stackTrace',
          );
        }
      }
    }

    await Future.wait<void>([
      for (var index = 0; index < workerCount; index++) worker(),
    ]);
    return results;
  }

  @override
  Future<List<WebSearchHit>> webSearch(
    String query, {
    String? providerId,
  }) async {
    final providers = await listSearchProviders();
    final enabled = providers
        .where(
          (item) =>
              item.enabled && (providerId == null || item.id == providerId),
        )
        .toList();
    final results = <WebSearchHit>[];
    for (final provider in enabled) {
      try {
        results.addAll(await _searchProvider(provider, query));
      } catch (error, stackTrace) {
        await AppRunLogService.instance.logError(
          'web search failed: ${provider.id}; $error\n$stackTrace',
        );
      }
    }
    return results;
  }

  @override
  Future<ReaderModeDetectionResult> detectReaderMode(String url) async {
    final startedAt = DateTime.now();
    await AppRunLogService.instance.logEvent(
      action: 'reader_mode.detect',
      result: 'start',
      context: <String, Object?>{'url': url},
    );
    try {
      final article = await readUrl(url);
      final title = article.pageTitle;
      final isLikelyNovel =
          article.detectedTocLinks.isNotEmpty ||
          RegExp(
            r'\u7b2c.{0,12}[\u7ae0\u8282\u56de\u96c6]',
            unicode: true,
          ).hasMatch(title) ||
          RegExp(
            r'\u4e0a\u4e00\u7ae0|\u4e0b\u4e00\u7ae0',
            unicode: true,
          ).hasMatch(article.contentText);
      final detectedBookTitle = _detectReaderModeBookTitle(
        title,
        fallback: article.siteName,
      );
      final detectedChapterTitle = _detectReaderModeChapterTitle(title);
      await AppRunLogService.instance.logEvent(
        action: 'reader_mode.detect',
        result: 'ok',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: <String, Object?>{
          'url': url,
          'toc_count': article.detectedTocLinks.length,
          'confidence': article.confidence,
          'is_likely_novel': isLikelyNovel,
        },
      );
      return ReaderModeDetectionResult(
        article: article,
        isLikelyNovel: isLikelyNovel,
        detectedBookTitle: detectedBookTitle,
        detectedChapterTitle: detectedChapterTitle,
      );
    } catch (error, stackTrace) {
      await AppRunLogService.instance.logEvent(
        action: 'reader_mode.detect',
        result: 'error',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: <String, Object?>{'url': url},
        error: error,
        stackTrace: stackTrace,
        level: 'ERROR',
      );
      rethrow;
    }
  }

  @override
  Future<ReaderModeDetectionResult> detectReaderModeFromHtml({
    required String html,
    required String url,
  }) async {
    final startedAt = DateTime.now();
    await AppRunLogService.instance.logEvent(
      action: 'reader_mode.detect',
      result: 'start',
      context: <String, Object?>{'url': url, 'source': 'webview'},
    );
    try {
      if (html.trim().isEmpty) {
        throw Exception('页面内容为空');
      }
      final requestUrl = Uri.tryParse(url) ?? Uri();
      final document = html_parser.parse(html);
      final article = _extractReaderMode(document, requestUrl);
      await _persistReaderHistory(article);
      final title = article.pageTitle;
      final isLikelyNovel =
          article.detectedTocLinks.isNotEmpty ||
          RegExp(
            r'\u7b2c.{0,12}[\u7ae0\u8282\u56de\u96c6]',
            unicode: true,
          ).hasMatch(title) ||
          RegExp(
            r'\u4e0a\u4e00\u7ae0|\u4e0b\u4e00\u7ae0',
            unicode: true,
          ).hasMatch(article.contentText);
      final detectedBookTitle = _detectReaderModeBookTitle(
        title,
        fallback: article.siteName,
      );
      final detectedChapterTitle = _detectReaderModeChapterTitle(title);
      await AppRunLogService.instance.logEvent(
        action: 'reader_mode.detect',
        result: 'ok',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: <String, Object?>{
          'url': url,
          'source': 'webview',
          'toc_count': article.detectedTocLinks.length,
          'confidence': article.confidence,
          'is_likely_novel': isLikelyNovel,
        },
      );
      return ReaderModeDetectionResult(
        article: article,
        isLikelyNovel: isLikelyNovel,
        detectedBookTitle: detectedBookTitle,
        detectedChapterTitle: detectedChapterTitle,
      );
    } catch (error, stackTrace) {
      await AppRunLogService.instance.logEvent(
        action: 'reader_mode.detect',
        result: 'error',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: <String, Object?>{'url': url, 'source': 'webview'},
        error: error,
        stackTrace: stackTrace,
        level: 'ERROR',
      );
      rethrow;
    }
  }

  Future<ReaderModeArticle> readUrl(String url) async {
    final matchedSource = await findSourceByUrl(url);
    final page = await _requestPage(url, source: matchedSource);
    final article = _extractReaderMode(page.document, page.requestUrl);
    await _persistReaderHistory(article);
    return article;
  }

  @override
  Future<List<ReaderModeArticle>> listReaderHistory() async {
    final db = await database;
    final rows = await db.query(
      'web_reader_history',
      orderBy: 'updated_at DESC',
      limit: 50,
    );
    return rows
        .map(
          (row) => _readerModeFromJson(
            jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  @override
  Future<void> clearReaderHistory() async {
    final db = await database;
    await db.delete('web_reader_history');
  }

  @override
  Future<void> clearReaderHistoryEntry(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final db = await database;
    await db.delete(
      'web_reader_history',
      where: 'url = ?',
      whereArgs: [trimmed],
    );
  }

  @override
  Future<SourceTestResult> testSource(WebNovelSource source) async {
    try {
      final response = await _requestPage(source.baseUrl, source: source);
      if (response.html.trim().isEmpty) {
        return const SourceTestResult(ok: false, message: '返回内容为空');
      }
      if (source.fetchViaBrowserOnly) {
        return const SourceTestResult(
          ok: true,
          message: '站点可连通，但建议在浏览器模式或伴生服务下使用。',
        );
      }
      return SourceTestResult(
        ok: true,
        message: '连通成功：${response.requestUrl.host}',
      );
    } catch (error) {
      return SourceTestResult(ok: false, message: error.toString());
    }
  }

  @override
  Future<AiSourcePatchSuggestion> repairSourceWithAi({
    required WebNovelSource source,
    required String sampleUrl,
    String sampleQuery = '',
    required TranslationConfig? config,
    AiSourceRepairMode mode = AiSourceRepairMode.suggest,
  }) async {
    final trimmedUrl = sampleUrl.trim();
    if (trimmedUrl.isEmpty) {
      throw Exception('缺少样例 URL，无法进行 AI 修复');
    }
    if (config == null || config.baseUrl.trim().isEmpty) {
      throw Exception('缺少有效的 AI API 配置');
    }
    if (mode == AiSourceRepairMode.off) {
      throw Exception('AI 书源修复已关闭');
    }

    final startedAt = DateTime.now();
    await AppRunLogService.instance.logEvent(
      action: 'ai.source_repair',
      result: 'start',
      context: <String, Object?>{
        'source_id': source.id,
        'sample_url': trimmedUrl,
        'mode': mode.storageValue,
      },
    );

    try {
      final page = await _requestPage(trimmedUrl, source: source);
      final htmlSample = _trimAiHtmlSample(page.html);
      final systemPrompt =
          'You are a strict JSON generator for web novel source rule repair. '
          'Output ONLY JSON. Use CSS selectors where possible.';
      final userPrompt =
          'We have a web novel source config in JSON. The rules failed on the sample HTML. '
          'Generate a PATCH JSON that can be merged onto the source config to fix extraction. '
          'Return JSON with fields: patch (partial WebNovelSource JSON), note (string), confidence (0-1).\n\n'
          'Sample URL: $trimmedUrl\n'
          'Sample Query: ${sampleQuery.trim()}\n'
          'Source JSON:\n${jsonEncode(source.toJson())}\n\n'
          'HTML Snippet:\n$htmlSample';

      final raw = await _collectAiResponse(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        config: config,
      );
      final decoded = _extractJsonObject(raw);
      if (decoded == null) {
        throw Exception('AI 返回内容不可解析');
      }
      final patchRaw = decoded['patch'];
      final patch = patchRaw is Map
          ? Map<String, dynamic>.from(patchRaw)
          : Map<String, dynamic>.from(decoded);
      if (patch.isEmpty) {
        throw Exception('AI 未提供可用修复补丁');
      }
      final note = decoded['note']?.toString() ?? '';
      final confidence =
          (decoded['confidence'] as num?)?.toDouble() ?? 0.5;

      final merged = _deepMergeJson(source.toJson(), patch);
      merged['id'] = source.id;
      merged['builtin'] = source.builtin;
      merged['enabled'] = source.enabled;
      final patchedSource = WebNovelSource.fromJson(merged);

      var validationPassed = false;
      var validationMessage = '';
      var applied = false;

      if (mode == AiSourceRepairMode.shadowValidate) {
        final test = await testSource(patchedSource);
        if (!test.ok) {
          validationMessage = test.message;
        } else if (sampleQuery.trim().isNotEmpty &&
            patchedSource.search.pathTemplate.trim().isNotEmpty) {
          try {
            final results = await _searchSourceDirect(
              patchedSource,
              sampleQuery.trim(),
            );
            if (results.isEmpty) {
              validationMessage = '样例搜索无结果';
            } else {
              validationPassed = true;
              validationMessage = '验证通过（命中 ${results.length} 条）';
            }
          } catch (error) {
            validationMessage = '样例搜索失败：$error';
          }
        } else {
          validationPassed = true;
          validationMessage = '验证通过';
        }

        if (validationPassed) {
          await _saveSourceVersion(
            source,
            createdBy: 'ai',
            note: note.isNotEmpty ? note : 'ai_patch',
          );
          await saveSource(patchedSource);
          applied = true;
        }
      }

      final suggestion = AiSourcePatchSuggestion(
        sourceId: source.id,
        patch: patch,
        note: note,
        confidence: confidence,
        rawResponse: raw,
        applied: applied,
        validationPassed: validationPassed,
        validationMessage: validationMessage,
      );

      await AppRunLogService.instance.logEvent(
        action: 'ai.source_repair',
        result: 'ok',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: <String, Object?>{
          'source_id': source.id,
          'applied': applied,
          'validated': validationPassed,
          'mode': mode.storageValue,
        },
      );

      return suggestion;
    } catch (error, stackTrace) {
      await AppRunLogService.instance.logEvent(
        action: 'ai.source_repair',
        result: 'error',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        error: error,
        stackTrace: stackTrace,
        level: 'ERROR',
        context: <String, Object?>{
          'source_id': source.id,
          'sample_url': trimmedUrl,
        },
      );
      rethrow;
    }
  }

  Future<bool> validateSession(String sourceId) async {
    final source = await getSourceById(sourceId);
    final session = await getSessionForSource(sourceId);
    if (source == null || session == null || source.login.checkUrl.isEmpty) {
      return false;
    }

    try {
      final page = await _requestPage(source.login.checkUrl, source: source);
      final ok =
          source.login.loggedInKeyword.isEmpty ||
          page.html.contains(source.login.loggedInKeyword);
      await _saveSession(
        WebSession(
          id: session.id,
          sourceId: session.sourceId,
          domain: session.domain,
          cookiesJson: session.cookiesJson,
          userAgent: session.userAgent,
          updatedAt: session.updatedAt,
          lastVerifiedAt: DateTime.now(),
        ),
      );
      return ok;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<WebNovelBookMeta> addBookFromSearchResult(
    WebNovelSearchResult result,
  ) async {
    final resolved = await _resolveBookDetailForSearchResult(result);
    final source = resolved.source;
    final detail = resolved.detail;
    final webBookId = _uuid.v4();
    final libraryBook = await _libraryService.addManagedWebNovel(
      detail.title,
      remoteBookId: webBookId,
      author: detail.author.isEmpty ? result.author : detail.author,
    );

    final meta = WebNovelBookMeta(
      id: webBookId,
      libraryBookId: libraryBook.id,
      sourceId: source.id,
      title: detail.title,
      author: detail.author.isEmpty ? result.author : detail.author,
      detailUrl: detail.detailUrl,
      originUrl: result.detailUrl,
      coverUrl: detail.coverUrl.isEmpty ? result.coverUrl : detail.coverUrl,
      description: detail.description.isEmpty
          ? result.description
          : detail.description,
      sourceSnapshot: jsonEncode(source.toJson()),
      updatedAt: DateTime.now(),
      chapterSyncStatus: WebChapterSyncStatus.pending,
      chapterSyncError: '',
      chapterSyncRetryCount: 0,
      chapterSyncUpdatedAt: _now(),
    );
    await _upsertBookMeta(meta);
    await _upsertBookSource(
      webBookId: meta.id,
      sourceId: meta.sourceId,
      detailUrl: meta.detailUrl,
      title: meta.title,
      author: meta.author,
      coverUrl: meta.coverUrl,
    );
    await _upsertChapterSyncTask(
      webBookId: meta.id,
      status: _chapterSyncTaskPending,
      attempt: 0,
      nextRetryAt: _now(),
      lastError: '',
    );
    if (_autoSyncOnAdd) {
      unawaited(_runChapterSyncTask(meta.id));
    }
    return meta;
  }

  @override
  Future<WebNovelSearchResult> resolveSearchResultDetail(
    WebNovelSearchResult result,
  ) async {
    final resolved = await _resolveBookDetailForSearchResult(result);
    final detail = resolved.detail;
    return WebNovelSearchResult(
      sourceId: resolved.source.id,
      title: detail.title.isEmpty ? result.title : detail.title,
      detailUrl: detail.detailUrl.isEmpty ? result.detailUrl : detail.detailUrl,
      author: detail.author.isEmpty ? result.author : detail.author,
      coverUrl: detail.coverUrl.isEmpty ? result.coverUrl : detail.coverUrl,
      description:
          detail.description.isEmpty ? result.description : detail.description,
      origin: result.origin,
    );
  }

  @override
  Future<WebNovelBookMeta> addBookFromUrl(String url) async {
    final source = await findSourceByUrl(url);
    if (source == null) {
      return _addBookFromReaderMode(url);
    }
    final detail = await _loadBookDetail(source, url);
    return addBookFromSearchResult(
      WebNovelSearchResult(
        sourceId: source.id,
        title: detail.title,
        detailUrl: detail.detailUrl,
        author: detail.author,
        coverUrl: detail.coverUrl,
        description: detail.description,
      ),
    );
  }

  WebNovelSource _buildReaderModeSource(Uri? originUri) {
    final baseUrl = originUri == null || originUri.host.isEmpty
        ? 'https://reader.mode'
        : originUri.origin;
    return WebNovelSource(
      id: _readerModeSourceId,
      name: '网页阅读',
      baseUrl: baseUrl,
      group: '阅读模式',
      enabled: true,
      builtin: true,
      tags: const <String>['reader_mode'],
      search: const BookSourceSearchRule(
        method: HttpMethod.get,
        pathTemplate: '',
      ),
      chapters: const BookSourceChapterRule(itemSelector: ''),
      content: const BookSourceContentRule(),
    );
  }

  String _trimReaderModeDescription(String text) {
    final cleaned = _cleanText(text);
    if (cleaned.length <= 240) {
      return cleaned;
    }
    return '${cleaned.substring(0, 240)}…';
  }

  String _normalizeReaderModeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(trimmed);
    if (parsed == null) {
      return trimmed;
    }
    final normalized = parsed.replace(fragment: '').toString();
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  WebChapterRecord _buildReaderModeChapterRecord(
    WebNovelBookMeta meta,
    WebNovelSource source,
    String url,
    String title,
    int index,
  ) {
    return WebChapterRecord(
      id: _uuid.v5(Namespace.url.value, '${meta.id}:${source.id}:$url'),
      webBookId: meta.id,
      sourceId: source.id,
      title: title,
      url: url,
      chapterIndex: index,
      updatedAt: DateTime.now(),
    );
  }

  List<WebChapterRecord> _reindexReaderModeChapters(
    List<WebChapterRecord> chapters,
    WebNovelBookMeta meta,
    WebNovelSource source,
  ) {
    return [
      for (var index = 0; index < chapters.length; index++)
        _buildReaderModeChapterRecord(
          meta,
          source,
          chapters[index].url,
          chapters[index].title,
          index,
        ),
    ];
  }

  List<WebChapterRecord> _ensureReaderModeCurrentChapter(
    ReaderModeArticle article,
    WebNovelBookMeta meta,
    WebNovelSource source,
    List<WebChapterRecord> chapters,
  ) {
    final normalizedCurrent = _normalizeReaderModeUrl(article.url);
    final chapterTitle =
        _detectReaderModeChapterTitle(article.pageTitle).ifEmpty(
          article.pageTitle,
        );
    final filtered = chapters
        .where((chapter) => chapter.url.trim().isNotEmpty)
        .toList(growable: true);
    var hasCurrent = false;
    for (var index = 0; index < filtered.length; index++) {
      final chapter = filtered[index];
      if (_normalizeReaderModeUrl(chapter.url) == normalizedCurrent) {
        hasCurrent = true;
        if (chapterTitle.isNotEmpty) {
          filtered[index] = WebChapterRecord(
            id: chapter.id,
            webBookId: chapter.webBookId,
            sourceId: chapter.sourceId,
            title: chapterTitle,
            url: chapter.url,
            chapterIndex: chapter.chapterIndex,
            updatedAt: chapter.updatedAt,
          );
        }
        break;
      }
    }
    if (!hasCurrent && normalizedCurrent.isNotEmpty) {
      filtered.insert(
        0,
        _buildReaderModeChapterRecord(
          meta,
          source,
          article.url,
          chapterTitle.isNotEmpty ? chapterTitle : article.pageTitle,
          0,
        ),
      );
    }
    return _reindexReaderModeChapters(filtered, meta, source);
  }

  Future<List<WebChapterRecord>> _buildReaderModeChapters(
    ReaderModeArticle article,
    WebNovelBookMeta meta,
    WebNovelSource source,
  ) async {
    final candidates = article.detectedTocLinks;
    for (final tocUrl in candidates) {
      try {
        final page = await _requestPage(tocUrl, source: source);
        final extracted = _extractChaptersByHeuristics(
          page: page,
          meta: meta,
          source: source,
        );
        if (extracted.isNotEmpty) {
          return _ensureReaderModeCurrentChapter(
            article,
            meta,
            source,
            extracted,
          );
        }
      } catch (error, stackTrace) {
        await AppRunLogService.instance.logError(
          'reader_mode toc parse failed: $tocUrl; $error\n$stackTrace',
        );
      }
    }
    return _ensureReaderModeCurrentChapter(article, meta, source, const []);
  }

  Future<void> _persistReaderModeChapters(
    WebNovelBookMeta meta,
    List<WebChapterRecord> chapters,
  ) async {
    final db = await database;
    await db.delete(
      'web_chapters',
      where: 'web_book_id = ?',
      whereArgs: [meta.id],
    );
    if (chapters.isEmpty) {
      return;
    }
    final batch = db.batch();
    for (final chapter in chapters) {
      batch.insert('web_chapters', {
        'id': chapter.id,
        'web_book_id': chapter.webBookId,
        'source_id': chapter.sourceId,
        'title': chapter.title,
        'url': chapter.url,
        'chapter_index': chapter.chapterIndex,
        'updated_at': chapter.updatedAt?.millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<void> _cacheReaderModeArticle(
    WebChapterRecord chapter,
    ReaderModeArticle article,
  ) async {
    final now = DateTime.now();
    final text = article.contentText;
    final html = article.contentHtml;
    final sizeBytes = utf8.encode(text).length + utf8.encode(html).length;
    final db = await database;
    await db.insert('web_chapter_cache', {
      'chapter_id': chapter.id,
      'source_id': chapter.sourceId,
      'title': chapter.title,
      'text': text,
      'html': html,
      'fetched_at': now.millisecondsSinceEpoch,
      'is_complete': 1,
      'last_accessed_at': now.millisecondsSinceEpoch,
      'size_bytes': sizeBytes,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<WebNovelBookMeta> _addBookFromReaderMode(String url) async {
    final startedAt = DateTime.now();
    await AppRunLogService.instance.logEvent(
      action: 'reader_mode.add',
      result: 'start',
      context: <String, Object?>{'url': url},
    );
    final article = await readUrl(url);
    final bookTitle = _detectReaderModeBookTitle(
      article.pageTitle,
      fallback: article.siteName,
    ).ifEmpty(article.pageTitle);
    final author =
        article.author.ifEmpty(article.siteName).ifEmpty('网页阅读');
    final webBookId = _uuid.v4();
    final libraryBook = await _libraryService.addManagedWebNovel(
      bookTitle,
      remoteBookId: webBookId,
      author: author,
    );
    final source = _buildReaderModeSource(Uri.tryParse(article.url));
    final detailUrl =
        article.detectedTocLinks.isNotEmpty
            ? article.detectedTocLinks.first
            : article.url;
    final metaSeed = WebNovelBookMeta(
      id: webBookId,
      libraryBookId: libraryBook.id,
      sourceId: source.id,
      title: bookTitle,
      author: author,
      detailUrl: detailUrl,
      originUrl: article.url,
      coverUrl: article.leadImage,
      description: _trimReaderModeDescription(article.contentText),
      sourceSnapshot: jsonEncode(source.toJson()),
      updatedAt: DateTime.now(),
      lastChapterTitle: '',
      chapterSyncStatus: WebChapterSyncStatus.synced,
      chapterSyncError: '',
      chapterSyncRetryCount: 0,
      chapterSyncUpdatedAt: _now(),
    );
    final chapters = await _buildReaderModeChapters(article, metaSeed, source);
    final lastChapterTitle = chapters.isEmpty ? '' : chapters.last.title;
    final meta = WebNovelBookMeta(
      id: metaSeed.id,
      libraryBookId: metaSeed.libraryBookId,
      sourceId: metaSeed.sourceId,
      title: metaSeed.title,
      author: metaSeed.author,
      detailUrl: metaSeed.detailUrl,
      originUrl: metaSeed.originUrl,
      coverUrl: metaSeed.coverUrl,
      description: metaSeed.description,
      sourceSnapshot: metaSeed.sourceSnapshot,
      updatedAt: metaSeed.updatedAt,
      lastChapterTitle: lastChapterTitle,
      chapterSyncStatus: metaSeed.chapterSyncStatus,
      chapterSyncError: metaSeed.chapterSyncError,
      chapterSyncRetryCount: metaSeed.chapterSyncRetryCount,
      chapterSyncUpdatedAt: metaSeed.chapterSyncUpdatedAt,
    );
    await _upsertBookMeta(meta);
    await _upsertBookSource(
      webBookId: meta.id,
      sourceId: meta.sourceId,
      detailUrl: meta.detailUrl,
      title: meta.title,
      author: meta.author,
      coverUrl: meta.coverUrl,
    );
    await _persistReaderModeChapters(meta, chapters);
    if (chapters.isNotEmpty) {
      final normalizedCurrent = _normalizeReaderModeUrl(article.url);
      final current = chapters.firstWhere(
        (chapter) =>
            _normalizeReaderModeUrl(chapter.url) == normalizedCurrent,
        orElse: () => chapters.first,
      );
      await _cacheReaderModeArticle(current, article);
    }
    await AppRunLogService.instance.logEvent(
      action: 'reader_mode.add',
      result: 'ok',
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      context: <String, Object?>{
        'url': url,
        'web_book_id': webBookId,
        'chapter_count': chapters.length,
        'toc_count': article.detectedTocLinks.length,
      },
    );
    return meta;
  }

  Future<_ResolvedBookDetail> _resolveBookDetailForSearchResult(
    WebNovelSearchResult result,
  ) async {
    final candidates = await _buildBookDetailCandidates(result);
    if (candidates.isEmpty) {
      throw Exception('未找到可用于详情解析的书源');
    }

    Object? lastError;
    for (final candidate in candidates) {
      try {
        final detail = await _loadBookDetail(
          candidate.source,
          candidate.detailUrl,
        );
        final title = detail.title.trim();
        final normalizedTitle = title.isEmpty || title == '未命名网文'
            ? result.title
            : detail.title;
        return _ResolvedBookDetail(
          source: candidate.source,
          detail: _BookDetail(
            detailUrl: detail.detailUrl,
            title: normalizedTitle,
            author: detail.author,
            coverUrl: detail.coverUrl,
            description: detail.description,
          ),
        );
      } catch (error, stackTrace) {
        lastError = error;
        await AppRunLogService.instance.logError(
          'addBook detail fallback failed: source=${candidate.source.id}; '
          'url=${candidate.detailUrl}; error=$error\n$stackTrace',
        );
      }
    }

    if (lastError != null) {
      throw Exception('详情获取失败：$lastError');
    }
    throw Exception('详情获取失败：未找到可用规则');
  }

  Future<List<_BookDetailCandidate>> _buildBookDetailCandidates(
    WebNovelSearchResult result,
  ) async {
    final seen = <String>{};
    final candidates = <_BookDetailCandidate>[];
    final primary = await getSourceById(result.sourceId);
    if (primary != null) {
      for (final detailUrl in _detailUrlVariantsForSource(
        primary,
        result.detailUrl,
      )) {
        final key = '${primary.id}::$detailUrl';
        if (seen.add(key)) {
          candidates.add(
            _BookDetailCandidate(source: primary, detailUrl: detailUrl),
          );
        }
      }
    }

    final detailUri = Uri.tryParse(result.detailUrl);
    if (detailUri != null && detailUri.host.isNotEmpty) {
      await listSources();
      for (final source in _sourcesForHost(detailUri.host)) {
        for (final detailUrl in _detailUrlVariantsForSource(
          source,
          result.detailUrl,
        )) {
          final key = '${source.id}::$detailUrl';
          if (seen.add(key)) {
            candidates.add(
              _BookDetailCandidate(source: source, detailUrl: detailUrl),
            );
          }
        }
      }
    }

    return candidates;
  }

  List<String> _detailUrlVariantsForSource(
    WebNovelSource source,
    String detailUrl,
  ) {
    final normalized = detailUrl.trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }

    final variants = <String>{};
    final parsed = Uri.tryParse(normalized);
    final sourceBase = Uri.tryParse(source.baseUrl);
    if (parsed == null) {
      return <String>[normalized];
    }

    if (parsed.hasScheme &&
        (parsed.scheme == 'http' || parsed.scheme == 'https')) {
      variants.add(parsed.toString());
      if (sourceBase != null &&
          sourceBase.host.isNotEmpty &&
          sourceBase.host != parsed.host &&
          parsed.path.isNotEmpty) {
        variants.add(
          sourceBase
              .replace(
                path: parsed.path,
                query: parsed.query.isEmpty ? null : parsed.query,
              )
              .toString(),
        );
      }
      return variants.toList(growable: false);
    }

    if (sourceBase != null) {
      variants.add(sourceBase.resolveUri(parsed).toString());
    }
    variants.add(normalized);
    return variants.toList(growable: false);
  }

  Future<List<Map<String, String>>> listBookSources(String webBookId) async {
    final db = await database;
    final rows = await db.query(
      'web_book_sources',
      where: 'web_book_id = ?',
      whereArgs: [webBookId],
    );
    return rows
        .map(
          (row) => {
            'sourceId': row['source_id'] as String,
            'detailUrl': row['detail_url'] as String,
            'title': row['title'] as String? ?? '',
            'author': row['author'] as String? ?? '',
            'coverUrl': row['cover_url'] as String? ?? '',
          },
        )
        .toList();
  }

  Future<void> switchPrimarySource(String webBookId, String sourceId) async {
    final db = await database;
    final rows = await db.query(
      'web_book_sources',
      where: 'web_book_id = ? AND source_id = ?',
      whereArgs: [webBookId, sourceId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('未找到备用书源');
    }

    final meta = await getBookMeta(webBookId);
    if (meta == null) {
      throw Exception('未找到网文记录');
    }
    final beforeSwitchChapters = await getChapters(webBookId);
    final books = await _libraryService.loadBooks();
    Book? linkedBook;
    for (final item in books) {
      if (item.id == meta.libraryBookId) {
        linkedBook = item;
        break;
      }
    }
    final oldIndex = beforeSwitchChapters.isEmpty
        ? 0
        : (linkedBook?.lastPosition ?? 0).clamp(
            0,
            beforeSwitchChapters.length - 1,
          );
    final oldTitle = beforeSwitchChapters.isEmpty
        ? ''
        : beforeSwitchChapters[oldIndex].title;
    final oldProgress = beforeSwitchChapters.length <= 1
        ? 0.0
        : oldIndex / (beforeSwitchChapters.length - 1);

    await _upsertBookMeta(
      WebNovelBookMeta(
        id: meta.id,
        libraryBookId: meta.libraryBookId,
        sourceId: sourceId,
        title: meta.title,
        author: meta.author,
        detailUrl: rows.first['detail_url'] as String,
        originUrl: meta.originUrl,
        coverUrl: meta.coverUrl,
        description: meta.description,
        lastChapterTitle: meta.lastChapterTitle,
        updatedAt: DateTime.now(),
        sourceSnapshot: meta.sourceSnapshot,
        chapterSyncStatus: meta.chapterSyncStatus,
        chapterSyncError: meta.chapterSyncError,
        chapterSyncRetryCount: meta.chapterSyncRetryCount,
        chapterSyncUpdatedAt: meta.chapterSyncUpdatedAt,
      ),
    );
    final refreshed = await getChapters(webBookId, refresh: true);
    if (refreshed.isEmpty) {
      return;
    }
    var mappedIndex = (oldProgress * (refreshed.length - 1)).round().clamp(
      0,
      refreshed.length - 1,
    );
    final normalizedTitle = _normalizeChapterTitleKey(oldTitle);
    if (normalizedTitle.isNotEmpty) {
      for (var index = 0; index < refreshed.length; index++) {
        if (_normalizeChapterTitleKey(refreshed[index].title) ==
            normalizedTitle) {
          mappedIndex = index;
          break;
        }
      }
    }
    final mappedProgress = refreshed.length <= 1
        ? 0.0
        : mappedIndex / (refreshed.length - 1);
    await _libraryService.updateProgress(
      meta.libraryBookId,
      mappedIndex,
      mappedProgress,
    );
  }

  Future<WebNovelSource?> findSourceByUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return null;
    }
    await listSources();
    for (final source in _sourcesForHost(uri.host)) {
      if (source.siteDomains.any(
        (domain) => uri.host == domain || uri.host.endsWith('.$domain'),
      )) {
        return source;
      }
    }
    return null;
  }

  Future<void> requestChapterSync(
    String webBookId, {
    bool force = false,
  }) async {
    final meta = await getBookMeta(webBookId);
    if (meta == null) {
      return;
    }
    await _upsertChapterSyncTask(
      webBookId: webBookId,
      status: _chapterSyncTaskPending,
      attempt: force ? 0 : meta.chapterSyncRetryCount,
      nextRetryAt: _now(),
      lastError: force ? '' : meta.chapterSyncError,
    );
    if (force) {
      await _runChapterSyncTask(webBookId, force: true);
      return;
    }
    unawaited(_runChapterSyncTask(webBookId));
  }

  Future<String> describeChapterSyncState(String webBookId) async {
    final meta = await getBookMeta(webBookId);
    if (meta == null) {
      return '未找到网文记录';
    }
    final retry = meta.chapterSyncRetryCount;
    switch (meta.chapterSyncStatus) {
      case WebChapterSyncStatus.synced:
        final lastChapter = meta.lastChapterTitle.trim();
        if (lastChapter.isNotEmpty) {
          return '目录已拉取：$lastChapter';
        }
        return retry > 0 ? '目录已拉取（重试后成功）' : '目录已拉取';
      case WebChapterSyncStatus.stale:
        final error = meta.chapterSyncError.trim();
        if (error.isEmpty) {
          return '目录状态失效，请重试获取章节';
        }
        return '目录状态失效：$error';
      case WebChapterSyncStatus.pending:
        final error = meta.chapterSyncError.trim();
        if (retry <= 0) {
          return '目录正在获取中，请稍后重试';
        }
        if (error.isEmpty) {
          return '目录正在重试中（已重试 $retry 次）';
        }
        return '目录正在重试中（已重试 $retry 次）：$error';
    }
  }

  void _resumePendingChapterSyncTasks() {
    unawaited(() async {
      final tasks = await _listDueChapterSyncTasks();
      for (final task in tasks) {
        unawaited(_runChapterSyncTask(task.webBookId));
      }
    }());
  }

  Future<List<_ChapterSyncTask>> _listDueChapterSyncTasks() async {
    final db = await database;
    final now = _now().millisecondsSinceEpoch;
    final rows = await db.query(
      'web_chapter_sync_tasks',
      where: '(status = ? OR status = ? OR status = ?) AND next_retry_at <= ?',
      whereArgs: [
        _chapterSyncTaskPending,
        _chapterSyncTaskRetrying,
        _chapterSyncTaskRunning,
        now,
      ],
      orderBy: 'next_retry_at ASC',
      limit: 64,
    );
    return rows.map(_chapterSyncTaskFromRow).toList(growable: false);
  }

  Future<_ChapterSyncTask?> _getChapterSyncTask(String webBookId) async {
    final db = await database;
    final rows = await db.query(
      'web_chapter_sync_tasks',
      where: 'web_book_id = ?',
      whereArgs: [webBookId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return _chapterSyncTaskFromRow(rows.first);
  }

  _ChapterSyncTask _chapterSyncTaskFromRow(Map<String, Object?> row) {
    return _ChapterSyncTask(
      webBookId: row['web_book_id'] as String,
      status: row['status'] as String? ?? _chapterSyncTaskPending,
      attempt: row['attempt'] as int? ?? 0,
      nextRetryAt: DateTime.fromMillisecondsSinceEpoch(
        row['next_retry_at'] as int? ?? 0,
      ),
      lastError: row['last_error'] as String? ?? '',
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row['updated_at'] as int? ?? 0,
      ),
    );
  }

  Future<void> _upsertChapterSyncTask({
    required String webBookId,
    required String status,
    required int attempt,
    required DateTime nextRetryAt,
    required String lastError,
  }) async {
    final db = await database;
    await db.insert('web_chapter_sync_tasks', {
      'web_book_id': webBookId,
      'status': status,
      'attempt': attempt,
      'next_retry_at': nextRetryAt.millisecondsSinceEpoch,
      'last_error': lastError,
      'updated_at': _now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _deleteChapterSyncTask(String webBookId) async {
    final db = await database;
    await db.delete(
      'web_chapter_sync_tasks',
      where: 'web_book_id = ?',
      whereArgs: [webBookId],
    );
  }

  Future<void> _updateChapterSyncState({
    required String webBookId,
    required WebChapterSyncStatus status,
    required int retryCount,
    required String error,
  }) async {
    final db = await database;
    await db.update(
      'web_books',
      {
        'chapter_sync_status': status.storageValue,
        'chapter_sync_retry_count': retryCount,
        'chapter_sync_error': error,
        'chapter_sync_updated_at': _now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [webBookId],
    );
  }

  Future<List<_BookSourceCandidate>> _buildChapterSyncCandidates(
    WebNovelBookMeta meta,
  ) async {
    final candidates = <_BookSourceCandidate>[];
    final seen = <String>{};

    final primarySource = await _sourceForMeta(meta);
    if (primarySource != null && meta.detailUrl.trim().isNotEmpty) {
      final key = '${primarySource.id}::${meta.detailUrl.trim()}';
      if (seen.add(key)) {
        candidates.add(
          _BookSourceCandidate(
            source: primarySource,
            detailUrl: meta.detailUrl.trim(),
          ),
        );
      }
    }

    final rows = await listBookSources(meta.id);
    for (final row in rows) {
      final sourceId = row['sourceId']?.trim() ?? '';
      final detailUrl = row['detailUrl']?.trim() ?? '';
      if (sourceId.isEmpty || detailUrl.isEmpty) {
        continue;
      }
      final source = await getSourceById(sourceId);
      if (source == null) {
        continue;
      }
      final key = '${source.id}::$detailUrl';
      if (!seen.add(key)) {
        continue;
      }
      candidates.add(
        _BookSourceCandidate(source: source, detailUrl: detailUrl),
      );
    }

    return candidates;
  }

  Future<void> _runChapterSyncTask(
    String webBookId, {
    bool force = false,
  }) async {
    if (!_chapterSyncInFlight.add(webBookId)) {
      return;
    }
    try {
      final meta = await getBookMeta(webBookId);
      if (meta == null) {
        await _deleteChapterSyncTask(webBookId);
        return;
      }

      final task = await _getChapterSyncTask(webBookId);
      if (task == null) {
        if (!force) {
          return;
        }
        await _upsertChapterSyncTask(
          webBookId: webBookId,
          status: _chapterSyncTaskPending,
          attempt: 0,
          nextRetryAt: _now(),
          lastError: '',
        );
      } else if (!force) {
        if (task.status == _chapterSyncTaskFailed ||
            task.nextRetryAt.isAfter(_now())) {
          return;
        }
      }

      final candidates = await _buildChapterSyncCandidates(meta);
      if (candidates.isEmpty) {
        await _upsertChapterSyncTask(
          webBookId: webBookId,
          status: _chapterSyncTaskFailed,
          attempt: _chapterSyncMaxAttempts,
          nextRetryAt: _now(),
          lastError: '未找到可用书源或目录地址',
        );
        await _updateChapterSyncState(
          webBookId: webBookId,
          status: WebChapterSyncStatus.stale,
          retryCount: _chapterSyncMaxAttempts,
          error: '未找到可用书源或目录地址',
        );
        return;
      }

      var attempt = force ? 0 : (task?.attempt ?? meta.chapterSyncRetryCount);
      var lastError = task?.lastError ?? '';

      while (attempt < _chapterSyncMaxAttempts) {
        final candidate = candidates[attempt % candidates.length];
        final workingMeta = WebNovelBookMeta(
          id: meta.id,
          libraryBookId: meta.libraryBookId,
          sourceId: candidate.source.id,
          title: meta.title,
          author: meta.author,
          detailUrl: candidate.detailUrl,
          originUrl: meta.originUrl,
          coverUrl: meta.coverUrl,
          description: meta.description,
          lastChapterTitle: meta.lastChapterTitle,
          updatedAt: _now(),
          sourceSnapshot: jsonEncode(candidate.source.toJson()),
          chapterSyncStatus: WebChapterSyncStatus.pending,
          chapterSyncError: lastError,
          chapterSyncRetryCount: attempt,
          chapterSyncUpdatedAt: _now(),
        );

        await _upsertChapterSyncTask(
          webBookId: webBookId,
          status: _chapterSyncTaskRunning,
          attempt: attempt,
          nextRetryAt: _now(),
          lastError: lastError,
        );
        await _updateChapterSyncState(
          webBookId: webBookId,
          status: WebChapterSyncStatus.pending,
          retryCount: attempt,
          error: lastError,
        );

        try {
          final chapters = await _syncChapters(workingMeta, candidate.source);
          if (chapters.isEmpty) {
            throw Exception('未解析到可阅读章节');
          }
          await _deleteChapterSyncTask(webBookId);
          await _updateChapterSyncState(
            webBookId: webBookId,
            status: WebChapterSyncStatus.synced,
            retryCount: attempt,
            error: '',
          );
          return;
        } catch (error, stackTrace) {
          lastError = error.toString();
          await AppRunLogService.instance.logError(
            'webnovel chapter sync failed: $webBookId; '
            'attempt=${attempt + 1}; source=${candidate.source.id}; '
            'error=$error\n$stackTrace',
          );
        }

        attempt += 1;
        if (attempt >= _chapterSyncMaxAttempts) {
          break;
        }

        final delay = Duration(seconds: math.max(1, 1 << (attempt - 1)));
        await _upsertChapterSyncTask(
          webBookId: webBookId,
          status: _chapterSyncTaskRetrying,
          attempt: attempt,
          nextRetryAt: _now().add(delay),
          lastError: lastError,
        );
        await _updateChapterSyncState(
          webBookId: webBookId,
          status: WebChapterSyncStatus.pending,
          retryCount: attempt,
          error: lastError,
        );
        await _retryDelay(delay);
      }

      await _upsertChapterSyncTask(
        webBookId: webBookId,
        status: _chapterSyncTaskFailed,
        attempt: _chapterSyncMaxAttempts,
        nextRetryAt: _now(),
        lastError: lastError,
      );
      await _updateChapterSyncState(
        webBookId: webBookId,
        status: WebChapterSyncStatus.stale,
        retryCount: _chapterSyncMaxAttempts,
        error: lastError,
      );
    } finally {
      _chapterSyncInFlight.remove(webBookId);
    }
  }

  WebChapterRecord _chapterFromRow(Map<String, Object?> row) =>
      WebChapterRecord(
        id: row['id'] as String,
        webBookId: row['web_book_id'] as String,
        sourceId: row['source_id'] as String,
        title: row['title'] as String,
        url: row['url'] as String,
        chapterIndex: row['chapter_index'] as int,
        updatedAt: row['updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );

  Future<WebNovelSource?> _sourceForMeta(WebNovelBookMeta meta) async {
    if (meta.sourceSnapshot.isNotEmpty) {
      try {
        return WebNovelSource.fromJson(
          jsonDecode(meta.sourceSnapshot) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    if (meta.sourceId.isNotEmpty) {
      return getSourceById(meta.sourceId);
    }
    return null;
  }

  Future<List<WebChapterRecord>> _syncChapters(
    WebNovelBookMeta meta,
    WebNovelSource source,
  ) async {
    final page = await _requestPage(meta.detailUrl, source: source);
    final nodes = _selectSourceItems(page, source.chapters.itemSelector);
    var chapters = _extractRuleBasedChapters(
      page: page,
      nodes: nodes,
      meta: meta,
      source: source,
    );

    if (chapters.isEmpty) {
      chapters = _extractChaptersByHeuristics(
        page: page,
        meta: meta,
        source: source,
      );
    }
    if (chapters.isEmpty) {
      throw Exception('未解析到可阅读章节');
    }

    final dedupByUrl = <String, WebChapterRecord>{};
    for (final chapter in chapters) {
      dedupByUrl[chapter.url] = chapter;
    }

    chapters = dedupByUrl.values.toList(growable: false);
    final ordered = source.chapters.reverse
        ? chapters.reversed.toList()
        : chapters;
    final db = await database;
    final oldChapterRows = await db.query(
      'web_chapters',
      where: 'web_book_id = ?',
      whereArgs: [meta.id],
      orderBy: 'chapter_index ASC',
    );
    final oldTitleById = <String, String>{
      for (final row in oldChapterRows)
        row['id'] as String: row['title'] as String? ?? '',
    };
    final oldChapterIds = oldChapterRows
        .map((row) => row['id'] as String)
        .where((id) => id.trim().isNotEmpty)
        .toList(growable: false);
    final oldCacheByChapterId = <String, Map<String, Object?>>{};
    if (oldChapterIds.isNotEmpty) {
      final placeholders = List.filled(oldChapterIds.length, '?').join(', ');
      final cachedRows = await db.query(
        'web_chapter_cache',
        where: 'chapter_id IN ($placeholders)',
        whereArgs: oldChapterIds,
      );
      for (final row in cachedRows) {
        final chapterId = row['chapter_id'] as String? ?? '';
        if (chapterId.isEmpty) {
          continue;
        }
        oldCacheByChapterId[chapterId] = row;
      }
    }

    await db.delete(
      'web_chapters',
      where: 'web_book_id = ?',
      whereArgs: [meta.id],
    );
    final batch = db.batch();
    for (var index = 0; index < ordered.length; index++) {
      final chapter = ordered[index];
      batch.insert('web_chapters', {
        'id': chapter.id,
        'web_book_id': chapter.webBookId,
        'source_id': chapter.sourceId,
        'title': chapter.title,
        'url': chapter.url,
        'chapter_index': index,
        'updated_at': chapter.updatedAt?.millisecondsSinceEpoch,
      });
    }
    await batch.commit(noResult: true);

    final newChapterIds = ordered.map((item) => item.id).toSet();
    final staleOldIds = oldChapterIds
        .where((chapterId) => !newChapterIds.contains(chapterId))
        .toList(growable: false);

    final reusedCachePool = <String, List<Map<String, Object?>>>{};
    for (final chapterId in staleOldIds) {
      final oldCache = oldCacheByChapterId[chapterId];
      if (oldCache == null) {
        continue;
      }
      final normalizedTitle = _normalizeChapterTitleKey(
        oldTitleById[chapterId] ?? '',
      );
      if (normalizedTitle.isEmpty) {
        continue;
      }
      reusedCachePool
          .putIfAbsent(normalizedTitle, () => <Map<String, Object?>>[])
          .add(oldCache);
    }

    for (final chapter in ordered) {
      if (oldCacheByChapterId.containsKey(chapter.id)) {
        continue;
      }
      final normalizedTitle = _normalizeChapterTitleKey(chapter.title);
      if (normalizedTitle.isEmpty) {
        continue;
      }
      final candidates = reusedCachePool[normalizedTitle];
      if (candidates == null || candidates.isEmpty) {
        continue;
      }
      final reused = candidates.removeAt(0);
      await db.insert('web_chapter_cache', {
        'chapter_id': chapter.id,
        'source_id': chapter.sourceId,
        'title': chapter.title,
        'text': reused['text'] as String? ?? '',
        'html': reused['html'] as String? ?? '',
        'fetched_at':
            reused['fetched_at'] as int? ?? _now().millisecondsSinceEpoch,
        'is_complete': reused['is_complete'] as int? ?? 1,
        'last_accessed_at':
            (reused['last_accessed_at'] as int?) ??
            (reused['fetched_at'] as int?) ??
            0,
        'size_bytes': reused['size_bytes'] as int? ?? 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    if (staleOldIds.isNotEmpty) {
      final placeholders = List.filled(staleOldIds.length, '?').join(', ');
      await db.delete(
        'web_chapter_cache',
        where: 'chapter_id IN ($placeholders)',
        whereArgs: staleOldIds,
      );
    }

    await _upsertBookMeta(
      WebNovelBookMeta(
        id: meta.id,
        libraryBookId: meta.libraryBookId,
        sourceId: meta.sourceId,
        title: meta.title,
        author: meta.author,
        detailUrl: meta.detailUrl,
        originUrl: meta.originUrl,
        coverUrl: meta.coverUrl,
        description: meta.description,
        lastChapterTitle: ordered.isEmpty
            ? meta.lastChapterTitle
            : ordered.last.title,
        updatedAt: DateTime.now(),
        sourceSnapshot: jsonEncode(source.toJson()),
        chapterSyncStatus: meta.chapterSyncStatus,
        chapterSyncError: meta.chapterSyncError,
        chapterSyncRetryCount: meta.chapterSyncRetryCount,
        chapterSyncUpdatedAt: _now(),
      ),
    );

    return ordered;
  }

  List<WebChapterRecord> _extractRuleBasedChapters({
    required _FetchedPage page,
    required List<Object?> nodes,
    required WebNovelBookMeta meta,
    required WebNovelSource source,
  }) {
    if (nodes.isEmpty) {
      return const <WebChapterRecord>[];
    }

    final chapters = <WebChapterRecord>[];
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      final title = _extractRuleValue(
        node,
        source.chapters.titleRule,
        baseUri: page.requestUrl,
      ).ifEmpty(_fallbackReadableText(node));
      final url = _extractRuleValue(
        node,
        source.chapters.urlRule,
        baseUri: page.requestUrl,
      );
      if (title.isEmpty || url.isEmpty) {
        continue;
      }
      chapters.add(
        WebChapterRecord(
          id: _uuid.v5(Namespace.url.value, '${meta.id}:${source.id}:$url'),
          webBookId: meta.id,
          sourceId: source.id,
          title: title,
          url: url,
          chapterIndex: index,
          updatedAt: DateTime.now(),
        ),
      );
    }
    return chapters;
  }

  List<WebChapterRecord> _extractChaptersByHeuristics({
    required _FetchedPage page,
    required WebNovelBookMeta meta,
    required WebNovelSource source,
  }) {
    final chapters = <WebChapterRecord>[];
    final seenUrls = <String>{};
    var index = 0;

    for (final anchor in page.document.querySelectorAll('a[href]')) {
      final rawHref = anchor.attributes['href'] ?? '';
      final url = _resolveUrl(page.requestUrl, rawHref);
      if (url.isEmpty || !seenUrls.add(url)) {
        continue;
      }
      final title = _cleanText(anchor.text);
      if (!_looksLikeChapterLink(title: title, url: url)) {
        continue;
      }
      chapters.add(
        WebChapterRecord(
          id: _uuid.v5(Namespace.url.value, '${meta.id}:${source.id}:$url'),
          webBookId: meta.id,
          sourceId: source.id,
          title: title,
          url: url,
          chapterIndex: index,
          updatedAt: DateTime.now(),
        ),
      );
      index += 1;
      if (chapters.length >= 5000) {
        break;
      }
    }

    if (chapters.length < 3) {
      return const <WebChapterRecord>[];
    }
    return chapters;
  }

  bool _looksLikeChapterLink({required String title, required String url}) {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty || normalizedTitle.length > 80) {
      return false;
    }
    if (RegExp(
      r'目录|返回|上一页|下一页|首页|书架|加入|推荐|版权|登录|注册|下载',
      unicode: true,
    ).hasMatch(normalizedTitle)) {
      return false;
    }
    if (RegExp(
      r'第.{0,18}[章节回卷集]|番外|楔子|序章|后记|chapter\s*\d+|chap\.?\s*\d+',
      caseSensitive: false,
      unicode: true,
    ).hasMatch(normalizedTitle)) {
      return true;
    }
    return RegExp(
      r'(/chapter/|/chap/|/read/|/book/\d+/\d+|/\d+[_-]\d+\.html|/\d+\.html)',
      caseSensitive: false,
    ).hasMatch(url);
  }

  Future<List<WebNovelSearchResult>> _searchSource(
    WebNovelSource source,
    String query, {
    bool allowProviderFallback = true,
    bool enableQueryExpansion = true,
  }) async {
    final results = <WebNovelSearchResult>[];
    if (!source.fetchViaBrowserOnly && source.search.pathTemplate.isNotEmpty) {
      results.addAll(await _searchSourceDirect(source, query));
    }
    if (results.isNotEmpty ||
        !allowProviderFallback ||
        !source.search.useSearchProviderFallback) {
      return results;
    }
    return _searchSourceByProviderFallback(
      source,
      query,
      enableQueryExpansion: enableQueryExpansion,
    );
  }

  Future<List<WebNovelSearchResult>> _searchSourceDirect(
    WebNovelSource source,
    String query,
  ) async {
    final path = source.search.pathTemplate.replaceAll(
      '{query}',
      Uri.encodeComponent(query),
    );
    final url = _resolveUrl(Uri.parse(source.baseUrl), path);
    final body = source.search.method == HttpMethod.post
        ? {source.search.queryField: query}
        : null;
    final page = await _requestPage(
      url,
      source: source,
      method: source.search.method,
      bodyFields: body,
      timeout: const Duration(seconds: 10),
    );

    final results = <WebNovelSearchResult>[];
    for (final node in _selectSourceItems(page, source.search.itemSelector)) {
      final title = _extractRuleValue(
        node,
        source.search.titleRule,
        baseUri: page.requestUrl,
      ).ifEmpty(_fallbackReadableText(node));
      final detailUrl = _extractRuleValue(
        node,
        source.search.urlRule,
        baseUri: page.requestUrl,
      );
      if (title.isEmpty || detailUrl.isEmpty) {
        continue;
      }
      results.add(
        WebNovelSearchResult(
          sourceId: source.id,
          title: title,
          detailUrl: detailUrl,
          author: _extractRuleValue(
            node,
            source.search.authorRule,
            baseUri: page.requestUrl,
          ),
          coverUrl: _extractRuleValue(
            node,
            source.search.coverRule,
            baseUri: page.requestUrl,
          ),
          description: _extractRuleValue(
            node,
            source.search.descriptionRule,
            baseUri: page.requestUrl,
          ),
          origin: WebNovelSearchResultOrigin.direct,
        ),
      );
      if (results.length >= 12) {
        break;
      }
    }
    return results;
  }

  Future<List<WebNovelSearchResult>> _searchSourceByProviderFallback(
    WebNovelSource source,
    String query, {
    bool enableQueryExpansion = true,
  }) async {
    final providers = await listSearchProviders();
    final domain = source.siteDomains.isEmpty
        ? Uri.parse(source.baseUrl).host
        : source.siteDomains.first;
    final results = <WebNovelSearchResult>[];
    final domainToken = domain.replaceFirst('www.', '');
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const <WebNovelSearchResult>[];
    }
    final triedQueries = enableQueryExpansion
        ? <String>[
            '$trimmedQuery 小说 site:$domainToken',
            '$trimmedQuery site:$domainToken',
            '$trimmedQuery 小说 $domainToken',
            '$trimmedQuery $domainToken',
            '$trimmedQuery ${source.name}',
            trimmedQuery,
          ]
        : <String>[trimmedQuery];

    for (final provider in providers.where((item) => item.enabled)) {
      for (final searchQuery in triedQueries) {
        final hits = await _searchProvider(provider, searchQuery);
        for (final hit in hits) {
          if (!_looksLikeSourceHit(hit, source)) {
            continue;
          }
          if (!_looksLikeBookDetailUrl(hit.url) ||
              _looksLikeSearchOrIndexUrl(hit.url)) {
            continue;
          }
          results.add(
            WebNovelSearchResult(
              sourceId: source.id,
              title: hit.title,
              detailUrl: hit.url,
              description: hit.snippet,
              origin: WebNovelSearchResultOrigin.providerFallback,
            ),
          );
        }
        if (results.isNotEmpty) {
          break;
        }
      }
      if (results.isNotEmpty) {
        break;
      }
    }
    return results;
  }

  Future<List<WebNovelSearchResult>> _searchSourcesByProviderFallbackBulk(
    List<WebNovelSource> sources,
    String query, {
    bool enableQueryExpansion = true,
    List<WebNovelSearchFailure>? failures,
    Set<String>? failureKeys,
  }) async {
    if (sources.isEmpty) {
      return const <WebNovelSearchResult>[];
    }
    final enabledProviders = (await listSearchProviders())
        .where((item) => item.enabled)
        .toList(growable: false);
    final customProviders = enabledProviders
        .where((item) => !item.builtin)
        .toList(growable: false);
    final providers = customProviders.isNotEmpty
        ? customProviders
        : enabledProviders;
    if (providers.isEmpty) {
      return const <WebNovelSearchResult>[];
    }

    final allowed = {for (final source in sources) source.id: source};
    final dedup = <String, WebNovelSearchResult>{};
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return const <WebNovelSearchResult>[];
    }
    final queries = enableQueryExpansion
        ? <String>['$trimmedQuery 小说', trimmedQuery]
        : <String>[trimmedQuery];
    final enoughResults = math.max(1, math.min(sources.length, 24));

    for (final provider in providers) {
      for (final searchQuery in queries) {
        try {
          final hits = await _searchProvider(provider, searchQuery);
          for (final hit in hits) {
            final source = _matchSourceForHit(hit, allowed);
            if (source == null) {
              continue;
            }
            if (!_looksLikeBookDetailUrl(hit.url) ||
                _looksLikeSearchOrIndexUrl(hit.url)) {
              continue;
            }
            dedup['${source.id}:${hit.url}'] = WebNovelSearchResult(
              sourceId: source.id,
              title: hit.title,
              detailUrl: hit.url,
              description: hit.snippet,
              origin: WebNovelSearchResultOrigin.providerFallback,
            );
          }
          if (dedup.length >= enoughResults) {
            return dedup.values.toList(growable: false);
          }
        } catch (error, stackTrace) {
          if (failures != null && failureKeys != null) {
            _recordSearchFailure(
              failures: failures,
              failureKeys: failureKeys,
              stage: WebNovelSearchFailureStage.providerBulkFallback,
              error: error,
            );
          }
          await AppRunLogService.instance.logError(
            'bulk provider fallback failed: ${provider.id}; query=$searchQuery; $error\n$stackTrace',
          );
        }
      }
    }
    return dedup.values.toList(growable: false);
  }

  WebNovelSource? _matchSourceForHit(
    WebSearchHit hit,
    Map<String, WebNovelSource> allowed,
  ) {
    final uri = Uri.tryParse(hit.url);
    if (uri != null) {
      for (final candidate in _sourcesForHost(uri.host)) {
        final source = allowed[candidate.id];
        if (source != null && _looksLikeSourceHit(hit, source)) {
          return source;
        }
      }
    }

    for (final source in allowed.values) {
      if (_looksLikeSourceHit(hit, source)) {
        return source;
      }
    }
    return null;
  }

  Future<List<WebSearchHit>> _searchProvider(
    WebSearchProvider provider,
    String query,
  ) async {
    final url = provider.searchUrlTemplate.replaceAll(
      '{query}',
      Uri.encodeComponent(query),
    );
    final page = await _requestPage(
      url,
      extraHeaders: provider.headers,
      userAgentOverride: provider.userAgent,
      timeout: const Duration(seconds: 10),
    );

    final results = <WebSearchHit>[];
    for (final node in page.document.querySelectorAll(
      provider.resultListSelector,
    )) {
      final title = _extractLooseValue(
        node,
        provider.resultTitleSelector,
        baseUri: page.requestUrl,
      );
      final link = _extractLooseValue(
        node,
        provider.resultUrlSelector,
        baseUri: page.requestUrl,
      );
      if (title.isEmpty || link.isEmpty) {
        continue;
      }
      results.add(
        WebSearchHit(
          providerId: provider.id,
          providerName: provider.name,
          title: title,
          url: link,
          snippet: _extractLooseValue(
            node,
            provider.resultSnippetSelector,
            baseUri: page.requestUrl,
          ),
        ),
      );
    }
    return results;
  }

  Future<_BookDetail> _loadBookDetail(
    WebNovelSource source,
    String detailUrl,
  ) async {
    final page = await _requestPage(detailUrl, source: source);
    final normalizedPage = await _normalizeDetailPage(source, page);
    final root = _pageRootValue(normalizedPage);
    return _BookDetail(
      detailUrl: normalizedPage.requestUrl.toString(),
      title:
          _extractRuleValue(
            root,
            source.detail.titleRule,
            baseUri: normalizedPage.requestUrl,
          ).ifEmpty(
            normalizedPage.document.querySelector('h1')?.text.trim() ?? '未命名网文',
          ),
      author: _extractRuleValue(
        root,
        source.detail.authorRule,
        baseUri: normalizedPage.requestUrl,
      ),
      coverUrl: _extractRuleValue(
        root,
        source.detail.coverRule,
        baseUri: normalizedPage.requestUrl,
      ),
      description: _extractRuleValue(
        root,
        source.detail.descriptionRule,
        baseUri: normalizedPage.requestUrl,
      ),
    );
  }

  Future<_FetchedPage> _normalizeDetailPage(
    WebNovelSource source,
    _FetchedPage page,
  ) async {
    final hasChapterList =
        source.chapters.itemSelector.trim().isNotEmpty &&
        _selectSourceItems(page, source.chapters.itemSelector).isNotEmpty;
    if (hasChapterList) {
      return page;
    }

    final root = _pageRootValue(page);
    final candidates = <String>{
      _extractRuleValue(
        root,
        source.detail.chapterListUrlRule,
        baseUri: page.requestUrl,
      ),
      ...page.document
          .querySelectorAll('a')
          .where(
            (link) => RegExp(
              r'目录|章节目录|全部章节|返回目录|书页|详情',
              unicode: true,
            ).hasMatch(link.text),
          )
          .map(
            (link) =>
                _resolveUrl(page.requestUrl, link.attributes['href'] ?? ''),
          ),
    }.where((item) => item.isNotEmpty).toSet();

    for (final candidate in candidates) {
      if (candidate == page.requestUrl.toString()) {
        continue;
      }
      try {
        final nextPage = await _requestPage(candidate, source: source);
        final nextRoot = _pageRootValue(nextPage);
        final nextHasChapterList =
            source.chapters.itemSelector.trim().isNotEmpty &&
            _selectSourceItems(
              nextPage,
              source.chapters.itemSelector,
            ).isNotEmpty;
        final nextTitle = _extractRuleValue(
          nextRoot,
          source.detail.titleRule,
          baseUri: nextPage.requestUrl,
        );
        if (nextHasChapterList || nextTitle.isNotEmpty) {
          return nextPage;
        }
      } catch (_) {}
    }

    return page;
  }

  (String, String, String, bool) _extractChapter(
    _FetchedPage page,
    WebNovelSource source,
    String fallbackTitle,
  ) {
    final root = _pageRootValue(page);
    final title = _extractRuleValue(
      root,
      source.content.titleRule,
      baseUri: page.requestUrl,
    ).ifEmpty(fallbackTitle);

    if (page.jsonBody != null ||
        source.content.contentRule.type == RuleSelectorType.legado ||
        source.content.contentRule.type == RuleSelectorType.jsonPath) {
      final extracted = _extractRuleValue(
        root,
        source.content.contentRule,
        baseUri: page.requestUrl,
      );
      final normalizedHtml = _normalizeExtractedContentHtml(extracted);
      final normalizedText = _normalizeExtractedContentText(extracted);
      if (normalizedHtml.isNotEmpty || normalizedText.isNotEmpty) {
        return (title, normalizedText, normalizedHtml, true);
      }
    }

    final contentNode = _selectContentNode(
      page.document,
      source.content.contentRule.expression,
    );
    final cloned =
        contentNode?.clone(true) ??
        page.document.body?.clone(true) ??
        dom.Element.tag('div');
    for (final selector in source.content.removeSelectors) {
      cloned.querySelectorAll(selector).forEach((element) => element.remove());
    }

    var html = cloned.innerHtml.trim();
    var text = _cleanText(cloned.text);
    if (source.content.decodeQb520Scripts) {
      final decoded = _decodeQb520Scripts(page.html);
      if (decoded.length > text.length) {
        text = decoded;
        html = '<p>${decoded.replaceAll('\n', '</p><p>')}</p>';
      }
    }
    return (title, text, html, true);
  }

  ReaderModeArticle _extractReaderMode(dom.Document document, Uri requestUrl) {
    final articleNode = _guessBestArticleNode(document);
    final cloned =
        articleNode?.clone(true) ??
        document.body?.clone(true) ??
        dom.Element.tag('div');
    for (final selector in const [
      'script',
      'style',
      'noscript',
      'header',
      'footer',
      'nav',
      '.ads',
      '.ad',
      '.banner',
      '.toolbar',
      '.recommend',
      '.page',
      '.read_btn',
    ]) {
      cloned.querySelectorAll(selector).forEach((element) => element.remove());
    }

    final detectedTocLinks = _detectReaderModeTocLinks(document, requestUrl);
    final pageTitle =
        _extractMetaContent(
          document,
          const [
            'meta[property="og:title"]',
            'meta[name="title"]',
            'meta[property="twitter:title"]',
          ],
        ).ifEmpty(
          _cleanText(
            document.querySelector('h1')?.text ??
                document.querySelector('h2')?.text ??
                document.querySelector('title')?.text ??
                requestUrl.toString(),
          ),
        );
    final siteName = _extractMetaContent(
      document,
      const [
        'meta[property="og:site_name"]',
        'meta[name="application-name"]',
      ],
    ).ifEmpty(requestUrl.host);
    final author = _extractReaderModeAuthor(document, cloned);
    final publishTime = _extractReaderModePublishTime(document, cloned);
    final leadImage = _extractMetaContent(
      document,
      const [
        'meta[property="og:image"]',
        'meta[name="twitter:image"]',
      ],
    ).ifEmpty(
      _extractMetaContent(document, const ['link[rel="image_src"]'], attr: 'href'),
    );
    final nextPageUrl = _detectReaderModeNextPageUrl(
      document,
      requestUrl,
      cloned,
    );

    return ReaderModeArticle(
      url: requestUrl.toString(),
      pageTitle: pageTitle,
      siteName: siteName,
      author: author,
      publishTime: publishTime,
      leadImage: leadImage,
      nextPageUrl: nextPageUrl,
      detectedTocLinks: detectedTocLinks,
      contentHtml: cloned.innerHtml.trim(),
      contentText: _cleanText(cloned.text),
      confidence: _readerConfidence(cloned.text),
    );
  }

  Future<_FetchedPage> _requestPage(
    String url, {
    WebNovelSource? source,
    HttpMethod method = HttpMethod.get,
    Map<String, String>? extraHeaders,
    Map<String, String>? bodyFields,
    String? referer,
    String? userAgentOverride,
    Duration timeout = AppTimeouts.webnovelRequestPage,
  }) async {
    var requestUrl = Uri.tryParse(url);
    if (requestUrl == null ||
        (!requestUrl.hasScheme && requestUrl.host.isEmpty)) {
      if (source != null) {
        final base = Uri.tryParse(source.baseUrl);
        if (base != null && base.hasScheme) {
          requestUrl = base.resolve(url.trim());
          url = requestUrl.toString();
        }
      }
    }
    if (requestUrl == null ||
        (!requestUrl.hasScheme && requestUrl.host.isEmpty)) {
      throw FormatException('Invalid URL: $url');
    }
    if (requestUrl.scheme != 'http' && requestUrl.scheme != 'https') {
      throw FormatException('Unsupported URL scheme: ${requestUrl.scheme}');
    }
    final headers = <String, String>{
      'Accept':
          'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Cache-Control': 'no-cache',
      'User-Agent':
          userAgentOverride ??
          source?.userAgent.ifEmpty(defaultWebNovelUserAgent) ??
          defaultWebNovelUserAgent,
      ...?source?.headers,
      ...?extraHeaders,
    };
    if (referer != null && referer.isNotEmpty) {
      headers['Referer'] = referer;
    }

    final host = requestUrl.host;
    final session = host.isEmpty
        ? null
        : source == null
        ? await getSessionForDomain(host)
        : (await getSessionForSource(source.id) ?? await getSessionForDomain(host));
    if (session != null && session.cookies.isNotEmpty) {
      headers['Cookie'] = session.cookies
          .map((cookie) => '${cookie['name']}=${cookie['value']}')
          .join('; ');
    }
    if (userAgentOverride == null &&
        session != null &&
        session.userAgent.trim().isNotEmpty) {
      headers['User-Agent'] = session.userAgent;
    }

    late http.Response response;
    if (method == HttpMethod.post) {
      response = await _client
          .post(
            requestUrl,
            headers: headers,
            body: bodyFields ?? const <String, String>{},
          )
          .timeout(timeout);
    } else {
      response = await _client
          .get(requestUrl, headers: headers)
          .timeout(timeout);
    }

    if (response.statusCode >= 400) {
      throw HttpException('HTTP ${response.statusCode} for $url');
    }

    final html = _decodeHtml(
      response.bodyBytes,
      charsetHint: source?.charset,
      contentType: response.headers['content-type'],
    );
    final decodedJson = _tryDecodeJsonBody(
      html,
      response.headers['content-type'],
    );
    return _FetchedPage(
      requestUrl: response.request?.url ?? requestUrl,
      html: html,
      document: html_parser.parse(html),
      jsonBody: decodedJson,
    );
  }

  @visibleForTesting
  Future<String> requestPageHtmlForTest(
    String url, {
    Duration timeout = const Duration(milliseconds: 250),
  }) async {
    final page = await _requestPage(url, timeout: timeout);
    return page.html;
  }

  String _decodeHtml(
    List<int> bytes, {
    String? charsetHint,
    String? contentType,
  }) {
    final hint = (charsetHint ?? '').toLowerCase();
    final type = (contentType ?? '').toLowerCase();
    if (hint.contains('gb') || type.contains('charset=gb')) {
      return gbk.decode(bytes, allowMalformed: true);
    }

    final utf = utf8.decode(bytes, allowMalformed: true);
    final metaCharset = RegExp(
      'charset=[\'"]?([a-zA-Z0-9\\-_]+)',
      caseSensitive: false,
    ).firstMatch(utf)?.group(1)?.toLowerCase();
    if ((metaCharset ?? '').contains('gb')) {
      return gbk.decode(bytes, allowMalformed: true);
    }
    return utf;
  }

  dynamic _tryDecodeJsonBody(String body, String? contentType) {
    final trimmed = body.trim();
    final normalizedType = (contentType ?? '').toLowerCase();
    final looksLikeJson =
        normalizedType.contains('application/json') ||
        normalizedType.contains('+json') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[');
    if (!looksLikeJson || trimmed.isEmpty) {
      return null;
    }
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  dom.Element? _selectContentNode(dom.Document document, String selector) {
    if (selector.trim().isEmpty) {
      return _guessBestArticleNode(document);
    }
    for (final candidate in selector.split(',')) {
      final element = document.querySelector(candidate.trim());
      if (element != null) {
        return element;
      }
    }
    return _guessBestArticleNode(document);
  }

  dom.Element? _guessBestArticleNode(dom.Document document) {
    for (final selector in const [
      '#chaptercontent',
      '#content',
      '#booktxt',
      'article',
      'main',
      '.content',
      '.yd_text2',
    ]) {
      final element = document.querySelector(selector);
      if (element != null && _cleanText(element.text).length > 120) {
        return element;
      }
    }

    dom.Element? best;
    var bestScore = 0;
    for (final element in document.querySelectorAll(
      'div, article, main, section',
    )) {
      final score = _cleanText(element.text).length;
      if (score > bestScore) {
        bestScore = score;
        best = element;
      }
    }
    return best;
  }

  Object _pageRootValue(_FetchedPage page) =>
      page.jsonBody ??
      page.document.documentElement ??
      page.document.body ??
      page.document;

  List<Object?> _selectSourceItems(_FetchedPage page, String selector) {
    final trimmed = selector.trim();
    if (trimmed.isEmpty) {
      return const <Object?>[];
    }
    if (_shouldPreserveLegadoRawRule(trimmed, allowOnlyCssSelector: true)) {
      return _coerceSelectedItems(
        _evaluateLegadoPipeline(
          _pageRootValue(page),
          trimmed,
          baseUri: page.requestUrl,
        ),
      );
    }
    return page.document
        .querySelectorAll(trimmed)
        .cast<Object?>()
        .toList(growable: false);
  }

  List<Object?> _coerceSelectedItems(dynamic value) {
    if (value == null) {
      return const <Object?>[];
    }
    final structured = _asStructuredData(value);
    if (structured is List) {
      return List<Object?>.from(structured);
    }
    if (value is Iterable && value is! String) {
      return List<Object?>.from(value);
    }
    if (structured is Map) {
      return <Object?>[structured];
    }
    return <Object?>[value];
  }

  String _fallbackReadableText(Object? value) {
    if (value == null) {
      return '';
    }
    if (value is dom.Document) {
      return _cleanText(
        value.body?.text ?? value.documentElement?.text ?? value.outerHtml,
      );
    }
    if (value is dom.Element) {
      return _cleanText(value.text);
    }
    return _stringifySelectedValue(value);
  }

  String _rawTextForRuleRoot(Object? root) {
    if (root == null) {
      return '';
    }
    if (root is dom.Document) {
      return root.outerHtml;
    }
    if (root is dom.Element) {
      return root.outerHtml;
    }
    if (root is Map || (root is Iterable && root is! String)) {
      try {
        return jsonEncode(root);
      } catch (_) {
        return '$root';
      }
    }
    return '$root';
  }

  String _normalizeExtractedContentHtml(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.contains('<') && trimmed.contains('>')) {
      return trimmed;
    }
    final paragraphs = trimmed
        .split(RegExp(r'\n{2,}'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) => '<p>${item.replaceAll('\n', '<br/>')}</p>')
        .join();
    return paragraphs.ifEmpty('<p>$trimmed</p>');
  }

  String _normalizeExtractedContentText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if (trimmed.contains('<') && trimmed.contains('>')) {
      return _cleanText(html_parser.parseFragment(trimmed).text ?? '');
    }
    return _cleanText(trimmed);
  }

  dynamic _asStructuredData(dynamic input) {
    if (input is Map || (input is List && input is! String)) {
      return input;
    }
    if (input is String) {
      final trimmed = input.trim();
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return jsonDecode(trimmed);
        } catch (_) {
          return null;
        }
      }
    }
    return null;
  }

  String _stringifySelectedValue(dynamic value) {
    if (value == null) {
      return '';
    }
    if (value is String) {
      return _cleanText(value);
    }
    if (value is num || value is bool) {
      return '$value';
    }
    if (value is dom.Document || value is dom.Element) {
      return _fallbackReadableText(value);
    }
    if (value is Iterable) {
      return value
          .map(_stringifySelectedValue)
          .where((item) => item.isNotEmpty)
          .join('\n');
    }
    if (value is Map) {
      for (final key in const ['text', 'content', 'title', 'name', 'value']) {
        final candidate = _stringifySelectedValue(value[key]);
        if (candidate.isNotEmpty) {
          return candidate;
        }
      }
      try {
        return jsonEncode(value);
      } catch (_) {
        return value.toString();
      }
    }
    return _cleanText(value.toString());
  }

  bool _hasLegadoValue(dynamic value) {
    if (value == null) {
      return false;
    }
    if (value is String) {
      return value.trim().isNotEmpty;
    }
    if (value is Iterable) {
      return value.isNotEmpty;
    }
    if (value is Map) {
      return value.isNotEmpty;
    }
    return true;
  }

  List<String> _splitTopLevel(String input, String operatorToken) {
    if (input.isEmpty || !input.contains(operatorToken)) {
      return <String>[input];
    }
    final parts = <String>[];
    final buffer = StringBuffer();
    var inSingle = false;
    var inDouble = false;
    var depthParen = 0;
    var depthBracket = 0;
    var depthBrace = 0;

    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      if (char == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (char == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (char == '(') {
          depthParen++;
        } else if (char == ')') {
          depthParen = math.max(0, depthParen - 1);
        } else if (char == '[') {
          depthBracket++;
        } else if (char == ']') {
          depthBracket = math.max(0, depthBracket - 1);
        } else if (char == '{') {
          depthBrace++;
        } else if (char == '}') {
          depthBrace = math.max(0, depthBrace - 1);
        }
      }

      if (!inSingle &&
          !inDouble &&
          depthParen == 0 &&
          depthBracket == 0 &&
          depthBrace == 0 &&
          input.startsWith(operatorToken, index)) {
        parts.add(buffer.toString());
        buffer.clear();
        index += operatorToken.length - 1;
        continue;
      }
      buffer.write(char);
    }
    parts.add(buffer.toString());
    return parts;
  }

  dynamic _extractStructuredField(dynamic input, String field) {
    final structured = _asStructuredData(input);
    if (structured is Map && structured.containsKey(field)) {
      return structured[field];
    }
    return null;
  }

  dynamic _evaluateJsonPath(String expression, dynamic root) {
    final structured = _asStructuredData(root);
    if (structured == null) {
      return null;
    }
    var path = expression.trim();
    if (path.startsWith('@json:')) {
      path = path.substring(6).trim();
    }
    if (path.isEmpty) {
      return structured;
    }
    if (!path.startsWith(r'$')) {
      path = path.startsWith('.')
          ? '\$$path'
          : '\$.${path.replaceAll(RegExp(r'^@+'), '')}';
    }

    var current = <dynamic>[structured];
    var index = 1;
    while (index < path.length) {
      if (path.startsWith('..', index)) {
        index += 2;
        if (index < path.length && path[index] == '*') {
          current = current
              .expand(_recursiveJsonValues)
              .toList(growable: false);
          index++;
          continue;
        }
        final name = _readJsonPathIdentifier(path, index);
        index += name.length;
        current = current
            .expand((node) => _recursiveJsonFieldValues(node, name))
            .toList(growable: false);
        continue;
      }
      if (path[index] == '.') {
        index++;
        if (index < path.length && path[index] == '*') {
          current = current.expand(_directJsonValues).toList(growable: false);
          index++;
          continue;
        }
        final name = _readJsonPathIdentifier(path, index);
        index += name.length;
        current = current
            .expand((node) => _directJsonFieldValues(node, name))
            .toList(growable: false);
        continue;
      }
      if (path[index] == '[') {
        final end = path.indexOf(']', index);
        if (end < 0) {
          break;
        }
        final token = path.substring(index + 1, end).trim();
        index = end + 1;
        if (token == '*') {
          current = current.expand(_directJsonValues).toList(growable: false);
          continue;
        }
        if ((token.startsWith('"') && token.endsWith('"')) ||
            (token.startsWith("'") && token.endsWith("'"))) {
          final key = _decodeJsStringLiteral(token);
          current = current
              .expand((node) => _directJsonFieldValues(node, key))
              .toList(growable: false);
          continue;
        }
        final parsedIndex = int.tryParse(token);
        if (parsedIndex != null) {
          current = current
              .expand((node) => _directJsonIndexValues(node, parsedIndex))
              .toList(growable: false);
        }
        continue;
      }
      index++;
    }

    if (current.isEmpty) {
      return null;
    }
    return current.length == 1 ? current.first : current;
  }

  String _readJsonPathIdentifier(String path, int start) {
    final buffer = StringBuffer();
    for (var index = start; index < path.length; index++) {
      final char = path[index];
      if (char == '.' || char == '[') {
        break;
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  Iterable<dynamic> _directJsonFieldValues(dynamic node, String field) sync* {
    if (node is Map && node.containsKey(field)) {
      yield node[field];
      return;
    }
    if (node is List) {
      for (final item in node) {
        yield* _directJsonFieldValues(item, field);
      }
    }
  }

  Iterable<dynamic> _directJsonIndexValues(dynamic node, int index) sync* {
    if (node is List && index >= 0 && index < node.length) {
      yield node[index];
    }
  }

  Iterable<dynamic> _directJsonValues(dynamic node) sync* {
    if (node is Map) {
      yield* node.values;
    } else if (node is List) {
      yield* node;
    }
  }

  Iterable<dynamic> _recursiveJsonFieldValues(
    dynamic node,
    String field,
  ) sync* {
    if (node is Map) {
      if (node.containsKey(field)) {
        yield node[field];
      }
      for (final value in node.values) {
        yield* _recursiveJsonFieldValues(value, field);
      }
      return;
    }
    if (node is List) {
      for (final item in node) {
        yield* _recursiveJsonFieldValues(item, field);
      }
    }
  }

  Iterable<dynamic> _recursiveJsonValues(dynamic node) sync* {
    if (node is Map) {
      for (final value in node.values) {
        yield value;
        yield* _recursiveJsonValues(value);
      }
      return;
    }
    if (node is List) {
      for (final item in node) {
        yield item;
        yield* _recursiveJsonValues(item);
      }
    }
  }

  String _evaluateLegadoRuleValue(
    Object? root,
    String raw, {
    required Uri baseUri,
  }) {
    final value = _evaluateLegadoPipeline(root, raw, baseUri: baseUri);
    return _stringifySelectedValue(value);
  }

  dynamic _evaluateLegadoPipeline(
    Object? root,
    String raw, {
    required Uri baseUri,
  }) {
    dynamic current = root;
    for (final stage in _splitLegadoStages(raw)) {
      current = stage.key
          ? _evaluateConstrainedLegadoJs(
              stage.value,
              current,
              originalRoot: root,
              baseUri: baseUri,
            )
          : _evaluateLegadoSelectorStage(
              stage.value,
              current,
              root,
              baseUri: baseUri,
            );
    }
    return current;
  }

  List<MapEntry<bool, String>> _splitLegadoStages(String raw) {
    final stages = <MapEntry<bool, String>>[];
    var remaining = raw;

    void appendTextStages(String text) {
      for (final line
          in text
              .split(RegExp(r'\r?\n'))
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)) {
        stages.add(MapEntry(false, line));
      }
    }

    while (remaining.isNotEmpty) {
      final jsBlockStart = remaining.indexOf('<js>');
      final inlineJsStart = remaining.indexOf('@js:');
      final hasInlineJs =
          inlineJsStart >= 0 &&
          (jsBlockStart < 0 || inlineJsStart < jsBlockStart);

      if (hasInlineJs) {
        appendTextStages(remaining.substring(0, inlineJsStart));
        stages.add(
          MapEntry(true, remaining.substring(inlineJsStart + 4).trim()),
        );
        break;
      }
      if (jsBlockStart < 0) {
        appendTextStages(remaining);
        break;
      }

      appendTextStages(remaining.substring(0, jsBlockStart));
      final jsBlockEnd = remaining.indexOf('</js>', jsBlockStart + 4);
      if (jsBlockEnd < 0) {
        stages.add(
          MapEntry(true, remaining.substring(jsBlockStart + 4).trim()),
        );
        break;
      }
      stages.add(
        MapEntry(
          true,
          remaining.substring(jsBlockStart + 4, jsBlockEnd).trim(),
        ),
      );
      remaining = remaining.substring(jsBlockEnd + 5);
    }

    return stages;
  }

  dynamic _evaluateLegadoSelectorStage(
    String stage,
    dynamic current,
    Object? originalRoot, {
    required Uri baseUri,
  }) {
    for (final candidate in _splitTopLevel(stage, '||')) {
      final value = _evaluateLegadoCandidate(
        candidate.trim(),
        current,
        originalRoot,
        baseUri: baseUri,
      );
      if (_hasLegadoValue(value)) {
        return value;
      }
      if (!identical(current, originalRoot)) {
        final fallback = _evaluateLegadoCandidate(
          candidate.trim(),
          originalRoot,
          originalRoot,
          baseUri: baseUri,
        );
        if (_hasLegadoValue(fallback)) {
          return fallback;
        }
      }
    }
    return '';
  }

  dynamic _evaluateLegadoCandidate(
    String candidate,
    dynamic input,
    Object? originalRoot, {
    required Uri baseUri,
  }) {
    if (candidate.isEmpty) {
      return input;
    }
    if (candidate.startsWith('##')) {
      return _applyInlineRegex(_stringifySelectedValue(input), candidate);
    }

    final regexIndex = _findInlineRegexMarker(candidate);
    final selector = regexIndex < 0
        ? candidate
        : candidate.substring(0, regexIndex).trim();
    final regex = regexIndex < 0 ? '' : candidate.substring(regexIndex).trim();

    dynamic value;
    if (selector.contains('{{') || selector.contains(r'{$.')) {
      value = _interpolateLegadoTemplate(
        selector,
        input,
        originalRoot,
        baseUri: baseUri,
      );
    } else if (_looksLikeJsonSelector(selector)) {
      value = _evaluateJsonPath(selector, _asStructuredData(input));
    } else if (_looksLikeLegadoCssExpression(selector)) {
      value = _evaluateCssLikeDynamic(input, selector, baseUri: baseUri);
    } else if (selector == 'result') {
      value = input;
    } else if (selector == 'baseUrl') {
      value = baseUri.toString();
    } else {
      value = _extractStructuredField(input, selector);
      if (!_hasLegadoValue(value)) {
        value = selector;
      }
    }

    return regex.isEmpty
        ? value
        : _applyInlineRegex(_stringifySelectedValue(value), regex);
  }

  int _findInlineRegexMarker(String candidate) {
    var inSingle = false;
    var inDouble = false;
    for (var index = 0; index < candidate.length - 1; index++) {
      final char = candidate[index];
      if (char == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (char == '"' && !inSingle) {
        inDouble = !inDouble;
      }
      if (!inSingle &&
          !inDouble &&
          candidate[index] == '#' &&
          candidate[index + 1] == '#') {
        return index;
      }
    }
    return -1;
  }

  String _applyInlineRegex(String input, String rawRegex) {
    final pattern = rawRegex.startsWith('##')
        ? rawRegex.substring(2).trim()
        : rawRegex.trim();
    if (pattern.isEmpty) {
      return input;
    }
    final match = RegExp(pattern, dotAll: true).firstMatch(input);
    if (match == null) {
      return _cleanText(input);
    }
    if (match.groupCount >= 1) {
      return _cleanText(match.group(1) ?? '');
    }
    return _cleanText(match.group(0) ?? '');
  }

  bool _looksLikeLegadoCssExpression(String raw) {
    if (raw.isEmpty ||
        _looksLikeJsonSelector(raw) ||
        raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('data:')) {
      return false;
    }
    if (raw.startsWith('//@')) {
      return true;
    }
    return _parseLegadoCssLikeRule(
          raw,
          absoluteUrl: false,
          allowOnlyCssSelector: false,
        ) !=
        null;
  }

  dynamic _evaluateCssLikeDynamic(
    dynamic input,
    String raw, {
    required Uri baseUri,
  }) {
    final domRoot = _coerceDomRoot(input);
    if (domRoot == null) {
      return null;
    }
    if (raw.startsWith('//@')) {
      final element = domRoot is dom.Document
          ? (domRoot.documentElement ?? domRoot.body)
          : domRoot as dom.Element;
      if (element == null) {
        return '';
      }
      return element.attributes[raw.substring(3).trim()] ?? '';
    }

    final parsed = _parseLegadoCssLikeRule(
      raw,
      absoluteUrl: false,
      allowOnlyCssSelector: false,
    );
    if (parsed is! SelectorRule) {
      return null;
    }
    final root = domRoot as dynamic;
    for (final candidate in parsed.expression.split(',')) {
      final selector = candidate.trim();
      if (selector.isEmpty) {
        continue;
      }
      final match = root.querySelector(selector);
      if (match == null) {
        continue;
      }
      final rawValue = parsed.attr == null || parsed.attr!.isEmpty
          ? match.text.trim()
          : (match.attributes[parsed.attr!] ?? '');
      if (rawValue.isNotEmpty) {
        return rawValue;
      }
    }
    return null;
  }

  dynamic _coerceDomRoot(dynamic input) {
    if (input is dom.Document || input is dom.Element) {
      return input;
    }
    if (input is String) {
      final trimmed = input.trim();
      if (trimmed.contains('<') && trimmed.contains('>')) {
        return html_parser.parse(trimmed);
      }
    }
    return null;
  }

  String _interpolateLegadoTemplate(
    String template,
    dynamic input,
    Object? originalRoot, {
    required Uri baseUri,
  }) {
    var output = template.replaceAllMapped(RegExp(r'\{\{([^{}]+)\}\}'), (
      match,
    ) {
      return _evaluateLegadoTemplateExpression(
        match.group(1) ?? '',
        input,
        originalRoot,
        baseUri: baseUri,
      );
    });
    output = output.replaceAllMapped(RegExp(r'\{(\$[^{}]+)\}'), (match) {
      return _evaluateLegadoTemplateExpression(
        match.group(1) ?? '',
        input,
        originalRoot,
        baseUri: baseUri,
      );
    });
    return output.trim();
  }

  String _evaluateLegadoTemplateExpression(
    String expression,
    dynamic input,
    Object? originalRoot, {
    required Uri baseUri,
  }) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    if ((trimmed.startsWith("'") && trimmed.endsWith("'")) ||
        (trimmed.startsWith('"') && trimmed.endsWith('"'))) {
      return _decodeJsStringLiteral(trimmed);
    }
    if (trimmed.contains('&&')) {
      final parts = _splitTopLevel(trimmed, '&&');
      if (parts.length == 2) {
        final left = _evaluateLegadoTemplateExpression(
          parts[0],
          input,
          originalRoot,
          baseUri: baseUri,
        );
        if (left.isEmpty) {
          return '';
        }
        return _evaluateLegadoTemplateExpression(
          parts[1],
          input,
          originalRoot,
          baseUri: baseUri,
        );
      }
    }
    if (trimmed.contains('||')) {
      for (final part in _splitTopLevel(trimmed, '||')) {
        final value = _evaluateLegadoTemplateExpression(
          part,
          input,
          originalRoot,
          baseUri: baseUri,
        );
        if (value.isNotEmpty) {
          return value;
        }
      }
      return '';
    }
    final getStringMatch = RegExp(
      r'''java\.getString\(['"](.+?)['"]\)''',
    ).firstMatch(trimmed);
    if (getStringMatch != null) {
      return _stringifySelectedValue(
        _evaluateJsonPath(
          getStringMatch.group(1) ?? '',
          _asStructuredData(input) ?? _asStructuredData(originalRoot),
        ),
      );
    }
    if (_looksLikeJsonSelector(trimmed)) {
      return _stringifySelectedValue(
        _evaluateJsonPath(
          trimmed,
          _asStructuredData(input) ?? _asStructuredData(originalRoot),
        ),
      );
    }
    if (trimmed == 'result') {
      return _stringifySelectedValue(input);
    }
    if (trimmed == 'baseUrl') {
      return baseUri.toString();
    }
    return '';
  }

  String _decodeJsStringLiteral(String literal) {
    final quote = literal[0];
    final body = literal.substring(1, literal.length - 1);
    final escapedQuote = '\\$quote';
    return body
        .replaceAll(r'\\', '\\')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t')
        .replaceAll(escapedQuote, quote);
  }

  dynamic _evaluateConstrainedLegadoJs(
    String script,
    dynamic current, {
    Object? originalRoot,
    required Uri baseUri,
  }) {
    final trimmed = script.trim();
    if (trimmed.isEmpty) {
      return current;
    }

    final replaceMatch = RegExp(
      r'''^result\.replace\(/(.+)/([a-z]*)\s*,\s*(['"])([\s\S]*)\3\)$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (replaceMatch != null) {
      return ('$current').replaceAll(
        RegExp(
          replaceMatch.group(1)!,
          caseSensitive: !(replaceMatch.group(2) ?? '').contains('i'),
          multiLine: (replaceMatch.group(2) ?? '').contains('m'),
        ),
        replaceMatch.group(4) ?? '',
      );
    }

    final concatMatch = RegExp(
      r'''^(['"])(.*)\1\s*\+\s*result$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (concatMatch != null) {
      return '${concatMatch.group(2) ?? ''}${current ?? ''}';
    }

    final suffixConcatMatch = RegExp(
      r'''^result\s*\+\s*(['"])(.*)\1$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (suffixConcatMatch != null) {
      return '${current ?? ''}${suffixConcatMatch.group(2) ?? ''}';
    }

    final baseUrlReplaceMatch = RegExp(
      r'''^baseUrl\.replace\(/(.+)/([a-z]*)\s*,\s*(['"])([\s\S]*)\3\)$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (baseUrlReplaceMatch != null) {
      return baseUri.toString().replaceAll(
        RegExp(
          baseUrlReplaceMatch.group(1)!,
          caseSensitive: !(baseUrlReplaceMatch.group(2) ?? '').contains('i'),
          multiLine: (baseUrlReplaceMatch.group(2) ?? '').contains('m'),
        ),
        baseUrlReplaceMatch.group(4) ?? '',
      );
    }

    final simpleResultMatch = RegExp(
      r'''^String\(result\)\.match\(/(.+)/([a-z]*)\)\[(\d+)\]$''',
      dotAll: true,
    ).firstMatch(trimmed);
    if (simpleResultMatch != null) {
      final match = RegExp(
        simpleResultMatch.group(1)!,
        caseSensitive: !(simpleResultMatch.group(2) ?? '').contains('i'),
      ).firstMatch('$current');
      if (match == null) {
        return '';
      }
      final groupIndex = int.tryParse(simpleResultMatch.group(3) ?? '') ?? 0;
      return match.group(groupIndex) ?? '';
    }

    if (trimmed == 'result' || trimmed == 'src') {
      return current;
    }
    return current;
  }

  String _extractRuleValue(
    Object? root,
    SelectorRule rule, {
    required Uri baseUri,
  }) {
    if (root == null) {
      return rule.defaultValue;
    }
    if (rule.type == RuleSelectorType.legado) {
      final value = _evaluateLegadoRuleValue(
        root,
        rule.expression,
        baseUri: baseUri,
      );
      return _finalizeExtractedValue(value, rule, baseUri);
    }
    if (rule.expression.trim().isEmpty) {
      return _finalizeExtractedValue(
        _fallbackReadableText(root),
        rule,
        baseUri,
      );
    }
    if (rule.type == RuleSelectorType.regex) {
      final raw = _rawTextForRuleRoot(root);
      return _applyRegex(rule, raw).ifEmpty(rule.defaultValue);
    }
    if (rule.type == RuleSelectorType.jsonPath) {
      final value = _stringifySelectedValue(
        _evaluateJsonPath(rule.expression, _asStructuredData(root)),
      );
      return _finalizeExtractedValue(value, rule, baseUri);
    }
    if (root is dom.Document || root is dom.Element) {
      final elementRoot = root as dynamic;
      for (final candidate in rule.expression.split(',')) {
        final selector = candidate.trim();
        if (selector.isEmpty) {
          continue;
        }
        final match = elementRoot.querySelector(selector);
        if (match == null) {
          continue;
        }
        final raw = rule.attr == null || rule.attr!.isEmpty
            ? match.text.trim()
            : (match.attributes[rule.attr!] ?? '');
        final value = _finalizeExtractedValue(raw, rule, baseUri);
        if (value.isNotEmpty) {
          return value;
        }
      }
    }
    final directStructured = _extractStructuredField(root, rule.expression);
    final directValue = _stringifySelectedValue(directStructured);
    if (directValue.isNotEmpty) {
      return _finalizeExtractedValue(directValue, rule, baseUri);
    }
    return rule.defaultValue;
  }

  String _extractLooseValue(
    dom.Element root,
    String expression, {
    required Uri baseUri,
  }) {
    final split = expression.split('@');
    final selector = split.first.trim();
    final attr = split.length > 1 ? split.last.trim() : '';
    for (final candidate in selector.split(',')) {
      final match = root.querySelector(candidate.trim());
      if (match == null) {
        continue;
      }
      final raw = attr.isEmpty
          ? match.text.trim()
          : (match.attributes[attr] ?? '');
      if (raw.isEmpty) {
        continue;
      }
      return attr.isEmpty ? _cleanText(raw) : _resolveUrl(baseUri, raw);
    }
    return '';
  }

  String _finalizeExtractedValue(String raw, SelectorRule rule, Uri baseUri) {
    var value = _cleanText(raw);
    if (rule.regex != null && rule.regex!.isNotEmpty) {
      value = _applyRegex(rule, value);
    }
    if (rule.absoluteUrl) {
      value = _resolveUrl(baseUri, value);
    }
    return value.ifEmpty(rule.defaultValue);
  }

  String _applyRegex(SelectorRule rule, String value) {
    if (rule.regex == null || rule.regex!.isEmpty) {
      return _cleanText(value);
    }
    final match = RegExp(rule.regex!, dotAll: true).firstMatch(value);
    if (match == null) {
      return _cleanText(value);
    }
    if (match.groupCount >= 1) {
      return _cleanText(match.group(1) ?? '');
    }
    return _cleanText(match.group(0) ?? '');
  }

  String _resolveUrl(Uri baseUri, String value) {
    if (value.trim().isEmpty) {
      return '';
    }
    final parsed = Uri.tryParse(value.trim());
    if (parsed == null) {
      return '';
    }
    if (parsed.hasScheme) {
      return parsed.toString();
    }
    return baseUri.resolveUri(parsed).toString();
  }

  String _cleanText(String value) {
    return value
        .replaceAll('\u00a0', ' ')
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
        .trim();
  }

  String _normalizeChapterTitleKey(String value) {
    return _cleanText(value).toLowerCase().replaceAll(
      RegExp("[\\s\\-_~·•，。、“”\"'‘’：:;；!?！？【】\\[\\]\\(\\)（）]"),
      '',
    );
  }

  bool _looksLikeSourceHit(WebSearchHit hit, WebNovelSource source) {
    final uri = Uri.tryParse(hit.url);
    final normalizedDomains = source.siteDomains.isEmpty
        ? <String>{Uri.parse(source.baseUrl).host.replaceFirst('www.', '')}
        : source.siteDomains
              .map((item) => item.replaceFirst('www.', ''))
              .toSet();
    final host = uri?.host.replaceFirst('www.', '') ?? '';
    if (host.isNotEmpty &&
        normalizedDomains.any(
          (domain) => host == domain || host.endsWith('.$domain'),
        )) {
      return true;
    }

    final haystack = '${hit.title}\n${hit.snippet}\n${hit.url}'.toLowerCase();
    if (haystack.contains(source.name.toLowerCase())) {
      return true;
    }
    return normalizedDomains.any(haystack.contains);
  }

  String _findNextPage(Uri baseUri, dom.Element root) {
    for (final anchor in root.querySelectorAll('a')) {
      final text = anchor.text.trim();
      if (RegExp(
        r'\u4e0b\u4e00\u7ae0|\u4e0b\u4e00\u9875',
        unicode: true,
      ).hasMatch(text)) {
        return _resolveUrl(baseUri, anchor.attributes['href'] ?? '');
      }
    }
    return '';
  }

  double _readerConfidence(String text) {
    final length = _cleanText(text).length;
    if (length >= 4000) {
      return 0.95;
    }
    if (length >= 1500) {
      return 0.8;
    }
    if (length >= 600) {
      return 0.6;
    }
    return 0.35;
  }

  String _extractMetaContent(
    dom.Document document,
    List<String> selectors, {
    String attr = 'content',
  }) {
    for (final selector in selectors) {
      final node = document.querySelector(selector);
      final value = node?.attributes[attr] ?? '';
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  String _extractReaderModeAuthor(dom.Document document, dom.Element root) {
    final metaAuthor = _extractMetaContent(
      document,
      const [
        'meta[name="author"]',
        'meta[property="article:author"]',
        'meta[property="og:author"]',
        'meta[name="byline"]',
      ],
    );
    if (metaAuthor.isNotEmpty) {
      return _cleanText(metaAuthor);
    }

    for (final selector in const [
      '.author',
      '.book-author',
      '.info .author',
      '.book-info .author',
      '#author',
      '[itemprop="author"]',
      '.writer',
      '.byline',
    ]) {
      final node = document.querySelector(selector) ?? root.querySelector(selector);
      if (node == null) {
        continue;
      }
      final text = _cleanText(node.text)
          .replaceAll(RegExp(r'^作者[:：]\s*'), '')
          .trim();
      if (text.isNotEmpty && text.length <= 40) {
        return text;
      }
    }
    return '';
  }

  String _extractReaderModePublishTime(dom.Document document, dom.Element root) {
    final metaTime = _extractMetaContent(
      document,
      const [
        'meta[property="article:published_time"]',
        'meta[name="pubdate"]',
        'meta[name="publishdate"]',
        'meta[name="timestamp"]',
      ],
    );
    if (metaTime.isNotEmpty) {
      return _cleanText(metaTime);
    }
    final timeNode =
        document.querySelector('time[datetime]') ??
        root.querySelector('time[datetime]');
    if (timeNode != null) {
      final value = timeNode.attributes['datetime'] ?? '';
      if (value.trim().isNotEmpty) {
        return value.trim();
      }
      return _cleanText(timeNode.text);
    }
    return '';
  }

  int _readerModeTocPriority(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('all.html') ||
        lower.contains('index.html') ||
        lower.contains('catalog') ||
        lower.contains('list') ||
        lower.contains('dir')) {
      return 0;
    }
    if (lower.contains('/book/') ||
        lower.contains('/info') ||
        lower.contains('/detail')) {
      return 1;
    }
    if (lower.contains('/chapter') ||
        lower.contains('/read') ||
        RegExp(r'/\d+[_-]\d+\.html$', caseSensitive: false).hasMatch(lower)) {
      return 3;
    }
    return 2;
  }

  List<String> _detectReaderModeTocLinks(
    dom.Document document,
    Uri requestUrl,
  ) {
    final links = <String>{};
    final relLink = document.querySelector('link[rel="contents"]');
    if (relLink != null) {
      final href = relLink.attributes['href'] ?? '';
      final resolved = _resolveUrl(requestUrl, href);
      if (resolved.isNotEmpty) {
        links.add(resolved);
      }
    }

    for (final anchor in document.querySelectorAll('a[href]')) {
      final text = _cleanText(anchor.text);
      final href = anchor.attributes['href'] ?? '';
      final resolved = _resolveUrl(requestUrl, href);
      if (resolved.isEmpty) {
        continue;
      }
      final isTocText = RegExp(
        r'\u76ee\u5f55|\u7ae0\u8282|\u7ae0\u8282\u76ee\u5f55|\u5168\u90e8\u7ae0\u8282|\u8fd4\u56de\u76ee\u5f55',
        unicode: true,
      ).hasMatch(text);
      final lowerUrl = resolved.toLowerCase();
      final isTocUrl =
          lowerUrl.contains('catalog') ||
          lowerUrl.contains('dir') ||
          lowerUrl.contains('list') ||
          lowerUrl.contains('index');
      if (isTocText || isTocUrl) {
        links.add(resolved);
      }
    }

    final sorted = links.toList()
      ..sort(
        (left, right) =>
            _readerModeTocPriority(left) - _readerModeTocPriority(right),
      );
    if (sorted.length > 12) {
      return sorted.take(12).toList(growable: false);
    }
    return sorted;
  }

  String _detectReaderModeNextPageUrl(
    dom.Document document,
    Uri requestUrl,
    dom.Element root,
  ) {
    final relNext = document.querySelector('link[rel="next"]');
    if (relNext != null) {
      final href = relNext.attributes['href'] ?? '';
      final resolved = _resolveUrl(requestUrl, href);
      if (resolved.isNotEmpty) {
        return resolved;
      }
    }
    final anchorNext = document.querySelector('a[rel="next"]');
    if (anchorNext != null) {
      final href = anchorNext.attributes['href'] ?? '';
      final resolved = _resolveUrl(requestUrl, href);
      if (resolved.isNotEmpty) {
        return resolved;
      }
    }
    return _findNextPage(requestUrl, root);
  }

  String _detectReaderModeChapterTitle(String pageTitle) {
    final trimmed = pageTitle.trim();
    if (trimmed.isEmpty) {
      return '';
    }
    final chapterMatch = RegExp(
      r'(第.{0,18}[章节回卷集][^\\|\\-—_]*?)($|\\s*[\\-|—_|｜])',
      unicode: true,
    ).firstMatch(trimmed);
    if (chapterMatch != null) {
      return chapterMatch.group(1)?.trim() ?? trimmed;
    }
    return trimmed;
  }

  String _detectReaderModeBookTitle(String pageTitle, {String fallback = ''}) {
    final trimmed = pageTitle.trim();
    if (trimmed.isEmpty) {
      return fallback;
    }

    final bracketMatch = RegExp(r'《([^》]{1,32})》').firstMatch(trimmed);
    if (bracketMatch != null) {
      return bracketMatch.group(1)?.trim().ifEmpty(fallback) ?? fallback;
    }

    final parts = trimmed
        .split(RegExp(r'\\s*[\\-|—_|｜·]\\s*'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return trimmed;
    }

    final cleaned = parts
        .where(
          (item) => !RegExp(
            r'第.{0,18}[章节回卷集]',
            unicode: true,
          ).hasMatch(item),
        )
        .toList();
    if (cleaned.isNotEmpty) {
      return cleaned.first;
    }
    return parts.first;
  }

  String _decodeQb520Scripts(String html) {
    final matches = RegExp(
      r"qsbs\.bb\('([^']+)'\)|atob\('([^']+)'\)|Base64\.decode\('([^']+)'\)",
      dotAll: true,
    ).allMatches(html);
    final chunks = <String>[];
    for (final match in matches) {
      final value = match.group(1) ?? match.group(2) ?? match.group(3) ?? '';
      if (value.isEmpty) {
        continue;
      }
      try {
        final decoded = utf8.decode(base64.decode(value), allowMalformed: true);
        final cleaned = _cleanText(decoded);
        if (cleaned.length > 3) {
          chunks.add(cleaned);
        }
      } catch (_) {}
    }
    return chunks.join('\n');
  }

  Map<String, dynamic>? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    final slice = raw.substring(start, end + 1);
    try {
      final decoded = jsonDecode(slice);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _deepMergeJson(
    Map<String, dynamic> base,
    Map<String, dynamic> patch,
  ) {
    final result = Map<String, dynamic>.from(base);
    patch.forEach((key, value) {
      if (value is Map && result[key] is Map) {
        result[key] = _deepMergeJson(
          Map<String, dynamic>.from(result[key] as Map),
          Map<String, dynamic>.from(value),
        );
      } else if (value != null) {
        result[key] = value;
      }
    });
    return result;
  }

  String _trimAiHtmlSample(String html) {
    var cleaned = html;
    cleaned = cleaned.replaceAll(
      RegExp(r'<script[\s\S]*?</script>', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'<style[\s\S]*?</style>', caseSensitive: false),
      '',
    );
    if (cleaned.length > 12000) {
      cleaned = cleaned.substring(0, 12000);
    }
    return cleaned;
  }

  Future<String> _collectAiResponse({
    required String systemPrompt,
    required String userPrompt,
    required TranslationConfig config,
  }) async {
    final buffer = StringBuffer();
    await for (final chunk in _translationService.askAiStream(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      config: config,
    )) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  Future<void> _persistReaderHistory(ReaderModeArticle article) async {
    final db = await database;
    await db.insert('web_reader_history', {
      'url': article.url,
      'payload': jsonEncode(_readerModeToJson(article)),
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Map<String, dynamic> _readerModeToJson(ReaderModeArticle article) => {
    'url': article.url,
    'pageTitle': article.pageTitle,
    'siteName': article.siteName,
    'contentHtml': article.contentHtml,
    'contentText': article.contentText,
    'author': article.author,
    'publishTime': article.publishTime,
    'leadImage': article.leadImage,
    'nextPageUrl': article.nextPageUrl,
    'detectedTocLinks': article.detectedTocLinks,
    'confidence': article.confidence,
  };

  ReaderModeArticle _readerModeFromJson(Map<String, dynamic> json) =>
      ReaderModeArticle(
        url: json['url'] as String? ?? '',
        pageTitle: json['pageTitle'] as String? ?? '',
        siteName: json['siteName'] as String? ?? '',
        contentHtml: json['contentHtml'] as String? ?? '',
        contentText: json['contentText'] as String? ?? '',
        author: json['author'] as String? ?? '',
        publishTime: json['publishTime'] as String? ?? '',
        leadImage: json['leadImage'] as String? ?? '',
        nextPageUrl: json['nextPageUrl'] as String? ?? '',
        detectedTocLinks: List<String>.from(
          json['detectedTocLinks'] as List? ?? const [],
        ),
        confidence: (json['confidence'] as num? ?? 0).toDouble(),
      );
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _FetchedPage {
  const _FetchedPage({
    required this.requestUrl,
    required this.html,
    required this.document,
    this.jsonBody,
  });

  final Uri requestUrl;
  final String html;
  final dom.Document document;
  final dynamic jsonBody;
}

class _BookDetail {
  const _BookDetail({
    required this.detailUrl,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.description,
  });

  final String detailUrl;
  final String title;
  final String author;
  final String coverUrl;
  final String description;
}
