import 'dart:async';
import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/runtime_platform.dart';
import '../../../core/utils/text_sanitizer.dart';
import '../../library/data/book_model.dart';
import '../../library/providers/library_providers.dart';
import '../../logging/app_run_log_service.dart';
import '../../logging/run_event_tracker.dart';
import '../../settings/providers/global_settings_provider.dart';
import '../../translation/translation_config.dart';
import '../ai_search_service.dart';
import '../models.dart';
import '../webnovel_repository.dart';
import 'webnovel_cache_screen.dart';

enum _BrowserRecognitionState { idle, loading, recognized, failed }

class WebNovelScreen extends ConsumerStatefulWidget {
  WebNovelScreen({
    super.key,
    WebNovelRepositoryHandle? repository,
    this.initialBrowserUrl,
  }) : repository = repository ?? WebNovelRepository();

  final WebNovelRepositoryHandle repository;
  final String? initialBrowserUrl;

  @override
  ConsumerState<WebNovelScreen> createState() => _WebNovelScreenState();
}

class _WebNovelScreenState extends ConsumerState<WebNovelScreen>
    with TickerProviderStateMixin {
  static const int _autoCacheChapterCount = 20;
  final RunEventTracker _runEventTracker = RunEventTracker();
  final AiSearchService _aiSearchService = AiSearchService();
  static final Set<Factory<OneSequenceGestureRecognizer>>
  _webViewGestureRecognizers = <Factory<OneSequenceGestureRecognizer>>{
    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
    Factory<OneSequenceGestureRecognizer>(() => TapGestureRecognizer()),
    Factory<OneSequenceGestureRecognizer>(() => LongPressGestureRecognizer()),
    Factory<OneSequenceGestureRecognizer>(
      () => VerticalDragGestureRecognizer(),
    ),
    Factory<OneSequenceGestureRecognizer>(
      () => HorizontalDragGestureRecognizer(),
    ),
    Factory<OneSequenceGestureRecognizer>(() => ScaleGestureRecognizer()),
  };

  final TextEditingController _bookSearchController = TextEditingController();
  final TextEditingController _browserInputController = TextEditingController();
  final TextEditingController _sourceFilterController = TextEditingController();
  final ScrollController _aggregatedResultsController = ScrollController();
  final ScrollController _rawResultsController = ScrollController();
  late final TabController _searchResultsTabController;

  InAppWebViewController? _browserController;
  List<WebNovelSource> _sources = const <WebNovelSource>[];
  List<_SourceListEntry> _indexedSources = const <_SourceListEntry>[];
  List<WebSearchProvider> _providers = const <WebSearchProvider>[];
  List<WebSession> _sessions = const <WebSession>[];
  List<WebNovelSearchResult> _bookResults = const <WebNovelSearchResult>[];
  List<WebNovelAggregatedResult> _aggregatedResults =
      const <WebNovelAggregatedResult>[];
  WebNovelSearchUpdate? _pendingSearchUpdate;
  StreamSubscription<WebNovelSearchUpdate>? _bookSearchSubscription;
  Timer? _searchUpdateDebounce;
  Timer? _autoRecognitionDebounce;
  int _bookSearchRequestId = 0;
  int _aiRerankRequestId = 0;
  bool _aiRerankApplied = false;
  int _aiFilteredCount = 0;
  List<ReaderModeArticle> _history = const <ReaderModeArticle>[];
  ReaderModeDetectionResult? _preview;
  PullToRefreshController? _pullToRefreshController;

  bool _busy = false;
  bool _pageLoading = true;
  bool _bookSearchAttempted = false;
  bool _browserLoading = false;
  bool _recognizingPage = false;
  bool _readerOptimizationEnabled = true;
  bool _browserCanGoBack = false;
  bool _browserCanGoForward = false;
  _BrowserRecognitionState _recognitionState = _BrowserRecognitionState.idle;
  String _recognitionError = '';
  String? _selectedSourceId;
  String? _selectedProviderId;
  final Set<String> _selectedSearchTags = <String>{};
  String _sourceFilterText = '';
  int _searchConcurrency = 6;
  bool _enableSearchQueryExpansion = true;
  WebNovelSearchReport? _lastBookSearchReport;
  String? _loadError;
  String _browserUrl = '';
  String? _lastBrowserKeyword;
  Timer? _backgroundReloadTimer;
  late final TabController _tabController;
  bool _shouldBuildBrowserTab = false;
  bool _showSearchBackToTop = false;

  WebNovelRepositoryHandle get _repository => widget.repository;

  bool get _isDesktop =>
      detectLocalRuntimePlatform() == LocalRuntimePlatform.windows;

  bool get _supportsEmbeddedBrowser => InAppWebViewPlatform.instance != null;

  Duration get _repositoryPrewarmTimeout =>
      _isDesktop ? const Duration(seconds: 8) : const Duration(seconds: 15);

  Duration get _repositoryListTimeout =>
      _isDesktop ? const Duration(seconds: 4) : const Duration(seconds: 12);

  Duration get _searchTimeout =>
      _isDesktop ? const Duration(seconds: 18) : const Duration(seconds: 30);

  Future<T> _loadRepositorySection<T>(
    String label,
    Future<T> Function() loader, {
    required T fallback,
    void Function()? onError,
  }) async {
    try {
      return await loader().timeout(_repositoryListTimeout);
    } catch (error) {
      onError?.call();
      await AppRunLogService.instance.logError(
        'WebNovel section load failed: $label; $error',
      );
      return fallback;
    }
  }

  Future<void> _refreshHistory() async {
    final history = await _loadRepositorySection<List<ReaderModeArticle>>(
      'history',
      _repository.listReaderHistory,
      fallback: _history,
    );
    if (!mounted) {
      return;
    }
    setState(() => _history = history);
  }

  Future<void> _refreshSessions() async {
    final sessions = await _loadRepositorySection<List<WebSession>>(
      'sessions',
      _repository.listSessions,
      fallback: _sessions,
    );
    if (!mounted) {
      return;
    }
    setState(() => _sessions = sessions);
  }

  WebNovelSource? _resolveSourceForHost(String host) {
    final normalized = host.toLowerCase();
    for (final source in _sources) {
      for (final domain in source.siteDomains) {
        final candidate = domain.toLowerCase();
        if (normalized == candidate || normalized.endsWith('.$candidate')) {
          return source;
        }
      }
    }
    return null;
  }

  String _resolveSessionDomain(String host, WebNovelSource? source) {
    final normalized = host.toLowerCase();
    if (source == null) {
      return normalized;
    }
    String? best;
    for (final domain in source.siteDomains) {
      final candidate = domain.toLowerCase();
      if (normalized == candidate || normalized.endsWith('.$candidate')) {
        if (best == null || candidate.length < best.length) {
          best = candidate;
        }
      }
    }
    return best ?? normalized;
  }

  String _historyDomain(ReaderModeArticle article) {
    final host = Uri.tryParse(article.url)?.host ?? '';
    if (host.isNotEmpty) {
      return host;
    }
    final fallback = article.siteName.trim();
    return fallback.isEmpty ? '未知站点' : fallback;
  }

  String _safeText(String raw) => sanitizeUiText(raw, fallback: raw);

  String _extractStatusLabel(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return '';
    }
    if (RegExp(r'已完结|完结').hasMatch(normalized)) {
      return '完结';
    }
    if (RegExp(r'连载|更新中|连载中').hasMatch(normalized)) {
      return '连载';
    }
    return '';
  }

  String _extractWordCountLabel(String text) {
    final match = RegExp(r'(\d+(?:\.\d+)?)(万|千)?字').firstMatch(text);
    if (match == null) {
      return '';
    }
    return '${match.group(1)}${match.group(2) ?? ''}字';
  }

  Map<String, List<ReaderModeArticle>> _groupHistoryByDomain() {
    final grouped = <String, List<ReaderModeArticle>>{};
    for (final item in _history) {
      final key = _historyDomain(item);
      grouped.putIfAbsent(key, () => <ReaderModeArticle>[]).add(item);
    }
    return grouped;
  }

  Map<String, List<WebSession>> _groupSessionsByDomain() {
    final grouped = <String, List<WebSession>>{};
    for (final session in _sessions) {
      final key = session.domain.trim().isEmpty
          ? session.sourceId
          : session.domain;
      grouped.putIfAbsent(key, () => <WebSession>[]).add(session);
    }
    return grouped;
  }

  String _formatSessionTime(DateTime time) {
    final year = time.year.toString().padLeft(4, '0');
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  List<WebNovelSource> get _visibleSources {
    final query = _sourceFilterText.trim().toLowerCase();
    if (query.isEmpty) {
      return _sources;
    }
    return _indexedSources
        .where((entry) => entry.searchKey.contains(query))
        .map((entry) => entry.source)
        .toList(growable: false);
  }

  String get _selectedSourceLabel {
    if ((_selectedSourceId ?? '_all') == '_all') {
      return '全部书源';
    }
    for (final source in _sources) {
      if (source.id == _selectedSourceId) {
        return _safeText(source.name);
      }
    }
    return '选择书源';
  }

  String _sourceNameById(String sourceId) {
    for (final source in _sources) {
      if (source.id == sourceId) {
        return _safeText(source.name);
      }
    }
    return sourceId;
  }

  List<String> get _availableSearchTags {
    final tags = <String>{};
    for (final source in _sources) {
      for (final tag in source.tags) {
        final trimmed = tag.trim();
        if (trimmed.isNotEmpty) {
          tags.add(trimmed);
        }
      }
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  String get _selectedTagSummary {
    if (_selectedSearchTags.isEmpty) {
      return '全部标签';
    }
    final sorted = _selectedSearchTags.toList()..sort();
    if (sorted.length <= 2) {
      return sorted.join(' / ');
    }
    return '${sorted.take(2).join(' / ')} 等 ${sorted.length} 项';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _isDesktop ? 4 : 2, vsync: this)
      ..addListener(() {
        if (_tabController.index == 1 && !_shouldBuildBrowserTab) {
          setState(() => _shouldBuildBrowserTab = true);
        }
      });
    _searchResultsTabController = TabController(length: 2, vsync: this)
      ..addListener(_updateSearchBackToTop);
    _aggregatedResultsController.addListener(_updateSearchBackToTop);
    _rawResultsController.addListener(_updateSearchBackToTop);
    _searchConcurrency = ref.read(globalSettingsProvider).searchConcurrency;
    _pullToRefreshController = _supportsEmbeddedBrowser
        ? PullToRefreshController(
            settings: PullToRefreshSettings(enabled: true),
            onRefresh: () async {
              final controller = _browserController;
              if (controller == null) {
                await _pullToRefreshController?.endRefreshing();
                return;
              }
              await controller.reload();
            },
          )
        : null;
    final initialUrl = widget.initialBrowserUrl?.trim() ?? '';
    if (initialUrl.isNotEmpty) {
      _browserUrl = initialUrl;
      _browserInputController.text = initialUrl;
      if (!_isDesktop) {
        _shouldBuildBrowserTab = true;
        _tabController.index = 1;
      }
    }
    _reloadAll();
  }

  @override
  void dispose() {
    _backgroundReloadTimer?.cancel();
    _tabController.dispose();
    _searchResultsTabController.dispose();
    _aggregatedResultsController.dispose();
    _rawResultsController.dispose();
    _bookSearchController.dispose();
    _browserInputController.dispose();
    _sourceFilterController.dispose();
    _pullToRefreshController?.dispose();
    _bookSearchSubscription?.cancel();
    _searchUpdateDebounce?.cancel();
    _autoRecognitionDebounce?.cancel();
    super.dispose();
  }

  Future<void> _reloadAll({bool scheduleRetryOnFailure = true}) async {
    if (mounted) {
      setState(() {
        _pageLoading = true;
        _loadError = null;
      });
    }

    var hadFailure = false;
    try {
      try {
        await _repository.prewarm().timeout(_repositoryPrewarmTimeout);
      } catch (error) {
        hadFailure = true;
        await AppRunLogService.instance.logError(
          'WebNovel prewarm failed: $error',
        );
      }

      final sources = await _loadRepositorySection<List<WebNovelSource>>(
        'sources',
        _repository.listSources,
        fallback: const <WebNovelSource>[],
        onError: () => hadFailure = true,
      );
      final providers = await _loadRepositorySection<List<WebSearchProvider>>(
        'providers',
        _repository.listSearchProviders,
        fallback: const <WebSearchProvider>[],
        onError: () => hadFailure = true,
      );
      final sessions = await _loadRepositorySection<List<WebSession>>(
        'sessions',
        _repository.listSessions,
        fallback: const <WebSession>[],
        onError: () => hadFailure = true,
      );
      final history = await _loadRepositorySection<List<ReaderModeArticle>>(
        'history',
        _repository.listReaderHistory,
        fallback: const <ReaderModeArticle>[],
        onError: () => hadFailure = true,
      );

      if (!mounted) {
        return;
      }

      final loadError = sources.isEmpty && providers.isEmpty && hadFailure
          ? '网文数据暂时不可用，可重试。'
          : hadFailure
          ? '部分网文数据加载失败，已尽量恢复。'
          : null;
      setState(() {
        _pageLoading = false;
        _loadError = loadError;
        _sources = sources;
        _indexedSources = sources
            .map(_SourceListEntry.fromSource)
            .toList(growable: false);
        _providers = providers;
        _sessions = sessions;
        _history = history;
        _selectedSourceId ??= sources.isEmpty ? null : '_all';
        _selectedProviderId ??= providers.isEmpty ? null : providers.first.id;
      });

      if (loadError == '网文数据暂时不可用，可重试。' && scheduleRetryOnFailure) {
        _scheduleBackgroundReload();
      }
    } catch (error) {
      await AppRunLogService.instance.logError(
        'WebNovel page reload failed unexpectedly: $error',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _pageLoading = false;
        _loadError = '网文数据暂时不可用，可重试。';
      });
      if (scheduleRetryOnFailure) {
        _scheduleBackgroundReload();
      }
    }
  }

  void _scheduleBackgroundReload() {
    if (_backgroundReloadTimer != null) {
      return;
    }
    _backgroundReloadTimer = Timer(const Duration(seconds: 1), () async {
      if (!mounted) {
        _backgroundReloadTimer = null;
        return;
      }
      try {
        await _reloadAll(scheduleRetryOnFailure: false);
      } finally {
        _backgroundReloadTimer = null;
      }
    });
  }

  Future<void> _runWithBusy(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _searchBooks() async {
    final query = _bookSearchController.text.trim();
    if (query.isEmpty) {
      await _bookSearchSubscription?.cancel();
      _searchUpdateDebounce?.cancel();
      _pendingSearchUpdate = null;
      setState(() {
        _bookSearchAttempted = false;
        _bookResults = const <WebNovelSearchResult>[];
        _aggregatedResults = const <WebNovelAggregatedResult>[];
        _lastBookSearchReport = null;
      });
      return;
    }

    await _bookSearchSubscription?.cancel();
    _bookSearchRequestId += 1;
    _aiRerankRequestId += 1;
    final requestId = _bookSearchRequestId;

    await _runWithBusy(() async {
      try {
        final sourceId = _selectedSourceId == '_all' ? null : _selectedSourceId;
        final requiredTags = sourceId == null
            ? _selectedSearchTags.toList(growable: false)
            : const <String>[];
        if (sourceId == null &&
            requiredTags.isNotEmpty &&
            _availableSearchTags.isNotEmpty) {
          final available = _availableSearchTags.toSet();
          final effective = requiredTags
              .where((tag) => available.contains(tag))
              .toList();
          if (effective.isEmpty) {
            if (!mounted) {
              return;
            }
            setState(() {
              _bookSearchAttempted = true;
              _bookResults = const <WebNovelSearchResult>[];
              _aggregatedResults = const <WebNovelAggregatedResult>[];
            });
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('当前标签下没有可用书源，请调整筛选')));
            return;
          }
        }

        if (!mounted) {
          return;
        }
        setState(() {
        _bookSearchAttempted = true;
        _bookResults = const <WebNovelSearchResult>[];
        _aggregatedResults = const <WebNovelAggregatedResult>[];
        _lastBookSearchReport = null;
      });
      _aiRerankRequestId++;

        final settings = ref.read(globalSettingsProvider);
        final completer = Completer<void>();
        _bookSearchSubscription = _repository
            .searchBooksStream(
              query,
              sourceId: sourceId,
              maxConcurrent: _searchConcurrency,
              requiredTags: requiredTags,
              enableQueryExpansion: _enableSearchQueryExpansion,
              enableWebFallback: settings.enableWebFallbackInBookSearch,
            )
            .listen(
          (update) {
            if (requestId != _bookSearchRequestId) {
              return;
            }
            _scheduleSearchUpdate(update);
            if (update.isFinal && !completer.isCompleted) {
              completer.complete();
            }
          },
          onError: (error, stackTrace) {
            unawaited(
              AppRunLogService.instance.logError(
                'WebNovel search stream failed: $query; $error\n$stackTrace',
              ),
            );
            if (!mounted || requestId != _bookSearchRequestId) {
              if (!completer.isCompleted) {
                completer.complete();
              }
              return;
            }
            setState(() {
              _bookSearchAttempted = true;
              _bookResults = const <WebNovelSearchResult>[];
              _aggregatedResults = const <WebNovelAggregatedResult>[];
              _lastBookSearchReport = null;
            });
            final message = error is TimeoutException
                ? '搜书超时：可尝试降低并发、切换书源或关闭关键词扩展后重试。'
                : '搜书失败：$error';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.redAccent,
              ),
            );
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onDone: () {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
        );

        await completer.future.timeout(_searchTimeout);
      } catch (error) {
        await AppRunLogService.instance.logError(
          'WebNovel search failed: $query; $error',
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _bookSearchAttempted = true;
          _bookResults = const <WebNovelSearchResult>[];
          _aggregatedResults = const <WebNovelAggregatedResult>[];
          _lastBookSearchReport = null;
        });
        final message = error is TimeoutException
            ? '搜书超时：可尝试降低并发、切换书源或关闭关键词扩展后重试。'
            : '搜书失败：$error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  int _nextSearchConcurrency() {
    const options = <int>[2, 4, 6, 8, 10, 12];
    final current = options.indexOf(_searchConcurrency);
    return current == -1 ? options.first : options[(current + 1) % options.length];
  }

  String _searchFailureSummary(WebNovelSearchReport report) {
    if (report.totalSources == 0) {
      return '当前筛选下没有可用书源，请调整标签或切换书源后重试。';
    }
    if (!report.hasFailures) {
      return '';
    }
    final counts = report.failureCounts;
    final parts = <String>[];
    void add(WebNovelSearchFailureType type, String label) {
      final value = counts[type] ?? 0;
      if (value > 0) {
        parts.add('$label $value');
      }
    }

    add(WebNovelSearchFailureType.timeout, '超时');
    add(WebNovelSearchFailureType.network, '网络');
    add(WebNovelSearchFailureType.http, 'HTTP');
    add(WebNovelSearchFailureType.parse, '解析');
    add(WebNovelSearchFailureType.rule, '规则');
    add(WebNovelSearchFailureType.unknown, '未知');

    if (parts.isEmpty) {
      return '';
    }
    return '失败：${parts.join(' · ')}';
  }

  String _bookSearchEmptyHintText() {
    if (!_bookSearchAttempted) {
      return '先搜索，再把识别出的结果加入书架';
    }
    final report = _lastBookSearchReport;
    final summary = report == null ? '' : _searchFailureSummary(report);
    if (summary.isEmpty) {
      return '没有找到可直接入库的结果';
    }
    return '没有找到可直接入库的结果\n$summary\n建议：降低并发 / 切换书源 / 稍后重试';
  }

  Widget _buildSearchResultsPanel() {
    if (_bookResults.isEmpty) {
      return Center(
        child: Text(
          _bookSearchEmptyHintText(),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: [
        if (_aiRerankApplied)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                const Chip(
                  label: Text('AI 已排序'),
                  visualDensity: VisualDensity.compact,
                ),
                if (_aiFilteredCount > 0)
                  Chip(
                    label: Text('过滤 $_aiFilteredCount 条非小说'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ),
        TabBar(
          controller: _searchResultsTabController,
          isScrollable: true,
          tabs: [
            Tab(text: '相关结果 (${_aggregatedResults.length})'),
            Tab(text: '相关书源 (${_bookResults.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _searchResultsTabController,
            children: [
              _buildAggregatedResultsList(),
              _buildRawResultsList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAggregatedResultsList() {
    if (_aggregatedResults.isEmpty) {
      return const Center(child: Text('暂无聚合结果'));
    }
    return ListView.builder(
      controller: _aggregatedResultsController,
      itemCount: _aggregatedResults.length,
      itemBuilder: (context, index) {
        final aggregated = _aggregatedResults[index];
        final title = _safeText(aggregated.title);
        final author = _safeText(aggregated.author);
        final description = _safeText(aggregated.description);
        final hasWebFallback = aggregated.sources.any(
          (item) => item.origin == WebNovelSearchResultOrigin.providerFallback,
        );
        return ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(title),
          subtitle: Text(
            [
              author,
              description,
            ].where((item) => item.trim().isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Chip(
                label: Text('${aggregated.sourceCount} 源'),
                visualDensity: VisualDensity.compact,
              ),
              if (hasWebFallback)
                const Chip(
                  label: Text('网页兜底'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          onTap: () => _showAggregatedResultDetail(aggregated),
        );
      },
    );
  }

  Widget _buildRawResultsList() {
    return ListView.builder(
      controller: _rawResultsController,
      itemCount: _bookResults.length,
      itemBuilder: (context, index) {
        final result = _bookResults[index];
        final safeTitle = sanitizeUiText(
          result.title,
          fallback: result.title,
        );
        final safeAuthor = sanitizeUiText(
          result.author,
          fallback: result.author,
        );
        final safeDescription = sanitizeUiText(
          result.description,
          fallback: result.description,
        );
        final sourceLabel = _sourceNameById(result.sourceId);
        final originLabel =
            result.origin == WebNovelSearchResultOrigin.providerFallback
                ? '网页兜底'
                : '';
        return ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(safeTitle),
          subtitle: Text(
            [
              sourceLabel,
              originLabel,
              safeAuthor,
              safeDescription,
            ].where((item) => item.trim().isNotEmpty).join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: IconButton(
            onPressed: () => _addSearchResult(result),
            icon: const Icon(Icons.library_add),
          ),
          onTap: () => _openBrowserTarget(result.detailUrl),
        );
      },
    );
  }

  Future<void> _showAggregatedResultDetail(
    WebNovelAggregatedResult aggregated,
  ) async {
    if (aggregated.sources.isEmpty) {
      return;
    }
    final primary = aggregated.sources.first;
    WebNovelSearchResult? resolved;
    var resolving = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final display = resolved ?? primary;
            final title = _safeText(display.title);
            final author = _safeText(display.author);
            final description = _safeText(display.description);
            final status = _extractStatusLabel(description);
            final wordCount = _extractWordCountLabel(description);
            final statusLineParts = <String>[
              if (status.isNotEmpty) '状态：$status',
              if (wordCount.isNotEmpty) '字数：$wordCount',
            ];
            final statusLine = statusLineParts.isEmpty
                ? '状态：未知 · 字数：未知'
                : statusLineParts.join(' · ');
            final sourceLabel = _sourceNameById(display.sourceId);
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (author.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('作者：$author'),
                    ],
                    const SizedBox(height: 6),
                    Text(statusLine),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        description,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text('来源：$sourceLabel · ${aggregated.sourceCount} 个书源'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _addSearchResult(display),
                          icon: const Icon(Icons.library_add),
                          label: const Text('加入书架'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _openBrowserTarget(display.detailUrl),
                          icon: const Icon(Icons.open_in_browser),
                          label: const Text('打开网页'),
                        ),
                        TextButton.icon(
                          onPressed: resolving
                              ? null
                              : () async {
                                  setSheetState(() => resolving = true);
                                  try {
                                    final updated =
                                        await _repository.resolveSearchResultDetail(
                                      display,
                                    );
                                    if (!context.mounted) {
                                      return;
                                    }
                                    setSheetState(() {
                                      resolved = updated;
                                      resolving = false;
                                    });
                                  } catch (error) {
                                    if (!context.mounted) {
                                      return;
                                    }
                                    setSheetState(() => resolving = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('详情补齐失败：$error'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                },
                          icon: const Icon(Icons.auto_fix_high),
                          label: Text(resolving ? '补齐中…' : '补齐信息'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '相关书源',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: aggregated.sources.length,
                        itemBuilder: (context, index) {
                          final sourceItem = aggregated.sources[index];
                          final sourceName = _sourceNameById(sourceItem.sourceId);
                          final originLabel = sourceItem.origin ==
                                  WebNovelSearchResultOrigin.providerFallback
                              ? '网页兜底'
                              : '';
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              _safeText(sourceItem.title),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              [
                                sourceName,
                                originLabel,
                                _safeText(sourceItem.author),
                              ].where((item) => item.trim().isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.library_add),
                              onPressed: () => _addSearchResult(sourceItem),
                            ),
                            onTap: () => _openBrowserTarget(sourceItem.detailUrl),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showSearchSourcePicker() async {
    final controller = TextEditingController();
    var query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final normalized = query.trim().toLowerCase();
            final filtered = normalized.isEmpty
                ? _sources
                : _indexedSources
                      .where((entry) => entry.searchKey.contains(normalized))
                      .map((entry) => entry.source)
                      .toList(growable: false);
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: '搜索书源（名称 / 域名 / 标签）',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          ListTile(
                            leading: Icon(
                              (_selectedSourceId ?? '_all') == '_all'
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            title: const Text('全部书源'),
                            subtitle: Text('已启用 ${_sources.length} 个书源'),
                            onTap: () {
                              setState(() => _selectedSourceId = '_all');
                              Navigator.pop(context);
                            },
                          ),
                          for (final source in filtered)
                            ListTile(
                              leading: Icon(
                                _selectedSourceId == source.id
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                              ),
                              title: Text(_safeText(source.name)),
                              subtitle: Text(
                                _safeText(source.baseUrl),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                setState(() => _selectedSourceId = source.id);
                                Navigator.pop(context);
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showTagFilterSheet() async {
    final tags = _availableSearchTags;
    if (tags.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前没有可用的标签')));
      return;
    }
    final selection = <String>{..._selectedSearchTags};
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.filter_alt_outlined),
                        const SizedBox(width: 8),
                        Text(
                          '书源标签筛选',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: selection.isEmpty
                              ? null
                              : () => setSheetState(selection.clear),
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tag in tags)
                          FilterChip(
                            selected: selection.contains(tag),
                            label: Text(tag),
                            onSelected: (value) {
                              setSheetState(() {
                                if (value) {
                                  selection.add(tag);
                                } else {
                                  selection.remove(tag);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              setState(() {
                                _selectedSearchTags
                                  ..clear()
                                  ..addAll(selection);
                              });
                              Navigator.pop(context);
                            },
                            child: const Text('应用'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openBrowserTarget([String? input]) async {
    final raw = (input ?? _browserInputController.text).trim();
    if (raw.isEmpty) {
      return;
    }

    final directUri = _resolveDirectBrowserUri(raw);
    final usedKeywordSearch = directUri == null;
    final target = directUri?.toString() ?? _resolveBrowserInput(raw);
    if (target.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有可用的网页搜索源')));
      return;
    }

    _lastBrowserKeyword = usedKeywordSearch ? raw : null;
    _browserInputController.text = usedKeywordSearch ? raw : target;
    setState(() {
      _browserLoading = true;
      _browserUrl = target;
      _recognitionState = _BrowserRecognitionState.idle;
      _recognitionError = '';
      if (_preview?.article.url != target) {
        _preview = null;
      }
    });

    final controller = _browserController;
    if (controller != null) {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(target)));
      return;
    }

    if (mounted) {
      setState(() => _browserLoading = false);
    }
  }

  Future<void> _refreshBrowserNavigationState() async {
    final controller = _browserController;
    if (controller == null || !mounted) {
      return;
    }
    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) {
      return;
    }
    setState(() {
      _browserCanGoBack = canGoBack;
      _browserCanGoForward = canGoForward;
    });
  }

  Future<String> _resolveBrowserUserAgent(
    InAppWebViewController controller,
  ) async {
    try {
      final settings = await controller.getSettings();
      final userAgent = settings?.userAgent?.trim();
      if (userAgent != null && userAgent.isNotEmpty) {
        return userAgent;
      }
    } catch (_) {}
    try {
      final value = await controller.evaluateJavascript(
        source: 'navigator.userAgent',
      );
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    } catch (_) {}
    return '';
  }

  List<Map<String, dynamic>> _mapCookies(
    List<Cookie> cookies,
    String fallbackDomain,
  ) {
    final normalizedDomain = fallbackDomain.trim().toLowerCase();
    final unique = <String, Map<String, dynamic>>{};
    for (final cookie in cookies) {
      final name = cookie.name.trim();
      if (name.isEmpty) {
        continue;
      }
      final domain = (cookie.domain ?? normalizedDomain).trim().toLowerCase();
      final path = (cookie.path ?? '/').trim();
      final key = '$domain|$path|$name';
      unique[key] = {
        'name': name,
        'value': (cookie.value ?? '').toString(),
        'domain': domain,
        'path': path.isEmpty ? '/' : path,
        'expiresDate': cookie.expiresDate,
        'isSecure': cookie.isSecure,
        'isHttpOnly': cookie.isHttpOnly,
        'sameSite': cookie.sameSite?.toValue(),
      };
    }
    return unique.values.toList(growable: false);
  }

  Future<void> _saveCurrentWebSession() async {
    if (!_supportsEmbeddedBrowser) {
      return;
    }
    final url = _browserUrl.trim();
    final controller = _browserController;
    if (url.isEmpty || controller == null) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前页面无法保存会话')));
      return;
    }

    final source = _resolveSourceForHost(uri.host);
    final domain = _resolveSessionDomain(uri.host, source);
    final cookieManager = CookieManager.instance();
    final cookies = await cookieManager.getCookies(
      url: WebUri(uri.toString()),
      webViewController: controller,
    );
    final mapped = _mapCookies(cookies, domain);
    if (mapped.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前页面暂无可保存的 Cookie')));
      return;
    }
    final userAgent = await _resolveBrowserUserAgent(controller);
    await _repository.saveCookieMaps(
      sourceId: source?.id ?? domain,
      domain: domain,
      cookies: mapped,
      userAgent: userAgent,
    );
    await _refreshSessions();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已保存会话（$domain，${mapped.length} 条 Cookie）')),
    );
  }

  Future<void> _applySessionToBrowser(WebSession session) async {
    if (!_supportsEmbeddedBrowser) {
      return;
    }
    final controller = _browserController;
    if (controller == null) {
      return;
    }
    final domain = session.domain.trim().isEmpty
        ? session.sourceId.trim()
        : session.domain.trim();
    if (domain.isEmpty) {
      return;
    }
    final target = Uri.parse('https://$domain/');
    final manager = CookieManager.instance();
    await manager.deleteCookies(url: WebUri(target.toString()), domain: domain);
    for (final cookie in session.cookies) {
      final name = (cookie['name'] ?? '').toString().trim();
      final value = (cookie['value'] ?? '').toString();
      if (name.isEmpty) {
        continue;
      }
      final sameSiteValue = cookie['sameSite']?.toString();
      await manager.setCookie(
        url: WebUri(target.toString()),
        name: name,
        value: value,
        path: (cookie['path'] ?? '/').toString(),
        domain: (cookie['domain'] ?? domain).toString(),
        expiresDate: cookie['expiresDate'] as int?,
        isSecure: cookie['isSecure'] as bool?,
        isHttpOnly: cookie['isHttpOnly'] as bool?,
        sameSite: HTTPCookieSameSitePolicy.fromValue(sameSiteValue),
        webViewController: controller,
      );
    }
    if (session.userAgent.trim().isNotEmpty) {
      await controller.setSettings(
        settings: InAppWebViewSettings(userAgent: session.userAgent),
      );
    }
    await controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(target.toString())),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _browserUrl = target.toString();
      _browserLoading = true;
    });
    await _refreshBrowserNavigationState();
  }

  Future<void> _removeHistoryEntry(ReaderModeArticle item) async {
    await _repository.clearReaderHistoryEntry(item.url);
    await _refreshHistory();
  }

  Future<void> _clearHistoryEntries(Iterable<ReaderModeArticle> items) async {
    for (final item in items) {
      await _repository.clearReaderHistoryEntry(item.url);
    }
    await _refreshHistory();
  }

  Future<void> _removeSession(WebSession session) async {
    await _repository.clearSession(session.id);
    await _refreshSessions();
  }

  Future<void> _clearSessionEntries(Iterable<WebSession> sessions) async {
    for (final session in sessions) {
      await _repository.clearSession(session.id);
    }
    await _refreshSessions();
  }

  Future<void> _applyBrowserReaderOptimization() async {
    final controller = _browserController;
    if (controller == null) {
      return;
    }
    final enabled = _readerOptimizationEnabled;
    final script =
        '''
      (() => {
        const styleId = 'wenwen-reader-opt-style';
        let style = document.getElementById(styleId);
        if (!style) {
          style = document.createElement('style');
          style.id = styleId;
          document.head.appendChild(style);
        }
        document.documentElement.classList.toggle('wenwen-reader-opt', ${enabled ? 'true' : 'false'});
        document.body?.classList?.toggle('wenwen-reader-opt', ${enabled ? 'true' : 'false'});
        style.textContent = ${enabled ? "`html.wenwen-reader-opt{scroll-behavior:smooth;scroll-padding-top:16px;background:#f5efe2;}body.wenwen-reader-opt{margin:0 auto!important;max-width:920px!important;padding:18px 18px 32px!important;line-height:1.9!important;font-size:18px!important;background:#f5efe2!important;color:#1e1a16!important;}html.wenwen-reader-opt img,body.wenwen-reader-opt img{max-width:100%!important;height:auto!important;border-radius:12px!important;}html.wenwen-reader-opt p,body.wenwen-reader-opt p{margin:0 0 1em!important;}html.wenwen-reader-opt [data-wenwen-fixed='1'],body.wenwen-reader-opt [data-wenwen-fixed='1']{display:none!important;}`" : "''"};
        if (${enabled ? 'true' : 'false'}) {
          document.querySelectorAll('*').forEach((node) => {
            const computed = window.getComputedStyle(node);
            const isOverlay = (computed.position === 'fixed' || computed.position === 'sticky') && (node.innerText || '').length < 120;
            if (isOverlay) {
              node.setAttribute('data-wenwen-fixed', '1');
            }
          });
        } else {
          document.querySelectorAll('[data-wenwen-fixed]').forEach((node) => node.removeAttribute('data-wenwen-fixed'));
        }
      })();
    ''';
    await controller.evaluateJavascript(source: script);
  }

  Future<void> _applySearchEngineNavigationPatch() async {
    final controller = _browserController;
    final host = Uri.tryParse(_browserUrl)?.host.toLowerCase() ?? '';
    final shouldPatchHost =
        host.contains('baidu.com') ||
        host.contains('sogou.com') ||
        host.contains('so.com') ||
        host.contains('sohu.com');
    if (controller == null || host.isEmpty || !shouldPatchHost) {
      return;
    }
    const patchScript = r'''
      (() => {
        if (window.__wenwenNavPatchApplied) return;
        window.__wenwenNavPatchApplied = true;
        const resolveUrl = (raw) => {
          if (!raw) return '';
          const value = String(raw).trim();
          if (!value) return '';
          if (value.startsWith('//')) return `${location.protocol}${value}`;
          if (value.startsWith('http://') || value.startsWith('https://')) return value;
          if (value.startsWith('/')) return `${location.origin}${value}`;
          if (value.startsWith('javascript:')) return '';
          try { return new URL(value, location.href).toString(); } catch (_) { return ''; }
        };
        const candidateFromAnchor = (anchor) => {
          const attrs = [
            'href',
            'data-href',
            'data-url',
            'url',
            'mu',
            'data-link',
            'data-mdurl',
            'data-jump',
            'data-src',
            'data-target',
            'data-landurl',
          ];
          for (const key of attrs) {
            const raw = anchor.getAttribute(key);
            const resolved = resolveUrl(raw);
            if (resolved) return resolved;
          }
          return '';
        };
        const forceNavigate = (raw) => {
          const resolved = resolveUrl(raw);
          if (!resolved) return false;
          window.location.href = resolved;
          return true;
        };
        document.querySelectorAll('a[target]').forEach((anchor) => anchor.setAttribute('target', '_self'));
        const originalOpen = window.open;
        window.open = function(url, target, features) {
          if (forceNavigate(url)) return null;
          if (typeof originalOpen === 'function') {
            return originalOpen.call(window, url, target, features);
          }
          return null;
        };
        document.addEventListener('click', (event) => {
          const anchor = event.target && event.target.closest ? event.target.closest('a') : null;
          if (!anchor) return;
          const target = (anchor.getAttribute('target') || '').toLowerCase();
          const candidate = candidateFromAnchor(anchor);
          if (!candidate) return;
          if (target === '_blank' || target === 'blank' || anchor.hasAttribute('onclick')) {
            event.preventDefault();
            event.stopPropagation();
            forceNavigate(candidate);
          }
        }, true);
      })();
    ''';
    await controller.evaluateJavascript(source: patchScript);
  }

  Future<void> _setReaderOptimizationEnabled(bool enabled) async {
    setState(() => _readerOptimizationEnabled = enabled);
    await _applyBrowserReaderOptimization();
  }

  Future<void> _scrollBrowserToEdge({required bool top}) async {
    final controller = _browserController;
    if (controller == null) {
      return;
    }
    await controller.evaluateJavascript(
      source: top
          ? 'window.scrollTo({ top: 0, behavior: "smooth" });'
          : 'window.scrollTo({ top: document.documentElement.scrollHeight, behavior: "smooth" });',
    );
  }

  Uri? _resolveDirectBrowserUri(String input) {
    final normalized = input.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final parsed = Uri.tryParse(normalized);
    if (parsed == null) {
      return null;
    }
    if (parsed.scheme == 'http' || parsed.scheme == 'https') {
      return parsed;
    }
    if (normalized.startsWith('//')) {
      final current = Uri.tryParse(_browserUrl);
      final scheme = current == null || current.scheme.isEmpty
          ? 'https'
          : current.scheme;
      return Uri.tryParse('$scheme:$normalized');
    }
    if (!parsed.hasScheme && parsed.host.isNotEmpty) {
      return Uri.tryParse('https://$normalized');
    }

    final current = Uri.tryParse(_browserUrl);
    final canResolveRelative =
        current != null &&
        (current.scheme == 'http' || current.scheme == 'https') &&
        !normalized.contains(' ');
    if (!canResolveRelative) {
      return null;
    }
    final looksLikeRelativeUrl =
        normalized.startsWith('/') ||
        normalized.startsWith('?') ||
        normalized.startsWith('#') ||
        normalized.startsWith('./') ||
        normalized.startsWith('../') ||
        normalized.contains('/') ||
        normalized.contains('.');
    if (!looksLikeRelativeUrl) {
      return null;
    }
    return current.resolveUri(parsed);
  }

  String? _resolveHttpFallbackFromDeepLink(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      return null;
    }
    for (final key in const <String>[
      'url',
      'u',
      'ru',
      'jumpurl',
      'jump_url',
      'link',
      'target',
      'targeturl',
      'to',
      'dest',
      'destination',
      'fromurl',
      'srcurl',
      'rurl',
      'redirect',
    ]) {
      final value = uri.queryParameters[key];
      if (value == null || value.trim().isEmpty) {
        continue;
      }
      final parsed = _decodeHttpLikeDeepLink(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
    final fromPath = _decodeHttpLikeDeepLink(uri.path);
    if (fromPath != null) {
      return fromPath;
    }
    final fromFragment = _decodeHttpLikeDeepLink(uri.fragment);
    if (fromFragment != null) {
      return fromFragment;
    }
    return null;
  }

  String? _decodeHttpLikeDeepLink(String raw) {
    var current = raw.trim();
    for (var i = 0; i < 3; i++) {
      final direct = _parseHttpLikeUrl(current);
      if (direct != null) {
        return direct;
      }
      final decoded = Uri.decodeFull(current).trim();
      if (decoded.isEmpty || decoded == current) {
        break;
      }
      current = decoded;
    }
    return _parseHttpLikeUrl(current);
  }

  String? _parseHttpLikeUrl(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    if (raw.startsWith('//')) {
      return 'https:$raw';
    }
    final parsed = Uri.tryParse(raw);
    if (parsed == null) {
      return null;
    }
    if (parsed.scheme == 'http' || parsed.scheme == 'https') {
      return parsed.toString();
    }
    if (!parsed.hasScheme && parsed.host.isNotEmpty) {
      return Uri.tryParse('https://$raw')?.toString();
    }
    return null;
  }

  String _resolveBrowserInput(String input) {
    final provider = _providers.firstWhere(
      (item) => item.id == _selectedProviderId,
      orElse: () => _providers.isEmpty
          ? const WebSearchProvider(
              id: '',
              name: '',
              searchUrlTemplate: '',
              resultListSelector: '',
              resultTitleSelector: '',
              resultUrlSelector: '',
              resultSnippetSelector: '',
            )
          : _providers.first,
    );
    if (provider.searchUrlTemplate.isEmpty) {
      return '';
    }
    return provider.searchUrlTemplate.replaceAll(
      '{query}',
      Uri.encodeComponent(input),
    );
  }

  TranslationConfig? _activeAiConfig(GlobalSettings settings) {
    if (settings.translationConfigs.isEmpty) {
      return null;
    }
    return settings.translationConfigs.firstWhere(
      (config) => config.id == settings.translationConfigId,
      orElse: () => settings.translationConfigs.first,
    );
  }

  Future<void> _handleProviderChanged(String? value) async {
    if (value == null || value == _selectedProviderId) {
      return;
    }
    setState(() => _selectedProviderId = value);
    var keyword = _lastBrowserKeyword?.trim();
    if (keyword == null || keyword.isEmpty) {
      final typed = _browserInputController.text.trim();
      if (typed.isNotEmpty && _resolveDirectBrowserUri(typed) == null) {
        keyword = typed;
      }
    }
    if (keyword == null || keyword.isEmpty) {
      return;
    }
    await _openBrowserTarget(keyword);
  }

  Future<String?> _loadBrowserHtml() async {
    final controller = _browserController;
    if (controller == null) {
      return null;
    }
    try {
      final result = await controller.evaluateJavascript(
        source: 'document.documentElement ? document.documentElement.outerHTML : ""',
      );
      if (result == null) {
        return null;
      }
      if (result is String) {
        return result;
      }
      return result.toString();
    } catch (_) {
      return null;
    }
  }

  Future<bool> _handleBackPressed() async {
    if (_isDesktop) {
      return true;
    }
    if (_tabController.index != 1) {
      return true;
    }
    final controller = _browserController;
    if (controller == null) {
      return true;
    }
    final canGoBack = await controller.canGoBack();
    if (canGoBack) {
      await controller.goBack();
      await _refreshBrowserNavigationState();
      return false;
    }
    return true;
  }

  Future<void> _recognizeCurrentPage() async {
    final url = _browserUrl.trim();
    if (url.isEmpty || _recognizingPage) {
      return;
    }

    setState(() {
      _recognizingPage = true;
      _recognitionState = _BrowserRecognitionState.loading;
      _recognitionError = '';
    });
    try {
      ReaderModeDetectionResult preview;
      final html = await _loadBrowserHtml();
      if (html != null && html.trim().isNotEmpty) {
        preview = await _repository.detectReaderModeFromHtml(
          html: html,
          url: url,
        );
      } else {
        preview = await _repository.detectReaderMode(url);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _preview = preview;
        _recognitionState = _BrowserRecognitionState.recognized;
        _recognitionError = '';
      });
      await _refreshHistory();
    } catch (error) {
      await AppRunLogService.instance.logError(
        'WebNovel reader-mode detection failed: $url; $error',
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _recognitionState = _BrowserRecognitionState.failed;
        _recognitionError = error.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('识别当前页失败：$error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _recognizingPage = false);
      }
    }
  }

  void _scheduleAutoRecognition() {
    final settings = ref.read(globalSettingsProvider);
    if (!settings.autoDetectReaderMode) {
      return;
    }
    if (_browserUrl.isEmpty) {
      return;
    }
    final preview = _preview;
    if (preview != null &&
        preview.article.url == _browserUrl &&
        _recognitionState == _BrowserRecognitionState.recognized) {
      return;
    }
    _autoRecognitionDebounce?.cancel();
    _autoRecognitionDebounce = Timer(const Duration(milliseconds: 650), () {
      if (!mounted || _recognizingPage) {
        return;
      }
      unawaited(_recognizeCurrentPage());
    });
  }

  Future<void> _addSearchResult(WebNovelSearchResult result) async {
    await _runWithBusy(() async {
      final meta = await _repository.addBookFromSearchResult(result);
      ref.invalidate(booksProvider);
      unawaited(_warmupBookCache(meta.id));
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已加入书架，正在后台获取目录')));
    });
  }

  List<String> _addBookCandidateUrls() {
    final candidates = <String>[];
    final seen = <String>{};

    void addCandidate(String raw) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (seen.add(trimmed)) {
        candidates.add(trimmed);
      }
    }

    final preview = _preview;
    if (preview != null) {
      final tocLinks = preview.article.detectedTocLinks
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false)
        ..sort((left, right) => _compareTocLinkPriority(left, right));
      for (final link in tocLinks) {
        addCandidate(link);
      }
      addCandidate(preview.article.url);
    }
    final current = _browserUrl.trim();
    if (current.isNotEmpty) {
      addCandidate(current);
    }
    return candidates;
  }

  int _tocLinkPriority(String url) {
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

  int _compareTocLinkPriority(String left, String right) {
    final diff = _tocLinkPriority(left) - _tocLinkPriority(right);
    if (diff != 0) {
      return diff;
    }
    return left.compareTo(right);
  }

  Future<WebNovelBookMeta> _addBookFromBestCandidate() async {
    final candidates = _addBookCandidateUrls();
    if (candidates.isEmpty) {
      throw Exception('当前页面为空，无法加入书架');
    }

    Object? lastError;
    for (final url in candidates) {
      try {
        return await _repository.addBookFromUrl(url);
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception(lastError?.toString() ?? '未识别到可入库资源');
  }

  Future<void> _warmupBookCache(String webBookId) async {
    try {
      final enqueued = await _runEventTracker.track<int>(
        action: 'webnovel.cache_warmup',
        context: <String, Object?>{
          'web_book_id': webBookId,
          'start_index': 0,
          'end_index': _autoCacheChapterCount - 1,
          'background': true,
        },
        isCancelled: () => !mounted,
        operation: () => _repository.cacheBookChapters(
          webBookId,
          startIndex: 0,
          endIndex: _autoCacheChapterCount - 1,
          background: true,
        ),
      );
      if (mounted && enqueued > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加入后台预缓存任务：$enqueued 章（可在缓存管理查看进度）')),
        );
      }
    } catch (error) {
      if (error is AppOperationCancelledException) {
        return;
      }
    }
  }

  void _applySearchUpdate(WebNovelSearchUpdate update) {
    if (!mounted) {
      return;
    }
    setState(() {
      _bookSearchAttempted = true;
      _bookResults = update.results;
      _aggregatedResults = update.aggregatedResults;
      _lastBookSearchReport = update.toReport();
      _aiRerankApplied = false;
      _aiFilteredCount = 0;
    });
  }

  void _scheduleSearchUpdate(WebNovelSearchUpdate update) {
    if (update.isFinal) {
      _searchUpdateDebounce?.cancel();
      _searchUpdateDebounce = null;
      _pendingSearchUpdate = null;
      _applySearchUpdate(update);
      _triggerAiRerank(update);
      return;
    }

    _pendingSearchUpdate = update;
    _searchUpdateDebounce ??= Timer(const Duration(milliseconds: 180), () {
      final pending = _pendingSearchUpdate;
      _pendingSearchUpdate = null;
      _searchUpdateDebounce = null;
      if (pending != null) {
        _applySearchUpdate(pending);
      }
    });
  }

  void _updateSearchBackToTop() {
    final controller = _searchResultsTabController.index == 0
        ? _aggregatedResultsController
        : _rawResultsController;
    final shouldShow = controller.hasClients && controller.offset > 240;
    if (shouldShow == _showSearchBackToTop) {
      return;
    }
    if (mounted) {
      setState(() => _showSearchBackToTop = shouldShow);
    } else {
      _showSearchBackToTop = shouldShow;
    }
  }

  void _scrollSearchResultsToTop() {
    final controller = _searchResultsTabController.index == 0
        ? _aggregatedResultsController
        : _rawResultsController;
    if (!controller.hasClients) {
      return;
    }
    controller.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void _triggerAiRerank(WebNovelSearchUpdate update) {
    final settings = ref.read(globalSettingsProvider);
    if (!settings.enableAiSearchBoost) {
      return;
    }
    final config = _activeAiConfig(settings);
    if (config == null) {
      return;
    }
    if (update.aggregatedResults.isEmpty) {
      return;
    }
    final requestId = ++_aiRerankRequestId;
    unawaited(() async {
      final rerankResult = await _aiSearchService.rerankAggregatedResults(
        query: update.query,
        results: update.aggregatedResults,
        config: config,
      );
      if (!mounted || requestId != _aiRerankRequestId) {
        return;
      }
      setState(() {
        _aggregatedResults = rerankResult.results;
        _aiRerankApplied = rerankResult.applied;
        _aiFilteredCount = rerankResult.filteredCount;
      });
    }());
  }

  Future<void> _addCurrentBrowserPage() async {
    await _runWithBusy(() async {
      try {
        final meta = await _addBookFromBestCandidate();
        ref.invalidate(booksProvider);
        unawaited(_warmupBookCache(meta.id));
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已加入书架，正在后台获取目录')));
      } catch (error) {
        await AppRunLogService.instance.logError(
          'add browser book failed: $error',
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('加入书架失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<WebNovelBookMeta?> _findExistingBrowserMeta() async {
    final candidates = _addBookCandidateUrls();
    for (final url in candidates) {
      final existing = await _repository.findBookMetaByUrl(url);
      if (existing != null) {
        return existing;
      }
    }
    return null;
  }

  Future<WebNovelBookMeta> _ensureBrowserBookAdded() async {
    try {
      return await _addBookFromBestCandidate();
    } catch (error) {
      final existing = await _findExistingBrowserMeta();
      if (existing != null) {
        return existing;
      }
      rethrow;
    }
  }

  Future<Book?> _findLibraryBookById(String id) async {
    final service = ref.read(libraryServiceProvider);
    final snapshot = await service.loadBooksSnapshot();
    for (final book in snapshot.books) {
      if (book.id == id) {
        return book;
      }
    }
    return null;
  }

  Future<void> _enterReaderModeFromBrowser() async {
    await _runWithBusy(() async {
      try {
        final meta = await _ensureBrowserBookAdded();
        ref.invalidate(booksProvider);
        final book = await _findLibraryBookById(meta.libraryBookId);
        if (book == null || book.id.isEmpty) {
          throw Exception('未在书架中找到该书');
        }
        if (!mounted) {
          return;
        }
        context.push('/reader', extra: book);
      } catch (error) {
        await AppRunLogService.instance.logError(
          'enter reader mode failed: $error',
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('进入阅读模式失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _cacheRemainingFromBrowser() async {
    await _runWithBusy(() async {
      try {
        final meta = await _ensureBrowserBookAdded();
        final chapters = await _repository.getChapters(meta.id);
        if (chapters.isEmpty) {
          throw Exception('未识别到章节目录，无法缓存');
        }
        final currentUrl = (_preview?.article.url ?? _browserUrl).trim();
        var startIndex = 0;
        if (currentUrl.isNotEmpty) {
          final normalizedCurrent = Uri.tryParse(currentUrl)
                  ?.replace(fragment: '')
                  .toString() ??
              currentUrl;
          final matchIndex = chapters.indexWhere((chapter) {
            final normalized = Uri.tryParse(chapter.url)
                    ?.replace(fragment: '')
                    .toString() ??
                chapter.url;
            return normalized == normalizedCurrent;
          });
          if (matchIndex >= 0) {
            startIndex = matchIndex;
          }
        }
        final enqueued = await _repository.cacheBookChapters(
          meta.id,
          startIndex: startIndex,
          background: true,
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已加入缓存任务：$enqueued 章（可在缓存管理查看进度）')),
        );
      } catch (error) {
        await AppRunLogService.instance.logError(
          'cache remaining failed: $error',
        );
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('缓存失败：$error'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  Future<void> _importSourcesFromFile() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (picked == null || picked.files.single.path == null) {
      return;
    }
    await _runWithBusy(() async {
      final text = await io.File(picked.files.single.path!).readAsString();
      final report = await _repository.importSourcesInputWithReport(text);
      await _reloadAll();
      if (mounted) {
        await _showImportReport(report);
      }
    });
  }

  Future<void> _importSourcesFromPaste() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴书源 JSON / Legado 链接'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('支持直接粘贴 JSON、Legado 导入链接，或指向书源 JSON 的 http(s) 地址。'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 12,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) {
      return;
    }
    await _runWithBusy(() async {
      final report = await _repository.importSourcesInputWithReport(text);
      await _reloadAll();
      if (mounted) {
        await _showImportReport(report);
      }
    });
  }

  Future<void> _showImportReport(SourceImportReport report) async {
    final failedCount = report.entries
        .where((entry) => entry.status == SourceImportEntryStatus.failed)
        .length;
    final skippedCount = report.entries
        .where((entry) => entry.status == SourceImportEntryStatus.skipped)
        .length;
    final message =
        '导入 ${report.importedCount}/${report.totalEntries}（更新 ${report.updatedCount}），兼容映射 ${report.legacyMappedCount}，跳过 $skippedCount，失败 $failedCount。';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );

    String statusLabel(SourceImportEntryStatus status) {
      switch (status) {
        case SourceImportEntryStatus.imported:
          return '导入';
        case SourceImportEntryStatus.updated:
          return '更新';
        case SourceImportEntryStatus.skipped:
          return '跳过';
        case SourceImportEntryStatus.failed:
          return '失败';
      }
    }

    final issues = report.entries
        .where(
          (entry) =>
              entry.status != SourceImportEntryStatus.imported ||
              entry.warnings.isNotEmpty ||
              (entry.message.isNotEmpty && entry.message != '导入成功'),
        )
        .toList(growable: false);
    if (issues.isEmpty) {
      return;
    }

    const limit = 200;
    final visible = issues.take(limit).toList(growable: false);
    final truncated = issues.length > visible.length;
    final lines = <String>[
      message,
      if (truncated) '（仅展示前 $limit 条，共 ${issues.length} 条）',
      '',
      for (final entry in visible)
        [
          '#${entry.index} [${statusLabel(entry.status)}]',
          if (entry.sourceName.trim().isNotEmpty) entry.sourceName.trim(),
          if (entry.sourceId.trim().isNotEmpty) '(${entry.sourceId.trim()})',
          if (entry.legacyMapped) '[Legado]',
          if (entry.message.trim().isNotEmpty) entry.message.trim(),
          ...entry.warnings.map((item) => '  - $item'),
        ].join(' '),
    ];
    final detailText = lines.join('\n');

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入报告'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(child: SelectableText(detailText)),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: detailText));
              if (!context.mounted) {
                return;
              }
              Navigator.pop(context);
              if (!mounted) {
                return;
              }
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('导入报告已复制')));
            },
            child: const Text('复制报告'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSources() async {
    final payload = await _repository.exportSourcesJson();
    if (!mounted) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('自定义书源 JSON 已复制到剪贴板')));
  }

  Future<void> _showReaderModeSheet() async {
    final preview = _preview;
    if (preview == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.article.pageTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                '${preview.article.siteName} · 置信度 ${(preview.article.confidence * 100).toStringAsFixed(0)}%',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: SelectableText(preview.article.contentText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDetectedTocSheet() async {
    final links = _preview?.article.detectedTocLinks ?? const <String>[];
    if (links.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前页面未识别到目录链接')));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: links.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final link = links[index];
          return ListTile(
            title: Text(link),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pop(context);
              unawaited(_openBrowserTarget(link));
            },
          );
        },
      ),
    );
  }

  Widget _buildSourceTile(WebNovelSource source) {
    return Card(
      child: ListTile(
        title: Text(_safeText(source.name)),
        subtitle: Text(
          '${_safeText(source.baseUrl)}\n'
          '${source.tags.map(_safeText).where((tag) => tag.isNotEmpty).join(' / ')}',
        ),
        isThreeLine: true,
        trailing: Switch(
          value: source.enabled,
          onChanged: (value) async {
            await _repository.setSourceEnabled(source.id, value);
            await _reloadAll();
          },
        ),
        onTap: () async {
          final result = await _repository.testSource(source);
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(result.message)));
        },
      ),
    );
  }

  Widget _buildSourcesSheetBody() {
    return StatefulBuilder(
      builder: (context, setSheetState) {
        final filtered = _visibleSources;
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: _importSourcesFromFile,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('导入文件'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _importSourcesFromPaste,
                          icon: const Icon(Icons.paste),
                          label: const Text('粘贴导入'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _exportSources,
                          icon: const Icon(Icons.file_copy_outlined),
                          label: const Text('导出自定义 JSON'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _sourceFilterController,
                      decoration: InputDecoration(
                        hintText: '筛选书源（名称 / 域名 / 标签）',
                        border: const OutlineInputBorder(),
                        suffixText: '${filtered.length}/${_sources.length}',
                      ),
                      onChanged: (value) {
                        _sourceFilterText = value;
                        setSheetState(() {});
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  prototypeItem: filtered.isEmpty
                      ? null
                      : _buildSourceTile(filtered.first),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) =>
                      _buildSourceTile(filtered[index]),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSourcesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _buildSourcesSheetBody(),
    );
  }

  Future<void> _showSessionsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Icon(Icons.cookie_outlined),
                const SizedBox(width: 8),
                Text('会话', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ..._buildSessionCards(compact: true),
          ],
        ),
      ),
    );
  }

  Future<void> _showHistorySheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Icon(Icons.history),
                const SizedBox(width: 8),
                Text('浏览历史', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _history.isEmpty
                      ? null
                      : () async {
                          await _repository.clearReaderHistory();
                          await _refreshHistory();
                          if (context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('清空'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._buildHistoryCards(compact: true),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildHistoryCards({bool compact = false}) {
    final grouped = _groupHistoryByDomain();
    if (grouped.isEmpty) {
      return const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('当前还没有浏览历史。'),
          ),
        ),
      ];
    }
    final keys = grouped.keys.toList()..sort();
    final widgets = <Widget>[];
    for (final key in keys) {
      final items = grouped[key] ?? const <ReaderModeArticle>[];
      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('${items.length} 条'),
                    IconButton(
                      onPressed: items.isEmpty
                          ? null
                          : () => _clearHistoryEntries(items),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '清除此站点历史',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final item in items)
                  ListTile(
                    dense: compact,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      item.pageTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(item.siteName),
                    onTap: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                      unawaited(_openBrowserTarget(item.url));
                    },
                    trailing: IconButton(
                      onPressed: () => _removeHistoryEntry(item),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildSessionCards({bool compact = false}) {
    final grouped = _groupSessionsByDomain();
    if (grouped.isEmpty) {
      return const [
        Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('当前还没有保存的会话。'),
          ),
        ),
      ];
    }
    final keys = grouped.keys.toList()..sort();
    final widgets = <Widget>[];
    for (final key in keys) {
      final items = grouped[key] ?? const <WebSession>[];
      widgets.add(
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text('${items.length} 个'),
                    IconButton(
                      onPressed: items.isEmpty
                          ? null
                          : () => _clearSessionEntries(items),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '清除此站点会话',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final session in items)
                  ListTile(
                    dense: compact,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cookie_outlined),
                    title: Text(session.sourceId),
                    subtitle: Text(
                      '更新时间：${_formatSessionTime(session.updatedAt)}',
                    ),
                    onTap: () async {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                      await _applySessionToBrowser(session);
                    },
                    trailing: IconButton(
                      onPressed: () => _removeSession(session),
                      icon: const Icon(Icons.close),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  Widget _buildLoadFailureState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    _loadError ?? '网文数据暂时不可用，可重试。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _reloadAll,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadWarningBanner(String message) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _reloadAll, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasContent =
        _sources.isNotEmpty ||
        _providers.isNotEmpty ||
        _sessions.isNotEmpty ||
        _history.isNotEmpty;
    final tabs = _isDesktop
        ? const <Tab>[
            Tab(text: '搜书'),
            Tab(text: '网页搜索'),
            Tab(text: '书源'),
            Tab(text: '会话'),
          ]
        : const <Tab>[Tab(text: '搜书'), Tab(text: '网页搜索')];

    return WillPopScope(
      onWillPop: _handleBackPressed,
      child: DefaultTabController(
        length: tabs.length,
        child: Scaffold(
        appBar: AppBar(
          title: const Text('网文中心'),
          actions: [
            if (!_isDesktop)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'sources') {
                    if (context.mounted) {
                      context.push('/source-files');
                    }
                  } else if (value == 'cache') {
                    unawaited(
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WebNovelCacheScreen(),
                        ),
                      ),
                    );
                  } else if (value == 'sessions') {
                    unawaited(_showSessionsSheet());
                  } else if (value == 'save_session') {
                    unawaited(_saveCurrentWebSession());
                  } else if (value == 'history') {
                    unawaited(_showHistorySheet());
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'save_session', child: Text('保存会话')),
                  PopupMenuItem(value: 'sources', child: Text('书源管理')),
                  PopupMenuItem(value: 'cache', child: Text('缓存')),
                  PopupMenuItem(value: 'sessions', child: Text('会话')),
                  PopupMenuItem(value: 'history', child: Text('历史')),
                ],
              ),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: tabs,
          ),
        ),
        body: _pageLoading && !hasContent
            ? const Center(child: CircularProgressIndicator())
            : _loadError != null && !hasContent
            ? _buildLoadFailureState()
            : Stack(
                children: [
                  Column(
                    children: [
                      if (_loadError != null)
                        _buildLoadWarningBanner(_loadError!),
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            _isDesktop
                                ? _buildBookSearchTab()
                                : _buildMobileBookSearchTab(),
                            _shouldBuildBrowserTab
                                ? _buildBrowserTab()
                                : _buildBrowserPlaceholder(),
                            if (_isDesktop) _buildSourcesDesktopTab(),
                            if (_isDesktop) _buildSessionsDesktopTab(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (_busy)
                    const Positioned.fill(
                      child: ColoredBox(
                        color: Color(0x33000000),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  if (_tabController.index == 0 && _showSearchBackToTop)
                    Positioned(
                      right: 16,
                      bottom: 16,
                      child: FloatingActionButton.small(
                        onPressed: _scrollSearchResultsToTop,
                        child: const Icon(Icons.vertical_align_top),
                      ),
                    ),
                ],
              ),
        ),
      ),
    );
  }

  Widget _buildBookSearchTab() {
    final globalSettings = ref.watch(globalSettingsProvider);
    final globalSettingsNotifier = ref.read(globalSettingsProvider.notifier);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SizedBox(
                width: 420,
                child: TextField(
                  controller: _bookSearchController,
                  decoration: const InputDecoration(
                    hintText: '输入书名、作者',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _searchBooks(),
                ),
              ),
              DropdownButton<String>(
                value: _selectedSourceId,
                items: [
                  const DropdownMenuItem(value: '_all', child: Text('全部书源')),
                  ..._sources.map(
                    (source) => DropdownMenuItem(
                      value: source.id,
                      child: Text(_safeText(source.name)),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _selectedSourceId = value),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _availableSearchTags.isEmpty
                        ? null
                        : _showTagFilterSheet,
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: Text(_selectedTagSummary),
                  ),
                  if (_selectedSearchTags.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(_selectedSearchTags.clear),
                      icon: const Icon(Icons.clear),
                      label: const Text('清空标签'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilterChip(
                    selected: _enableSearchQueryExpansion,
                    label: const Text('关键词扩展'),
                    onSelected: (value) =>
                        setState(() => _enableSearchQueryExpansion = value),
                  ),
                  FilterChip(
                    selected: globalSettings.enableWebFallbackInBookSearch,
                    label: const Text('网页兜底'),
                    onSelected: (value) => globalSettingsNotifier
                        .setEnableWebFallbackInBookSearch(value),
                  ),
                  Tooltip(
                    message: '并发越高越快但更易超时，点按可切换 2/4/6/8/10/12',
                    child: ActionChip(
                      label: Text('并发 $_searchConcurrency'),
                      onPressed: () {
                        final next = _nextSearchConcurrency();
                        setState(() => _searchConcurrency = next);
                        globalSettingsNotifier.setSearchConcurrency(next);
                      },
                    ),
                  ),
                ],
              ),
              FilledButton(onPressed: _searchBooks, child: const Text('搜索')),
            ],
          ),
        ),
        if ((_selectedSourceId ?? '_all') == '_all' && _sources.length > 24)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              globalSettings.enableWebFallbackInBookSearch
                  ? '全部书源模式会优先搜索高优先级书源，结果不足时再补网页兜底。'
                  : '全部书源模式会优先搜索高优先级书源，默认不启用网页兜底。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(child: _buildSearchResultsPanel()),
      ],
    );
  }

  Widget _buildBrowserTab() {
    final initialBrowserTarget = _browserUrl.isEmpty
        ? _resolveBrowserInput('小说')
        : _browserUrl;
    final browser = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _browserInputController,
                      decoration: const InputDecoration(
                        hintText: '输入关键词搜索，或直接粘贴网页 URL',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _openBrowserTarget(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _openBrowserTarget,
                    child: const Text('打开'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey<String?>(_selectedProviderId),
                      initialValue: _selectedProviderId,
                      decoration: const InputDecoration(
                        labelText: '网页搜索引擎',
                        border: OutlineInputBorder(),
                      ),
                      items: _providers
                          .map(
                            (provider) => DropdownMenuItem(
                              value: provider.id,
                              child: Text(provider.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          unawaited(_handleProviderChanged(value)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _recognizingPage ? null : _recognizeCurrentPage,
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('识别当前页'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: _buildBrowserQuickActions(),
              ),
            ],
          ),
        ),
        Expanded(
          child: _supportsEmbeddedBrowser
              ? InAppWebView(
                  initialSettings: InAppWebViewSettings(
                    javaScriptEnabled: true,
                    supportZoom: true,
                    builtInZoomControls: true,
                    displayZoomControls: false,
                    javaScriptCanOpenWindowsAutomatically: true,
                    horizontalScrollBarEnabled: true,
                    verticalScrollBarEnabled: true,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    useHybridComposition: true,
                    transparentBackground: false,
                    useShouldOverrideUrlLoading: true,
                  ),
                  initialUrlRequest: initialBrowserTarget.isEmpty
                      ? null
                      : URLRequest(url: WebUri(initialBrowserTarget)),
                  gestureRecognizers: _webViewGestureRecognizers,
                  pullToRefreshController: _pullToRefreshController,
                  onWebViewCreated: (controller) {
                    _browserController = controller;
                    unawaited(_refreshBrowserNavigationState());
                  },
                  shouldOverrideUrlLoading: (_, navigationAction) async {
                    final nextUrl = navigationAction.request.url?.toString();
                    if (nextUrl != null) {
                      final parsed = Uri.tryParse(nextUrl);
                      if (parsed != null &&
                          parsed.scheme.isNotEmpty &&
                          parsed.scheme != 'http' &&
                          parsed.scheme != 'https' &&
                          parsed.scheme != 'about' &&
                          parsed.scheme != 'data' &&
                          parsed.scheme != 'javascript') {
                        final fallback = _resolveHttpFallbackFromDeepLink(
                          nextUrl,
                        );
                        if (fallback != null) {
                          await _browserController?.loadUrl(
                            urlRequest: URLRequest(url: WebUri(fallback)),
                          );
                        }
                        return NavigationActionPolicy.CANCEL;
                      }
                    }
                    if (nextUrl != null && mounted) {
                      setState(() {
                        _browserLoading = true;
                        _browserUrl = nextUrl;
                        _recognitionState = _BrowserRecognitionState.idle;
                        _recognitionError = '';
                        if (_preview?.article.url != nextUrl) {
                          _preview = null;
                        }
                      });
                    }
                    return NavigationActionPolicy.ALLOW;
                  },
                  onCreateWindow: (controller, createWindowRequest) async {
                    final nextUrl = createWindowRequest.request.url;
                    if (nextUrl == null) {
                      await controller.evaluateJavascript(
                        source: '''
                          (() => {
                            const active = document.activeElement;
                            const href = active?.getAttribute?.('href') || active?.href || '';
                            if (href) {
                              window.location.href = href;
                            }
                          })();
                        ''',
                      );
                      return true;
                    }
                    await controller.loadUrl(
                      urlRequest: URLRequest(url: nextUrl),
                    );
                    return true;
                  },
                  onLoadStart: (_, url) {
                    setState(() {
                      _browserLoading = true;
                      _browserUrl = url?.toString() ?? _browserUrl;
                      _recognitionState = _BrowserRecognitionState.idle;
                      _recognitionError = '';
                      if (_preview?.article.url != _browserUrl) {
                        _preview = null;
                      }
                    });
                    unawaited(_refreshBrowserNavigationState());
                  },
                  onLoadStop: (_, url) async {
                    await _pullToRefreshController?.endRefreshing();
                    await _applySearchEngineNavigationPatch();
                    await _applyBrowserReaderOptimization();
                    await _refreshBrowserNavigationState();
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _browserLoading = false;
                      _browserUrl = url?.toString() ?? _browserUrl;
                    });
                    _scheduleAutoRecognition();
                  },
                  onReceivedError: (_, _, _) async {
                    await _pullToRefreshController?.endRefreshing();
                    await _refreshBrowserNavigationState();
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      _browserLoading = false;
                      _recognitionState = _BrowserRecognitionState.failed;
                      _recognitionError = '页面加载失败';
                    });
                  },
                )
              : _buildBrowserFallback(),
        ),
      ],
    );

    if (_isDesktop) {
      return Row(
        children: [
          Expanded(flex: 7, child: browser),
          Container(
            width: 360,
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: _buildBrowserSidePanel(),
          ),
        ],
      );
    }

    return browser;
  }

  Widget _buildBrowserFallback() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.public_off_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '当前环境未注册内嵌浏览器，仍可粘贴 URL 后执行识别和加入书架。',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SelectableText(
                    _browserUrl.isEmpty ? '尚未打开页面' : _browserUrl,
                    maxLines: 3,
                  ),
                  if (_history.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '最近识别',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    for (final item in _history.take(5))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.pageTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(item.siteName),
                        onTap: () => _openBrowserTarget(item.url),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBookSearchTab() {
    final globalSettings = ref.watch(globalSettingsProvider);
    final globalSettingsNotifier = ref.read(globalSettingsProvider.notifier);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _bookSearchController,
                decoration: const InputDecoration(
                  hintText: '输入书名、作者或关键词',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onSubmitted: (_) => _searchBooks(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sources.isEmpty
                          ? null
                          : _showSearchSourcePicker,
                      icon: const Icon(Icons.source_outlined),
                      label: Text(
                        _selectedSourceLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _searchBooks,
                    icon: const Icon(Icons.search),
                    label: const Text('搜索'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _availableSearchTags.isEmpty
                        ? null
                        : _showTagFilterSheet,
                    icon: const Icon(Icons.filter_alt_outlined),
                    label: Text(_selectedTagSummary),
                  ),
                  if (_selectedSearchTags.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => setState(_selectedSearchTags.clear),
                      icon: const Icon(Icons.clear),
                      label: const Text('清空标签'),
                    ),
                  FilterChip(
                    selected: _enableSearchQueryExpansion,
                    label: const Text('关键词扩展'),
                    onSelected: (value) =>
                        setState(() => _enableSearchQueryExpansion = value),
                  ),
                  FilterChip(
                    selected: globalSettings.enableAiSearchBoost,
                    label: const Text('AI 搜索增强'),
                    onSelected: (value) {
                      globalSettingsNotifier.setEnableAiSearchBoost(value);
                      if (value) {
                        final config = _activeAiConfig(globalSettings);
                        if (config == null ||
                            config.baseUrl.trim().isEmpty ||
                            config.modelName.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('AI 未配置完成，请先在设置中补全 API 配置'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  FilterChip(
                    selected: globalSettings.enableWebFallbackInBookSearch,
                    label: const Text('网页兜底'),
                    onSelected: (value) => globalSettingsNotifier
                        .setEnableWebFallbackInBookSearch(value),
                  ),
                  ActionChip(
                    label: Text('并发 $_searchConcurrency'),
                    onPressed: () {
                      final next = _nextSearchConcurrency();
                      setState(() => _searchConcurrency = next);
                      globalSettingsNotifier.setSearchConcurrency(next);
                    },
                  ),
                  ActionChip(
                    label: const Text('书源管理'),
                    avatar: const Icon(Icons.source_outlined, size: 18),
                    onPressed: () {
                      if (context.mounted) {
                        context.push('/source-files');
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        if ((_selectedSourceId ?? '_all') == '_all' && _sources.length > 24)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              '全部书源模式会优先搜索高优先级书源，并在命中后尽早返回，避免手机端长时间卡住。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(child: _buildSearchResultsPanel()),
      ],
    );
  }

  Widget _buildBrowserPlaceholder() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.public, size: 42),
                  const SizedBox(height: 16),
                  const Text(
                    '网页搜索按需加载，切到这个标签时才会初始化浏览器，避免网文页一打开就卡顿。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      if (!_shouldBuildBrowserTab) {
                        setState(() => _shouldBuildBrowserTab = true);
                      }
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('初始化网页搜索'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrowserSidePanel() {
    return Column(
      children: [
        _buildBrowserStatusCard(),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('最近识别', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final item in _history.take(8))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    item.pageTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(item.siteName),
                  onTap: () => _openBrowserTarget(item.url),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrowserQuickActions() {
    final settings = ref.watch(globalSettingsProvider);
    final notifier = ref.read(globalSettingsProvider.notifier);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        IconButton.filledTonal(
          onPressed: _browserCanGoBack
              ? () async {
                  await _browserController?.goBack();
                  await _refreshBrowserNavigationState();
                }
              : null,
          icon: const Icon(Icons.arrow_back),
          tooltip: '后退',
        ),
        IconButton.filledTonal(
          onPressed: _browserCanGoForward
              ? () async {
                  await _browserController?.goForward();
                  await _refreshBrowserNavigationState();
                }
              : null,
          icon: const Icon(Icons.arrow_forward),
          tooltip: '前进',
        ),
        OutlinedButton.icon(
          onPressed: _browserUrl.isEmpty
              ? null
              : () => _scrollBrowserToEdge(top: true),
          icon: const Icon(Icons.vertical_align_top),
          label: const Text('顶部'),
        ),
        FilterChip(
          selected: _readerOptimizationEnabled,
          label: const Text('阅读优化'),
          onSelected: (_) =>
              _setReaderOptimizationEnabled(!_readerOptimizationEnabled),
        ),
        FilterChip(
          selected: settings.autoDetectReaderMode,
          label: const Text('自动识别'),
          onSelected: (value) => notifier.setAutoDetectReaderMode(value),
        ),
      ],
    );
  }

  Widget _buildBrowserStatusCard({bool compact = false}) {
    final preview = _preview;
    final recognized = preview != null && preview.article.url == _browserUrl;
    IconData statusIcon;
    Color statusColor;
    String statusText;
    switch (_recognitionState) {
      case _BrowserRecognitionState.loading:
        statusIcon = Icons.autorenew;
        statusColor = Colors.orange;
        statusText = '识别中';
        break;
      case _BrowserRecognitionState.recognized:
        statusIcon = Icons.check_circle;
        statusColor = Colors.green;
        statusText = preview?.isLikelyNovel == true ? '已识别为可读网文页面' : '已识别为可读网页';
        break;
      case _BrowserRecognitionState.failed:
        statusIcon = Icons.error_outline;
        statusColor = Colors.redAccent;
        statusText = _recognitionError.isEmpty
            ? '识别失败'
            : '识别失败：$_recognitionError';
        break;
      case _BrowserRecognitionState.idle:
        if (_browserLoading) {
          statusIcon = Icons.hourglass_bottom;
          statusColor = Colors.orange;
          statusText = '页面加载中';
        } else if (_browserUrl.isEmpty) {
          statusIcon = Icons.pending_outlined;
          statusColor = Colors.orange;
          statusText = '未加载页面';
        } else {
          statusIcon = recognized ? Icons.check_circle : Icons.pending_outlined;
          statusColor = recognized ? Colors.green : Colors.orange;
          statusText = recognized ? '已识别' : '未识别';
        }
        break;
    }

    return Card(
      margin: compact
          ? const EdgeInsets.fromLTRB(16, 16, 16, 8)
          : const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              compact ? '当前页面' : '网页搜索工作区',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _browserUrl.isEmpty ? '尚未打开页面' : _browserUrl,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(statusText)),
              ],
            ),
            const SizedBox(height: 12),
            _buildBrowserQuickActions(),
            if (preview != null) ...[
              const SizedBox(height: 12),
              Text(
                preview.article.pageTitle,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                preview.article.contentText,
                maxLines: compact ? 3 : 8,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: preview == null ? null : _showReaderModeSheet,
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('Info'),
                ),
                FilledButton.icon(
                  onPressed: preview == null ? null : _enterReaderModeFromBrowser,
                  icon: const Icon(Icons.chrome_reader_mode),
                  label: const Text('进入阅读模式'),
                ),
                OutlinedButton.icon(
                  onPressed: _browserUrl.isEmpty
                      ? null
                      : _addCurrentBrowserPage,
                  icon: const Icon(Icons.library_add),
                  label: const Text('加入书架'),
                ),
                OutlinedButton.icon(
                  onPressed: _browserUrl.isEmpty
                      ? null
                      : _cacheRemainingFromBrowser,
                  icon: const Icon(Icons.download_for_offline_outlined),
                  label: const Text('缓存剩余章节'),
                ),
                OutlinedButton.icon(
                  onPressed: preview == null ? null : _showDetectedTocSheet,
                  icon: const Icon(Icons.list_alt),
                  label: const Text('目录'),
                ),
                OutlinedButton.icon(
                  onPressed: _browserUrl.isEmpty
                      ? null
                      : () => _openBrowserTarget(_browserUrl),
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('原网页'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesDesktopTab() {
    final filtered = _visibleSources;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _importSourcesFromFile,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('导入文件'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _importSourcesFromPaste,
                    icon: const Icon(Icons.paste),
                    label: const Text('粘贴导入'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _exportSources,
                    icon: const Icon(Icons.file_copy_outlined),
                    label: const Text('导出自定义 JSON'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sourceFilterController,
                decoration: InputDecoration(
                  hintText: '筛选书源（名称 / 域名 / 标签）',
                  border: const OutlineInputBorder(),
                  suffixText: '${filtered.length}/${_sources.length}',
                ),
                onChanged: (value) => setState(() => _sourceFilterText = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            prototypeItem: filtered.isEmpty
                ? null
                : _buildSourceTile(filtered.first),
            itemCount: filtered.length,
            itemBuilder: (context, index) => _buildSourceTile(filtered[index]),
          ),
        ),
      ],
    );
    // ignore: dead_code
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _importSourcesFromFile,
              icon: const Icon(Icons.upload_file),
              label: const Text('导入文件'),
            ),
            OutlinedButton.icon(
              onPressed: _importSourcesFromPaste,
              icon: const Icon(Icons.paste),
              label: const Text('粘贴导入'),
            ),
            OutlinedButton.icon(
              onPressed: _exportSources,
              icon: const Icon(Icons.file_copy_outlined),
              label: const Text('导出自定义 JSON'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final source in _sources)
          Card(
            child: ListTile(
              title: Text(_safeText(source.name)),
              subtitle: Text(
                '${_safeText(source.baseUrl)}\n'
                '${source.tags.map(_safeText).where((tag) => tag.isNotEmpty).join(' / ')}',
              ),
              isThreeLine: true,
              trailing: Switch(
                value: source.enabled,
                onChanged: (value) async {
                  await _repository.setSourceEnabled(source.id, value);
                  await _reloadAll();
                },
              ),
              onTap: () async {
                final result = await _repository.testSource(source);
                if (!mounted) {
                  return;
                }
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(result.message)));
              },
            ),
          ),
      ],
    );
  }

  Widget _buildSessionsDesktopTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Icon(Icons.history),
            const SizedBox(width: 8),
            Text('浏览历史', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: _history.isEmpty
                  ? null
                  : () async {
                      await _repository.clearReaderHistory();
                      await _refreshHistory();
                    },
              icon: const Icon(Icons.delete_outline),
              label: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ..._buildHistoryCards(),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.cookie_outlined),
            const SizedBox(width: 8),
            Text('会话', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 12),
        ..._buildSessionCards(),
      ],
    );
  }
}

class _SourceListEntry {
  const _SourceListEntry({required this.source, required this.searchKey});

  factory _SourceListEntry.fromSource(WebNovelSource source) =>
      _SourceListEntry(
        source: source,
        searchKey: sanitizeUiText(
          '${source.name}\n${source.baseUrl}\n${source.tags.join('\n')}',
          fallback: '',
        ).toLowerCase(),
      );

  final WebNovelSource source;
  final String searchKey;
}
