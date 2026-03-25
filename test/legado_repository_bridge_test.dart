import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/app/runtime_platform.dart';
import 'package:wenwen_tome/features/translation/translation_config.dart';
import 'package:wenwen_tome/features/webnovel/engine/legado_platform_client.dart';
import 'package:wenwen_tome/features/webnovel/engine/legado_repository_bridge.dart';
import 'package:wenwen_tome/features/webnovel/models.dart';
import 'package:wenwen_tome/features/webnovel/webnovel_download_manager.dart';
import 'package:wenwen_tome/features/webnovel/webnovel_repository.dart';

class _FakeLegadoPlatformClient extends LegadoPlatformClient {
  _FakeLegadoPlatformClient({this.searchResults});

  final List<WebNovelSearchResult>? searchResults;
  int searchCallCount = 0;

  @override
  Future<void> prewarm() async {}

  @override
  Future<List<WebNovelSearchResult>?> searchBooks({
    required String query,
    String? sourceId,
    required int maxConcurrent,
    required List<String> requiredTags,
    required bool enableQueryExpansion,
    required bool enableWebFallback,
  }) async {
    searchCallCount += 1;
    return searchResults;
  }
}

class _FakeWebNovelRepositoryHandle implements WebNovelRepositoryHandle {
  _FakeWebNovelRepositoryHandle({required this.streamFactory});

  final Stream<WebNovelSearchUpdate> Function(String query) streamFactory;
  int searchStreamCallCount = 0;

  @override
  Stream<WebNovelSearchUpdate> searchBooksStream(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) {
    searchStreamCallCount += 1;
    return streamFactory(query);
  }

  @override
  Future<void> prewarm() async {}

  @override
  Future<List<WebNovelSource>> listSources() async => const <WebNovelSource>[];

  @override
  Future<List<WebSearchProvider>> listSearchProviders() async =>
      const <WebSearchProvider>[];

  @override
  Future<List<WebSession>> listSessions() async => const <WebSession>[];

  @override
  Future<List<ReaderModeArticle>> listReaderHistory() async =>
      const <ReaderModeArticle>[];

  @override
  Future<void> clearReaderHistory() async {}

  @override
  Future<void> clearReaderHistoryEntry(String url) async {}

  @override
  Future<List<WebNovelSearchResult>> searchBooks(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) async => const <WebNovelSearchResult>[];

  @override
  Future<WebNovelSearchReport> searchBooksWithReport(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) async => WebNovelSearchReport(
    query: query,
    results: const <WebNovelSearchResult>[],
    totalSources: 0,
    directCandidates: 0,
    failures: const <WebNovelSearchFailure>[],
    enableQueryExpansion: enableQueryExpansion,
  );

  @override
  Future<List<WebSearchHit>> webSearch(
    String query, {
    String? providerId,
  }) async => const <WebSearchHit>[];

  @override
  Future<ReaderModeDetectionResult> detectReaderMode(String url) async =>
      const ReaderModeDetectionResult(
        article: ReaderModeArticle(
          url: '',
          pageTitle: '',
          siteName: '',
          contentHtml: '',
          contentText: '',
        ),
        isLikelyNovel: false,
      );

  @override
  Future<ReaderModeDetectionResult> detectReaderModeFromHtml({
    required String html,
    required String url,
  }) async => const ReaderModeDetectionResult(
    article: ReaderModeArticle(
      url: '',
      pageTitle: '',
      siteName: '',
      contentHtml: '',
      contentText: '',
    ),
    isLikelyNovel: false,
  );

  @override
  Future<WebNovelBookMeta> addBookFromSearchResult(
    WebNovelSearchResult result,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<WebNovelSearchResult> resolveSearchResultDetail(
    WebNovelSearchResult result,
  ) async => result;

  @override
  Future<WebNovelBookMeta> addBookFromUrl(String url) {
    throw UnimplementedError();
  }

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
  }) {
    throw UnimplementedError();
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
  }) async => const <WebDownloadTask>[];

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
  Future<Map<String, int>> getChapterCacheStats() async =>
      const <String, int>{};

  @override
  Future<int> getDownloadSettingInt(String key, int fallback) async => fallback;

  @override
  Future<void> setDownloadSettingInt(String key, int value) async {}

  @override
  Future<SourceImportReport> importSourcesJsonWithReport(String jsonText) {
    throw UnimplementedError();
  }

  @override
  Future<SourceImportReport> importSourcesInputWithReport(String input) {
    throw UnimplementedError();
  }

  @override
  Future<String> exportSourcesJson() async => '[]';

  @override
  Future<void> saveManualCookies({
    required String sourceId,
    required String domain,
    required String cookieHeader,
    String userAgent = '',
  }) async {}

  @override
  Future<void> saveCookieMaps({
    required String sourceId,
    required String domain,
    required List<Map<String, dynamic>> cookies,
    String userAgent = '',
  }) async {}

  @override
  Future<void> clearSession(String sessionId) async {}

  @override
  Future<void> setSourceEnabled(String sourceId, bool enabled) async {}

  @override
  Future<int> removeCustomSources(Iterable<String> sourceIds) async => 0;

  @override
  Future<SourceTestResult> testSource(WebNovelSource source) async =>
      const SourceTestResult(ok: true, message: 'ok');
}

void main() {
  test(
    'Android search stream prefers platform results when available',
    () async {
      final platform = _FakeLegadoPlatformClient(
        searchResults: const <WebNovelSearchResult>[
          WebNovelSearchResult(
            sourceId: 'legado',
            title: 'Platform Result',
            detailUrl: 'https://example.com/book',
          ),
        ],
      );
      final legacy = _FakeWebNovelRepositoryHandle(
        streamFactory: (_) => Stream<WebNovelSearchUpdate>.value(
          const WebNovelSearchUpdate(
            query: 'ignored',
            results: <WebNovelSearchResult>[],
            aggregatedResults: <WebNovelAggregatedResult>[],
            totalSources: 1,
            directCandidates: 1,
            failures: <WebNovelSearchFailure>[],
            enableQueryExpansion: true,
            isFinal: true,
          ),
        ),
      );
      final bridge = LegadoRepositoryBridge(
        platform: LocalRuntimePlatform.android,
        legacy: legacy,
        platformClient: platform,
      );

      final updates = await bridge.searchBooksStream('legend').toList();

      expect(platform.searchCallCount, 1);
      expect(legacy.searchStreamCallCount, 0);
      expect(updates, hasLength(1));
      expect(updates.single.isFinal, isTrue);
      expect(updates.single.results.single.title, 'Platform Result');
    },
  );

  test(
    'Android search stream falls back to legacy when platform is unavailable',
    () async {
      final platform = _FakeLegadoPlatformClient(searchResults: null);
      final legacy = _FakeWebNovelRepositoryHandle(
        streamFactory: (query) => Stream<WebNovelSearchUpdate>.value(
          WebNovelSearchUpdate(
            query: query,
            results: const <WebNovelSearchResult>[
              WebNovelSearchResult(
                sourceId: 'legacy',
                title: 'Legacy Result',
                detailUrl: 'https://example.com/legacy',
              ),
            ],
            aggregatedResults: const <WebNovelAggregatedResult>[],
            totalSources: 2,
            directCandidates: 1,
            failures: const <WebNovelSearchFailure>[],
            enableQueryExpansion: true,
            isFinal: true,
          ),
        ),
      );
      final bridge = LegadoRepositoryBridge(
        platform: LocalRuntimePlatform.android,
        legacy: legacy,
        platformClient: platform,
      );

      final updates = await bridge.searchBooksStream('legend').toList();

      expect(platform.searchCallCount, 1);
      expect(legacy.searchStreamCallCount, 1);
      expect(updates.single.results.single.title, 'Legacy Result');
    },
  );
}
