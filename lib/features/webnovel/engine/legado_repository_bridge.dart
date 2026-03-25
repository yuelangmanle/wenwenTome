import '../../../app/runtime_platform.dart';
import '../../translation/translation_config.dart';
import '../models.dart';
import '../webnovel_repository.dart';
import '../webnovel_download_manager.dart';

class LegadoRepositoryBridge implements WebNovelRepositoryHandle {
  LegadoRepositoryBridge({
    LocalRuntimePlatform? platform,
    WebNovelRepositoryHandle? legacy,
  }) : _platform = platform ?? detectLocalRuntimePlatform(),
       _legacy = legacy ?? WebNovelRepository();

  final LocalRuntimePlatform _platform;
  final WebNovelRepositoryHandle _legacy;

  bool get _isAndroidLegadoTarget =>
      _platform == LocalRuntimePlatform.android;

  Future<T> _runLegadoOrFallback<T>(
    String capability,
    Future<T> Function() legacyOperation,
  ) async {
    if (_isAndroidLegadoTarget) {
      // Migration seam: Android webnovel capabilities will switch from the
      // legacy in-process repository to Legado-backed execution here.
    }
    return legacyOperation();
  }

  @override
  Future<void> prewarm() =>
      _runLegadoOrFallback<void>('prewarm', _legacy.prewarm);

  @override
  Future<List<WebNovelSource>> listSources() => _legacy.listSources();

  @override
  Future<List<WebSearchProvider>> listSearchProviders() =>
      _legacy.listSearchProviders();

  @override
  Future<List<WebSession>> listSessions() => _legacy.listSessions();

  @override
  Future<List<ReaderModeArticle>> listReaderHistory() =>
      _legacy.listReaderHistory();

  @override
  Future<void> clearReaderHistory() => _legacy.clearReaderHistory();

  @override
  Future<void> clearReaderHistoryEntry(String url) =>
      _legacy.clearReaderHistoryEntry(url);

  @override
  Future<List<WebNovelSearchResult>> searchBooks(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) {
    return _runLegadoOrFallback<List<WebNovelSearchResult>>(
      'searchBooks',
      () => _legacy.searchBooks(
        query,
        sourceId: sourceId,
        maxConcurrent: maxConcurrent,
        requiredTags: requiredTags,
        enableQueryExpansion: enableQueryExpansion,
        enableWebFallback: enableWebFallback,
      ),
    );
  }

  @override
  Future<WebNovelSearchReport> searchBooksWithReport(
    String query, {
    String? sourceId,
    int maxConcurrent = 6,
    List<String> requiredTags = const <String>[],
    bool enableQueryExpansion = true,
    bool enableWebFallback = false,
  }) {
    return _runLegadoOrFallback<WebNovelSearchReport>(
      'searchBooksWithReport',
      () => _legacy.searchBooksWithReport(
        query,
        sourceId: sourceId,
        maxConcurrent: maxConcurrent,
        requiredTags: requiredTags,
        enableQueryExpansion: enableQueryExpansion,
        enableWebFallback: enableWebFallback,
      ),
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
  }) => _legacy.searchBooksStream(
    query,
    sourceId: sourceId,
    maxConcurrent: maxConcurrent,
    requiredTags: requiredTags,
    enableQueryExpansion: enableQueryExpansion,
    enableWebFallback: enableWebFallback,
  );

  @override
  Future<List<WebSearchHit>> webSearch(String query, {String? providerId}) =>
      _legacy.webSearch(query, providerId: providerId);

  @override
  Future<ReaderModeDetectionResult> detectReaderMode(String url) =>
      _legacy.detectReaderMode(url);

  @override
  Future<ReaderModeDetectionResult> detectReaderModeFromHtml({
    required String html,
    required String url,
  }) => _legacy.detectReaderModeFromHtml(html: html, url: url);

  @override
  Future<WebNovelBookMeta> addBookFromSearchResult(WebNovelSearchResult result) {
    return _runLegadoOrFallback<WebNovelBookMeta>(
      'addBookFromSearchResult',
      () => _legacy.addBookFromSearchResult(result),
    );
  }

  @override
  Future<WebNovelSearchResult> resolveSearchResultDetail(
    WebNovelSearchResult result,
  ) => _legacy.resolveSearchResultDetail(result);

  @override
  Future<WebNovelBookMeta> addBookFromUrl(String url) => _legacy.addBookFromUrl(url);

  @override
  Future<WebNovelBookMeta?> findBookMetaByUrl(String url) =>
      _legacy.findBookMetaByUrl(url);

  @override
  Future<List<WebChapterRecord>> getChapters(
    String webBookId, {
    bool refresh = false,
  }) {
    return _runLegadoOrFallback<List<WebChapterRecord>>(
      'getChapters',
      () => _legacy.getChapters(webBookId, refresh: refresh),
    );
  }

  @override
  Future<List<WebSourceVersion>> listSourceVersions(String sourceId) =>
      _legacy.listSourceVersions(sourceId);

  @override
  Future<void> rollbackSourceVersion(String versionId) =>
      _legacy.rollbackSourceVersion(versionId);

  @override
  Future<AiSourcePatchSuggestion> repairSourceWithAi({
    required WebNovelSource source,
    required String sampleUrl,
    String sampleQuery = '',
    required TranslationConfig? config,
    AiSourceRepairMode mode = AiSourceRepairMode.suggest,
  }) => _legacy.repairSourceWithAi(
    source: source,
    sampleUrl: sampleUrl,
    sampleQuery: sampleQuery,
    config: config,
    mode: mode,
  );

  @override
  Future<int> cacheBookChapters(
    String webBookId, {
    int startIndex = 0,
    int? endIndex,
    bool forceRefresh = false,
    bool background = true,
  }) => _legacy.cacheBookChapters(
    webBookId,
    startIndex: startIndex,
    endIndex: endIndex,
    forceRefresh: forceRefresh,
    background: background,
  );

  @override
  Stream<int> watchDownloadTasks() => _legacy.watchDownloadTasks();

  @override
  Future<List<WebDownloadTask>> listDownloadTasks({
    String webBookId = '',
    bool includeCompleted = true,
    int limit = 200,
  }) => _legacy.listDownloadTasks(
    webBookId: webBookId,
    includeCompleted: includeCompleted,
    limit: limit,
  );

  @override
  Future<void> pauseAllDownloads() => _legacy.pauseAllDownloads();

  @override
  Future<void> resumeAllDownloads() => _legacy.resumeAllDownloads();

  @override
  Future<void> clearTerminalDownloadTasks() => _legacy.clearTerminalDownloadTasks();

  @override
  Future<void> clearAllDownloadTasks() => _legacy.clearAllDownloadTasks();

  @override
  Future<int> clearCachedChapters({String webBookId = ''}) =>
      _legacy.clearCachedChapters(webBookId: webBookId);

  @override
  Future<Map<String, int>> getChapterCacheStats() =>
      _legacy.getChapterCacheStats();

  @override
  Future<int> getDownloadSettingInt(String key, int fallback) =>
      _legacy.getDownloadSettingInt(key, fallback);

  @override
  Future<void> setDownloadSettingInt(String key, int value) =>
      _legacy.setDownloadSettingInt(key, value);

  @override
  Future<SourceImportReport> importSourcesJsonWithReport(String jsonText) =>
      _legacy.importSourcesJsonWithReport(jsonText);

  @override
  Future<SourceImportReport> importSourcesInputWithReport(String input) =>
      _legacy.importSourcesInputWithReport(input);

  @override
  Future<String> exportSourcesJson() => _legacy.exportSourcesJson();

  @override
  Future<void> saveManualCookies({
    required String sourceId,
    required String domain,
    required String cookieHeader,
    String userAgent = '',
  }) => _legacy.saveManualCookies(
    sourceId: sourceId,
    domain: domain,
    cookieHeader: cookieHeader,
    userAgent: userAgent,
  );

  @override
  Future<void> saveCookieMaps({
    required String sourceId,
    required String domain,
    required List<Map<String, dynamic>> cookies,
    String userAgent = '',
  }) => _legacy.saveCookieMaps(
    sourceId: sourceId,
    domain: domain,
    cookies: cookies,
    userAgent: userAgent,
  );

  @override
  Future<void> clearSession(String sessionId) => _legacy.clearSession(sessionId);

  @override
  Future<void> setSourceEnabled(String sourceId, bool enabled) =>
      _legacy.setSourceEnabled(sourceId, enabled);

  @override
  Future<int> removeCustomSources(Iterable<String> sourceIds) =>
      _legacy.removeCustomSources(sourceIds);

  @override
  Future<SourceTestResult> testSource(WebNovelSource source) =>
      _legacy.testSource(source);
}
