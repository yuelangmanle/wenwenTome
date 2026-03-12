import 'dart:convert';

enum RuleSelectorType { css, regex, xpath, jsonPath, legado }

enum HttpMethod { get, post }

class SelectorRule {
  const SelectorRule({
    this.type = RuleSelectorType.css,
    required this.expression,
    this.attr,
    this.absoluteUrl = false,
    this.defaultValue = '',
    this.regex,
  });

  final RuleSelectorType type;
  final String expression;
  final String? attr;
  final bool absoluteUrl;
  final String defaultValue;
  final String? regex;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'expression': expression,
    'attr': attr,
    'absoluteUrl': absoluteUrl,
    'defaultValue': defaultValue,
    'regex': regex,
  };

  factory SelectorRule.fromJson(Map<String, dynamic> json) => SelectorRule(
    type: RuleSelectorType.values.firstWhere(
      (item) => item.name == json['type'],
      orElse: () => RuleSelectorType.css,
    ),
    expression: json['expression'] as String? ?? '',
    attr: json['attr'] as String?,
    absoluteUrl: json['absoluteUrl'] as bool? ?? false,
    defaultValue: json['defaultValue'] as String? ?? '',
    regex: json['regex'] as String?,
  );
}

class BookSourceSearchRule {
  const BookSourceSearchRule({
    required this.method,
    required this.pathTemplate,
    this.queryField = 'q',
    this.itemSelector = '',
    this.titleRule = const SelectorRule(expression: ''),
    this.urlRule = const SelectorRule(expression: ''),
    this.authorRule = const SelectorRule(expression: ''),
    this.coverRule = const SelectorRule(expression: ''),
    this.descriptionRule = const SelectorRule(expression: ''),
    this.useSearchProviderFallback = false,
  });

  final HttpMethod method;
  final String pathTemplate;
  final String queryField;
  final String itemSelector;
  final SelectorRule titleRule;
  final SelectorRule urlRule;
  final SelectorRule authorRule;
  final SelectorRule coverRule;
  final SelectorRule descriptionRule;
  final bool useSearchProviderFallback;

  Map<String, dynamic> toJson() => {
    'method': method.name,
    'pathTemplate': pathTemplate,
    'queryField': queryField,
    'itemSelector': itemSelector,
    'titleRule': titleRule.toJson(),
    'urlRule': urlRule.toJson(),
    'authorRule': authorRule.toJson(),
    'coverRule': coverRule.toJson(),
    'descriptionRule': descriptionRule.toJson(),
    'useSearchProviderFallback': useSearchProviderFallback,
  };

  factory BookSourceSearchRule.fromJson(
    Map<String, dynamic> json,
  ) => BookSourceSearchRule(
    method: HttpMethod.values.firstWhere(
      (item) => item.name == json['method'],
      orElse: () => HttpMethod.get,
    ),
    pathTemplate: json['pathTemplate'] as String? ?? '',
    queryField: json['queryField'] as String? ?? 'q',
    itemSelector: json['itemSelector'] as String? ?? '',
    titleRule: SelectorRule.fromJson(
      json['titleRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    urlRule: SelectorRule.fromJson(
      json['urlRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    authorRule: SelectorRule.fromJson(
      json['authorRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    coverRule: SelectorRule.fromJson(
      json['coverRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    descriptionRule: SelectorRule.fromJson(
      json['descriptionRule'] as Map<String, dynamic>? ??
          const {'expression': ''},
    ),
    useSearchProviderFallback:
        json['useSearchProviderFallback'] as bool? ?? false,
  );
}

class BookSourceDetailRule {
  const BookSourceDetailRule({
    this.titleRule = const SelectorRule(expression: ''),
    this.authorRule = const SelectorRule(expression: ''),
    this.coverRule = const SelectorRule(expression: ''),
    this.descriptionRule = const SelectorRule(expression: ''),
    this.firstChapterRule = const SelectorRule(expression: ''),
    this.chapterListUrlRule = const SelectorRule(expression: ''),
  });

  final SelectorRule titleRule;
  final SelectorRule authorRule;
  final SelectorRule coverRule;
  final SelectorRule descriptionRule;
  final SelectorRule firstChapterRule;
  final SelectorRule chapterListUrlRule;

  Map<String, dynamic> toJson() => {
    'titleRule': titleRule.toJson(),
    'authorRule': authorRule.toJson(),
    'coverRule': coverRule.toJson(),
    'descriptionRule': descriptionRule.toJson(),
    'firstChapterRule': firstChapterRule.toJson(),
    'chapterListUrlRule': chapterListUrlRule.toJson(),
  };

  factory BookSourceDetailRule.fromJson(
    Map<String, dynamic> json,
  ) => BookSourceDetailRule(
    titleRule: SelectorRule.fromJson(
      json['titleRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    authorRule: SelectorRule.fromJson(
      json['authorRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    coverRule: SelectorRule.fromJson(
      json['coverRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    descriptionRule: SelectorRule.fromJson(
      json['descriptionRule'] as Map<String, dynamic>? ??
          const {'expression': ''},
    ),
    firstChapterRule: SelectorRule.fromJson(
      json['firstChapterRule'] as Map<String, dynamic>? ??
          const {'expression': ''},
    ),
    chapterListUrlRule: SelectorRule.fromJson(
      json['chapterListUrlRule'] as Map<String, dynamic>? ??
          const {'expression': ''},
    ),
  );
}

class BookSourceChapterRule {
  const BookSourceChapterRule({
    required this.itemSelector,
    this.titleRule = const SelectorRule(expression: ''),
    this.urlRule = const SelectorRule(expression: ''),
    this.reverse = false,
  });

  final String itemSelector;
  final SelectorRule titleRule;
  final SelectorRule urlRule;
  final bool reverse;

  Map<String, dynamic> toJson() => {
    'itemSelector': itemSelector,
    'titleRule': titleRule.toJson(),
    'urlRule': urlRule.toJson(),
    'reverse': reverse,
  };

  factory BookSourceChapterRule.fromJson(Map<String, dynamic> json) =>
      BookSourceChapterRule(
        itemSelector: json['itemSelector'] as String? ?? '',
        titleRule: SelectorRule.fromJson(
          json['titleRule'] as Map<String, dynamic>? ??
              const {'expression': ''},
        ),
        urlRule: SelectorRule.fromJson(
          json['urlRule'] as Map<String, dynamic>? ?? const {'expression': ''},
        ),
        reverse: json['reverse'] as bool? ?? false,
      );
}

class BookSourceContentRule {
  const BookSourceContentRule({
    this.titleRule = const SelectorRule(expression: ''),
    this.contentRule = const SelectorRule(expression: ''),
    this.nextPageRule = const SelectorRule(expression: ''),
    this.nextPageKeyword = '下一章',
    this.removeSelectors = const <String>[],
    this.decodeQb520Scripts = false,
  });

  final SelectorRule titleRule;
  final SelectorRule contentRule;
  final SelectorRule nextPageRule;
  final String nextPageKeyword;
  final List<String> removeSelectors;
  final bool decodeQb520Scripts;

  Map<String, dynamic> toJson() => {
    'titleRule': titleRule.toJson(),
    'contentRule': contentRule.toJson(),
    'nextPageRule': nextPageRule.toJson(),
    'nextPageKeyword': nextPageKeyword,
    'removeSelectors': removeSelectors,
    'decodeQb520Scripts': decodeQb520Scripts,
  };

  factory BookSourceContentRule.fromJson(
    Map<String, dynamic> json,
  ) => BookSourceContentRule(
    titleRule: SelectorRule.fromJson(
      json['titleRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    contentRule: SelectorRule.fromJson(
      json['contentRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    nextPageRule: SelectorRule.fromJson(
      json['nextPageRule'] as Map<String, dynamic>? ?? const {'expression': ''},
    ),
    nextPageKeyword: json['nextPageKeyword'] as String? ?? '下一章',
    removeSelectors: List<String>.from(
      json['removeSelectors'] as List? ?? const [],
    ),
    decodeQb520Scripts: json['decodeQb520Scripts'] as bool? ?? false,
  );
}

class BookSourceLoginRule {
  const BookSourceLoginRule({
    this.loginUrl = '',
    this.checkUrl = '',
    this.loggedInKeyword = '',
    this.expiredKeyword = '',
    this.domain = '',
  });

  final String loginUrl;
  final String checkUrl;
  final String loggedInKeyword;
  final String expiredKeyword;
  final String domain;

  Map<String, dynamic> toJson() => {
    'loginUrl': loginUrl,
    'checkUrl': checkUrl,
    'loggedInKeyword': loggedInKeyword,
    'expiredKeyword': expiredKeyword,
    'domain': domain,
  };

  factory BookSourceLoginRule.fromJson(Map<String, dynamic> json) =>
      BookSourceLoginRule(
        loginUrl: json['loginUrl'] as String? ?? '',
        checkUrl: json['checkUrl'] as String? ?? '',
        loggedInKeyword: json['loggedInKeyword'] as String? ?? '',
        expiredKeyword: json['expiredKeyword'] as String? ?? '',
        domain: json['domain'] as String? ?? '',
      );
}

class WebNovelSource {
  const WebNovelSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.group = '默认',
    this.charset = '',
    this.userAgent = '',
    this.headers = const <String, String>{},
    this.enabled = true,
    this.priority = 0,
    this.supportsWebViewLogin = false,
    this.supportsCookieImport = true,
    this.supportsCompanionService = false,
    this.search = const BookSourceSearchRule(
      method: HttpMethod.get,
      pathTemplate: '',
    ),
    this.detail = const BookSourceDetailRule(),
    this.chapters = const BookSourceChapterRule(itemSelector: ''),
    this.content = const BookSourceContentRule(),
    this.login = const BookSourceLoginRule(),
    this.tags = const <String>[],
    this.siteDomains = const <String>[],
    this.fetchViaBrowserOnly = false,
    this.builtin = true,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String group;
  final String charset;
  final String userAgent;
  final Map<String, String> headers;
  final bool enabled;
  final int priority;
  final bool supportsWebViewLogin;
  final bool supportsCookieImport;
  final bool supportsCompanionService;
  final BookSourceSearchRule search;
  final BookSourceDetailRule detail;
  final BookSourceChapterRule chapters;
  final BookSourceContentRule content;
  final BookSourceLoginRule login;
  final List<String> tags;
  final List<String> siteDomains;
  final bool fetchViaBrowserOnly;
  final bool builtin;

  WebNovelSource copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? group,
    String? charset,
    String? userAgent,
    Map<String, String>? headers,
    bool? enabled,
    int? priority,
    bool? supportsWebViewLogin,
    bool? supportsCookieImport,
    bool? supportsCompanionService,
    BookSourceSearchRule? search,
    BookSourceDetailRule? detail,
    BookSourceChapterRule? chapters,
    BookSourceContentRule? content,
    BookSourceLoginRule? login,
    List<String>? tags,
    List<String>? siteDomains,
    bool? fetchViaBrowserOnly,
    bool? builtin,
  }) {
    return WebNovelSource(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      group: group ?? this.group,
      charset: charset ?? this.charset,
      userAgent: userAgent ?? this.userAgent,
      headers: headers ?? this.headers,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      supportsWebViewLogin: supportsWebViewLogin ?? this.supportsWebViewLogin,
      supportsCookieImport: supportsCookieImport ?? this.supportsCookieImport,
      supportsCompanionService:
          supportsCompanionService ?? this.supportsCompanionService,
      search: search ?? this.search,
      detail: detail ?? this.detail,
      chapters: chapters ?? this.chapters,
      content: content ?? this.content,
      login: login ?? this.login,
      tags: tags ?? this.tags,
      siteDomains: siteDomains ?? this.siteDomains,
      fetchViaBrowserOnly: fetchViaBrowserOnly ?? this.fetchViaBrowserOnly,
      builtin: builtin ?? this.builtin,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'group': group,
    'charset': charset,
    'userAgent': userAgent,
    'headers': headers,
    'enabled': enabled,
    'priority': priority,
    'supportsWebViewLogin': supportsWebViewLogin,
    'supportsCookieImport': supportsCookieImport,
    'supportsCompanionService': supportsCompanionService,
    'search': search.toJson(),
    'detail': detail.toJson(),
    'chapters': chapters.toJson(),
    'content': content.toJson(),
    'login': login.toJson(),
    'tags': tags,
    'siteDomains': siteDomains,
    'fetchViaBrowserOnly': fetchViaBrowserOnly,
    'builtin': builtin,
  };

  factory WebNovelSource.fromJson(Map<String, dynamic> json) => WebNovelSource(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    baseUrl: json['baseUrl'] as String? ?? '',
    group: json['group'] as String? ?? '默认',
    charset: json['charset'] as String? ?? '',
    userAgent: json['userAgent'] as String? ?? '',
    headers: {
      for (final entry
          in (json['headers'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: entry.value.toString(),
    },
    enabled: json['enabled'] as bool? ?? true,
    priority: json['priority'] as int? ?? 0,
    supportsWebViewLogin: json['supportsWebViewLogin'] as bool? ?? false,
    supportsCookieImport: json['supportsCookieImport'] as bool? ?? true,
    supportsCompanionService:
        json['supportsCompanionService'] as bool? ?? false,
    search: BookSourceSearchRule.fromJson(
      json['search'] as Map<String, dynamic>? ?? const {'pathTemplate': ''},
    ),
    detail: BookSourceDetailRule.fromJson(
      json['detail'] as Map<String, dynamic>? ?? const {},
    ),
    chapters: BookSourceChapterRule.fromJson(
      json['chapters'] as Map<String, dynamic>? ?? const {'itemSelector': ''},
    ),
    content: BookSourceContentRule.fromJson(
      json['content'] as Map<String, dynamic>? ?? const {},
    ),
    login: BookSourceLoginRule.fromJson(
      json['login'] as Map<String, dynamic>? ?? const {},
    ),
    tags: List<String>.from(json['tags'] as List? ?? const []),
    siteDomains: List<String>.from(json['siteDomains'] as List? ?? const []),
    fetchViaBrowserOnly: json['fetchViaBrowserOnly'] as bool? ?? false,
    builtin: json['builtin'] as bool? ?? false,
  );
}

class WebNovelSearchResult {
  const WebNovelSearchResult({
    required this.sourceId,
    required this.title,
    required this.detailUrl,
    this.author = '',
    this.coverUrl = '',
    this.description = '',
    this.origin = WebNovelSearchResultOrigin.direct,
  });

  final String sourceId;
  final String title;
  final String detailUrl;
  final String author;
  final String coverUrl;
  final String description;
  final WebNovelSearchResultOrigin origin;
}

enum WebNovelSearchResultOrigin { direct, providerFallback }

enum AiSourceRepairMode { off, suggest, shadowValidate }

extension AiSourceRepairModeX on AiSourceRepairMode {
  String get storageValue =>
      this == AiSourceRepairMode.shadowValidate ? 'shadow_validate' : name;

  static AiSourceRepairMode fromStorageValue(String? value) {
    switch (value) {
      case 'suggest':
        return AiSourceRepairMode.suggest;
      case 'shadow_validate':
        return AiSourceRepairMode.shadowValidate;
      default:
        return AiSourceRepairMode.off;
    }
  }
}

enum WebNovelSearchFailureType { timeout, network, http, parse, rule, unknown }

enum WebNovelSearchFailureStage {
  directSearch,
  providerFallback,
  providerBulkFallback,
}

class WebNovelSearchFailure {
  const WebNovelSearchFailure({
    required this.stage,
    required this.type,
    required this.message,
    this.sourceId = '',
    this.sourceName = '',
  });

  final String sourceId;
  final String sourceName;
  final WebNovelSearchFailureStage stage;
  final WebNovelSearchFailureType type;
  final String message;
}

class WebNovelSearchReport {
  const WebNovelSearchReport({
    required this.query,
    required this.results,
    required this.totalSources,
    required this.directCandidates,
    required this.failures,
    required this.enableQueryExpansion,
  });

  final String query;
  final List<WebNovelSearchResult> results;
  final int totalSources;
  final int directCandidates;
  final List<WebNovelSearchFailure> failures;
  final bool enableQueryExpansion;

  bool get hasFailures => failures.isNotEmpty;

  Map<WebNovelSearchFailureType, int> get failureCounts {
    final counts = <WebNovelSearchFailureType, int>{};
    for (final failure in failures) {
      counts[failure.type] = (counts[failure.type] ?? 0) + 1;
    }
    return counts;
  }
}

class WebNovelAggregatedResult {
  const WebNovelAggregatedResult({
    required this.key,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.description,
    required this.sources,
    this.aliases = const <String>[],
  });

  final String key;
  final String title;
  final String author;
  final String coverUrl;
  final String description;
  final List<WebNovelSearchResult> sources;
  final List<String> aliases;

  int get sourceCount => sources.length;
}

class WebNovelSearchUpdate {
  const WebNovelSearchUpdate({
    required this.query,
    required this.results,
    required this.aggregatedResults,
    required this.totalSources,
    required this.directCandidates,
    required this.failures,
    required this.enableQueryExpansion,
    required this.isFinal,
  });

  final String query;
  final List<WebNovelSearchResult> results;
  final List<WebNovelAggregatedResult> aggregatedResults;
  final int totalSources;
  final int directCandidates;
  final List<WebNovelSearchFailure> failures;
  final bool enableQueryExpansion;
  final bool isFinal;

  WebNovelSearchReport toReport() => WebNovelSearchReport(
        query: query,
        results: results,
        totalSources: totalSources,
        directCandidates: directCandidates,
        failures: failures,
        enableQueryExpansion: enableQueryExpansion,
      );
}

enum WebChapterSyncStatus { pending, synced, stale }

extension WebChapterSyncStatusX on WebChapterSyncStatus {
  String get storageValue => name;

  String get label {
    switch (this) {
      case WebChapterSyncStatus.pending:
        return '未拉取';
      case WebChapterSyncStatus.synced:
        return '已拉取';
      case WebChapterSyncStatus.stale:
        return '失效';
    }
  }

  static WebChapterSyncStatus fromStorageValue(String? value) {
    for (final status in WebChapterSyncStatus.values) {
      if (status.storageValue == value) {
        return status;
      }
    }
    return WebChapterSyncStatus.pending;
  }
}

class WebNovelBookMeta {
  const WebNovelBookMeta({
    required this.id,
    required this.libraryBookId,
    required this.sourceId,
    required this.title,
    required this.author,
    required this.detailUrl,
    required this.originUrl,
    this.coverUrl = '',
    this.description = '',
    this.lastChapterTitle = '',
    this.updatedAt,
    this.sourceSnapshot = '',
    this.chapterSyncStatus = WebChapterSyncStatus.pending,
    this.chapterSyncError = '',
    this.chapterSyncRetryCount = 0,
    this.chapterSyncUpdatedAt,
  });

  final String id;
  final String libraryBookId;
  final String sourceId;
  final String title;
  final String author;
  final String detailUrl;
  final String originUrl;
  final String coverUrl;
  final String description;
  final String lastChapterTitle;
  final DateTime? updatedAt;
  final String sourceSnapshot;
  final WebChapterSyncStatus chapterSyncStatus;
  final String chapterSyncError;
  final int chapterSyncRetryCount;
  final DateTime? chapterSyncUpdatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'libraryBookId': libraryBookId,
    'sourceId': sourceId,
    'title': title,
    'author': author,
    'detailUrl': detailUrl,
    'originUrl': originUrl,
    'coverUrl': coverUrl,
    'description': description,
    'lastChapterTitle': lastChapterTitle,
    'updatedAt': updatedAt?.toIso8601String(),
    'sourceSnapshot': sourceSnapshot,
    'chapterSyncStatus': chapterSyncStatus.storageValue,
    'chapterSyncError': chapterSyncError,
    'chapterSyncRetryCount': chapterSyncRetryCount,
    'chapterSyncUpdatedAt': chapterSyncUpdatedAt?.toIso8601String(),
  };

  factory WebNovelBookMeta.fromJson(Map<String, dynamic> json) =>
      WebNovelBookMeta(
        id: json['id'] as String? ?? '',
        libraryBookId: json['libraryBookId'] as String? ?? '',
        sourceId: json['sourceId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        author: json['author'] as String? ?? '',
        detailUrl: json['detailUrl'] as String? ?? '',
        originUrl: json['originUrl'] as String? ?? '',
        coverUrl: json['coverUrl'] as String? ?? '',
        description: json['description'] as String? ?? '',
        lastChapterTitle: json['lastChapterTitle'] as String? ?? '',
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.tryParse(json['updatedAt'] as String),
        sourceSnapshot: json['sourceSnapshot'] as String? ?? '',
        chapterSyncStatus: WebChapterSyncStatusX.fromStorageValue(
          json['chapterSyncStatus'] as String?,
        ),
        chapterSyncError: json['chapterSyncError'] as String? ?? '',
        chapterSyncRetryCount: json['chapterSyncRetryCount'] as int? ?? 0,
        chapterSyncUpdatedAt: json['chapterSyncUpdatedAt'] == null
            ? null
            : DateTime.tryParse(json['chapterSyncUpdatedAt'] as String),
      );
}

class WebChapterRecord {
  const WebChapterRecord({
    required this.id,
    required this.webBookId,
    required this.sourceId,
    required this.title,
    required this.url,
    required this.chapterIndex,
    this.updatedAt,
  });

  final String id;
  final String webBookId;
  final String sourceId;
  final String title;
  final String url;
  final int chapterIndex;
  final DateTime? updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'webBookId': webBookId,
    'sourceId': sourceId,
    'title': title,
    'url': url,
    'chapterIndex': chapterIndex,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory WebChapterRecord.fromJson(Map<String, dynamic> json) =>
      WebChapterRecord(
        id: json['id'] as String? ?? '',
        webBookId: json['webBookId'] as String? ?? '',
        sourceId: json['sourceId'] as String? ?? '',
        title: json['title'] as String? ?? '',
        url: json['url'] as String? ?? '',
        chapterIndex: json['chapterIndex'] as int? ?? 0,
        updatedAt: json['updatedAt'] == null
            ? null
            : DateTime.tryParse(json['updatedAt'] as String),
      );
}

class WebChapterContent {
  const WebChapterContent({
    required this.chapterId,
    required this.sourceId,
    required this.title,
    required this.text,
    required this.html,
    required this.fetchedAt,
    this.isComplete = true,
  });

  final String chapterId;
  final String sourceId;
  final String title;
  final String text;
  final String html;
  final DateTime fetchedAt;
  final bool isComplete;
}

class WebSession {
  const WebSession({
    required this.id,
    required this.sourceId,
    required this.domain,
    required this.cookiesJson,
    this.userAgent = '',
    required this.updatedAt,
    this.lastVerifiedAt,
  });

  final String id;
  final String sourceId;
  final String domain;
  final String cookiesJson;
  final String userAgent;
  final DateTime updatedAt;
  final DateTime? lastVerifiedAt;

  List<Map<String, dynamic>> get cookies =>
      List<Map<String, dynamic>>.from(jsonDecode(cookiesJson) as List);
}

class WebSearchProvider {
  const WebSearchProvider({
    required this.id,
    required this.name,
    required this.searchUrlTemplate,
    this.method = HttpMethod.get,
    this.queryParamEncoding = 'utf-8',
    required this.resultListSelector,
    required this.resultTitleSelector,
    required this.resultUrlSelector,
    required this.resultSnippetSelector,
    this.userAgent = '',
    this.headers = const <String, String>{},
    this.enabled = true,
    this.priority = 0,
    this.builtin = false,
  });

  final String id;
  final String name;
  final String searchUrlTemplate;
  final HttpMethod method;
  final String queryParamEncoding;
  final String resultListSelector;
  final String resultTitleSelector;
  final String resultUrlSelector;
  final String resultSnippetSelector;
  final String userAgent;
  final Map<String, String> headers;
  final bool enabled;
  final int priority;
  final bool builtin;

  WebSearchProvider copyWith({
    String? id,
    String? name,
    String? searchUrlTemplate,
    HttpMethod? method,
    String? queryParamEncoding,
    String? resultListSelector,
    String? resultTitleSelector,
    String? resultUrlSelector,
    String? resultSnippetSelector,
    String? userAgent,
    Map<String, String>? headers,
    bool? enabled,
    int? priority,
    bool? builtin,
  }) {
    return WebSearchProvider(
      id: id ?? this.id,
      name: name ?? this.name,
      searchUrlTemplate: searchUrlTemplate ?? this.searchUrlTemplate,
      method: method ?? this.method,
      queryParamEncoding: queryParamEncoding ?? this.queryParamEncoding,
      resultListSelector: resultListSelector ?? this.resultListSelector,
      resultTitleSelector: resultTitleSelector ?? this.resultTitleSelector,
      resultUrlSelector: resultUrlSelector ?? this.resultUrlSelector,
      resultSnippetSelector:
          resultSnippetSelector ?? this.resultSnippetSelector,
      userAgent: userAgent ?? this.userAgent,
      headers: headers ?? this.headers,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      builtin: builtin ?? this.builtin,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'searchUrlTemplate': searchUrlTemplate,
    'method': method.name,
    'queryParamEncoding': queryParamEncoding,
    'resultListSelector': resultListSelector,
    'resultTitleSelector': resultTitleSelector,
    'resultUrlSelector': resultUrlSelector,
    'resultSnippetSelector': resultSnippetSelector,
    'userAgent': userAgent,
    'headers': headers,
    'enabled': enabled,
    'priority': priority,
    'builtin': builtin,
  };

  factory WebSearchProvider.fromJson(Map<String, dynamic> json) =>
      WebSearchProvider(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        searchUrlTemplate: json['searchUrlTemplate'] as String? ?? '',
        method: HttpMethod.values.firstWhere(
          (item) => item.name == json['method'],
          orElse: () => HttpMethod.get,
        ),
        queryParamEncoding: json['queryParamEncoding'] as String? ?? 'utf-8',
        resultListSelector: json['resultListSelector'] as String? ?? '',
        resultTitleSelector: json['resultTitleSelector'] as String? ?? '',
        resultUrlSelector: json['resultUrlSelector'] as String? ?? '',
        resultSnippetSelector: json['resultSnippetSelector'] as String? ?? '',
        userAgent: json['userAgent'] as String? ?? '',
        headers: {
          for (final entry
              in (json['headers'] as Map<String, dynamic>? ?? const {}).entries)
            entry.key: entry.value.toString(),
        },
        enabled: json['enabled'] as bool? ?? true,
        priority: json['priority'] as int? ?? 0,
        builtin: json['builtin'] as bool? ?? false,
      );
}

class WebSearchHit {
  const WebSearchHit({
    required this.providerId,
    required this.providerName,
    required this.title,
    required this.url,
    this.snippet = '',
  });

  final String providerId;
  final String providerName;
  final String title;
  final String url;
  final String snippet;
}

class ReaderModeArticle {
  const ReaderModeArticle({
    required this.url,
    required this.pageTitle,
    required this.siteName,
    required this.contentHtml,
    required this.contentText,
    this.author = '',
    this.publishTime = '',
    this.leadImage = '',
    this.nextPageUrl = '',
    this.detectedTocLinks = const <String>[],
    this.confidence = 0.0,
  });

  final String url;
  final String pageTitle;
  final String siteName;
  final String contentHtml;
  final String contentText;
  final String author;
  final String publishTime;
  final String leadImage;
  final String nextPageUrl;
  final List<String> detectedTocLinks;
  final double confidence;
}

class ReaderModeDetectionResult {
  const ReaderModeDetectionResult({
    required this.article,
    required this.isLikelyNovel,
    this.detectedBookTitle = '',
    this.detectedChapterTitle = '',
  });

  final ReaderModeArticle article;
  final bool isLikelyNovel;
  final String detectedBookTitle;
  final String detectedChapterTitle;
}

class SourceTestResult {
  const SourceTestResult({required this.ok, required this.message});

  final bool ok;
  final String message;
}

class AiSourcePatchSuggestion {
  const AiSourcePatchSuggestion({
    required this.sourceId,
    required this.patch,
    required this.note,
    required this.confidence,
    required this.rawResponse,
    this.applied = false,
    this.validationPassed = false,
    this.validationMessage = '',
  });

  final String sourceId;
  final Map<String, dynamic> patch;
  final String note;
  final double confidence;
  final String rawResponse;
  final bool applied;
  final bool validationPassed;
  final String validationMessage;
}

class WebSourceVersion {
  const WebSourceVersion({
    required this.id,
    required this.sourceId,
    required this.payload,
    required this.createdAt,
    required this.createdBy,
    this.note = '',
  });

  final String id;
  final String sourceId;
  final String payload;
  final DateTime createdAt;
  final String createdBy;
  final String note;
}

class CompanionFetchRequest {
  const CompanionFetchRequest({
    required this.action,
    required this.sourceId,
    this.url = '',
    this.query = '',
    this.headers = const <String, String>{},
    this.cookies = const <Map<String, dynamic>>[],
    this.timeoutSeconds = 15,
  });

  final String action;
  final String sourceId;
  final String url;
  final String query;
  final Map<String, String> headers;
  final List<Map<String, dynamic>> cookies;
  final int timeoutSeconds;

  Map<String, dynamic> toJson() => {
    'action': action,
    'sourceId': sourceId,
    'url': url,
    'query': query,
    'headers': headers,
    'cookies': cookies,
    'timeoutSeconds': timeoutSeconds,
  };
}

class CompanionFetchResponse {
  const CompanionFetchResponse({
    required this.ok,
    this.data = const <String, dynamic>{},
    this.errorCode = '',
    this.errorMessage = '',
    this.debugTrace = '',
  });

  final bool ok;
  final Map<String, dynamic> data;
  final String errorCode;
  final String errorMessage;
  final String debugTrace;
}
