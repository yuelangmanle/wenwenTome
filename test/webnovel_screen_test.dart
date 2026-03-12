import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/webnovel/models.dart';
import 'package:wenwen_tome/features/webnovel/presentation/webnovel_screen.dart';
import 'package:wenwen_tome/features/webnovel/webnovel_download_manager.dart';
import 'package:wenwen_tome/features/webnovel/webnovel_repository.dart';
import 'package:wenwen_tome/features/translation/translation_config.dart';

class _FakeWebNovelRepository implements WebNovelRepositoryHandle {
  _FakeWebNovelRepository({this.failuresRemaining = 0});

  int failuresRemaining;

  @override
  Future<void> prewarm() async {
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw StateError('offline');
    }
  }

  @override
  Future<WebNovelBookMeta> addBookFromSearchResult(
    WebNovelSearchResult result,
  ) async => const WebNovelBookMeta(
    id: 'book-1',
    libraryBookId: 'library-1',
    sourceId: 'source',
    title: '示例书籍',
    author: '作者',
    detailUrl: 'https://example.com/book',
        originUrl: 'https://example.com/book',
      );

  @override
  Future<WebNovelSearchResult> resolveSearchResultDetail(
    WebNovelSearchResult result,
  ) async => result;

  @override
  Future<WebNovelBookMeta> addBookFromUrl(String url) async =>
      const WebNovelBookMeta(
        id: 'book-2',
        libraryBookId: 'library-2',
        sourceId: 'source',
        title: '示例书籍',
        author: '作者',
        detailUrl: 'https://example.com/book',
        originUrl: 'https://example.com/book',
      );

  @override
  Future<WebNovelBookMeta?> findBookMetaByUrl(String url) async => null;

  @override
  Future<List<WebChapterRecord>> getChapters(
    String webBookId, {
    bool refresh = false,
  }) async => const <WebChapterRecord>[];

  @override
  Future<List<WebSourceVersion>> listSourceVersions(String sourceId) async =>
      const <WebSourceVersion>[];

  @override
  Future<void> rollbackSourceVersion(String versionId) async {}

  @override
  Future<AiSourcePatchSuggestion> repairSourceWithAi({
    required WebNovelSource source,
    required String sampleUrl,
    String sampleQuery = '',
    required TranslationConfig? config,
    AiSourceRepairMode mode = AiSourceRepairMode.suggest,
  }) async => const AiSourcePatchSuggestion(
    sourceId: 'source',
    patch: <String, dynamic>{},
    note: '',
    confidence: 0,
    rawResponse: '',
  );

  @override
  Future<void> clearSession(String sessionId) async {}

  @override
  Future<ReaderModeDetectionResult> detectReaderMode(String url) async {
    return ReaderModeDetectionResult(
      article: ReaderModeArticle(
        url: url,
        pageTitle: '示例文章',
        siteName: '示例站点',
        contentHtml: '<p>正文</p>',
        contentText: '正文',
      ),
      isLikelyNovel: true,
    );
  }

  @override
  Future<ReaderModeDetectionResult> detectReaderModeFromHtml({
    required String html,
    required String url,
  }) async {
    return detectReaderMode(url);
  }

  @override
  Future<String> exportSourcesJson() async => '[]';

  @override
  Future<SourceImportReport> importSourcesJsonWithReport(
    String jsonText,
  ) async {
    return const SourceImportReport(
      importedSources: <WebNovelSource>[],
      totalEntries: 0,
      importedCount: 0,
      updatedCount: 0,
      legacyMappedCount: 0,
      skippedCount: 0,
      warnings: <String>[],
      entries: <SourceImportEntryReport>[],
    );
  }

  @override
  Future<SourceImportReport> importSourcesInputWithReport(String input) async {
    return importSourcesJsonWithReport(input);
  }

  @override
  Future<int> cacheBookChapters(
    String webBookId, {
    int startIndex = 0,
    int? endIndex,
    bool forceRefresh = false,
    bool background = true,
  }) async => 0;

  @override
  Stream<int> watchDownloadTasks() => const Stream<int>.empty();

  @override
  Future<List<WebDownloadTask>> listDownloadTasks({
    String webBookId = '',
    bool includeCompleted = true,
    int limit = 200,
  }) async =>
      const <WebDownloadTask>[];

  @override
  Future<void> pauseAllDownloads() async {}

  @override
  Future<void> resumeAllDownloads() async {}

  @override
  Future<void> clearTerminalDownloadTasks() async {}

  @override
  Future<void> clearAllDownloadTasks() async {}

  @override
  Future<int> clearCachedChapters({String webBookId = ''}) async => 0;

  @override
  Future<Map<String, int>> getChapterCacheStats() async => const {
    'cachedChapters': 0,
    'cachedBytes': 0,
    'cachedBooks': 0,
  };

  @override
  Future<int> getDownloadSettingInt(String key, int fallback) async => fallback;

  @override
  Future<void> setDownloadSettingInt(String key, int value) async {}

  @override
  Future<List<ReaderModeArticle>> listReaderHistory() async => const [];

  @override
  Future<void> clearReaderHistory() async {}

  @override
  Future<void> clearReaderHistoryEntry(String url) async {}

  @override
  Future<List<WebSearchProvider>> listSearchProviders() async => const [
    WebSearchProvider(
      id: 'provider',
      name: '搜索源',
      searchUrlTemplate: 'https://example.com?q={query}',
      resultListSelector: '.result',
      resultTitleSelector: 'a',
      resultUrlSelector: 'a',
      resultSnippetSelector: '.snippet',
    ),
  ];

  @override
  Future<List<WebSession>> listSessions() async => const [];

  @override
  Future<List<WebNovelSource>> listSources() async => const [
    WebNovelSource(
      id: 'source',
      name: '示例书源',
      baseUrl: 'https://example.com',
      search: BookSourceSearchRule(
        method: HttpMethod.get,
        pathTemplate: '/search?q={query}',
      ),
    ),
  ];

  @override
  Future<void> saveCookieMaps({
    required String sourceId,
    required String domain,
    required List<Map<String, dynamic>> cookies,
    String userAgent = '',
  }) async {}

  @override
  Future<void> saveManualCookies({
    required String sourceId,
    required String domain,
    required String cookieHeader,
    String userAgent = '',
  }) async {}

  @override
  Future<List<WebNovelSearchResult>> searchBooks(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) async => const [];

  @override
  Future<WebNovelSearchReport> searchBooksWithReport(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) async {
    return WebNovelSearchReport(
      query: query,
      results: const [],
      totalSources: 0,
      directCandidates: 0,
      failures: const [],
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
    return Stream<WebNovelSearchUpdate>.value(
      WebNovelSearchUpdate(
        query: query,
        results: const [],
        aggregatedResults: const [],
        totalSources: 0,
        directCandidates: 0,
        failures: const [],
        enableQueryExpansion: enableQueryExpansion,
        isFinal: true,
      ),
    );
  }

  @override
  Future<int> removeCustomSources(Iterable<String> sourceIds) async => 0;

  @override
  Future<void> setSourceEnabled(String sourceId, bool enabled) async {}

  @override
  Future<SourceTestResult> testSource(WebNovelSource source) async =>
      const SourceTestResult(ok: true, message: 'ok');

  @override
  Future<List<WebSearchHit>> webSearch(
    String query, {
    String? providerId,
  }) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('WebNovelScreen stays usable when prewarm fails once', (
    tester,
  ) async {
    final repository = _FakeWebNovelRepository(failuresRemaining: 1);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: WebNovelScreen(repository: repository)),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
  });
}
