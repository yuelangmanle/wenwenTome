import 'package:flutter/services.dart';

import '../models.dart';

class LegadoPlatformStatus {
  const LegadoPlatformStatus({
    required this.installed,
    required this.packageName,
    required this.providerAvailable,
    required this.httpServiceAvailable,
    required this.webSocketAvailable,
  });

  final bool installed;
  final String packageName;
  final bool providerAvailable;
  final bool httpServiceAvailable;
  final bool webSocketAvailable;

  bool get searchReady => webSocketAvailable;

  bool get chapterReady => httpServiceAvailable;
}

class LegadoPlatformClient {
  static const MethodChannel _channel = MethodChannel('wenwen_tome/legado');

  Future<void> prewarm() async {
    try {
      await _channel.invokeMethod<void>('prewarm');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<List<WebNovelSearchResult>?> searchBooks({
    required String query,
    String? sourceId,
    required int maxConcurrent,
    required List<String> requiredTags,
    required bool enableQueryExpansion,
    required bool enableWebFallback,
  }) async {
    try {
      final rawList = await _channel
          .invokeMethod<List<dynamic>>('searchBooks', {
            'query': query,
            'sourceId': sourceId,
            'maxConcurrent': maxConcurrent,
            'requiredTags': requiredTags,
            'enableQueryExpansion': enableQueryExpansion,
            'enableWebFallback': enableWebFallback,
          });
      if (rawList == null) {
        return null;
      }
      return rawList
          .whereType<Map>()
          .map((item) => _searchResultFromMap(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<List<WebChapterRecord>?> getChapters(
    String webBookId, {
    WebNovelBookMeta? meta,
    bool refresh = false,
  }) async {
    try {
      final rawList = await _channel.invokeMethod<List<dynamic>>(
        'getChapters',
        {'webBookId': webBookId, 'meta': meta?.toJson(), 'refresh': refresh},
      );
      if (rawList == null) {
        return null;
      }
      return rawList
          .whereType<Map>()
          .map(
            (item) =>
                WebChapterRecord.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<WebChapterContent?> getChapterContent(
    String webBookId,
    int chapterIndex, {
    required WebNovelBookMeta? meta,
    WebChapterRecord? chapter,
    bool refresh = false,
  }) async {
    try {
      final raw = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getChapterContent', {
            'webBookId': webBookId,
            'chapterIndex': chapterIndex,
            'meta': meta?.toJson(),
            'chapter': chapter?.toJson(),
            'refresh': refresh,
          });
      if (raw == null) {
        return null;
      }
      final map = Map<String, dynamic>.from(raw);
      final fetchedAtRaw = map['fetchedAt'];
      final fetchedAt = fetchedAtRaw is int
          ? DateTime.fromMillisecondsSinceEpoch(fetchedAtRaw)
          : DateTime.tryParse(fetchedAtRaw?.toString() ?? '') ?? DateTime.now();
      return WebChapterContent(
        chapterId: map['chapterId']?.toString() ?? '',
        sourceId: map['sourceId']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        text: map['text']?.toString() ?? '',
        html: map['html']?.toString() ?? '',
        fetchedAt: fetchedAt,
        isComplete: map['isComplete'] as bool? ?? true,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<LegadoPlatformStatus?> getStatus() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getStatus',
      );
      if (raw == null) {
        return null;
      }
      final map = Map<String, dynamic>.from(raw);
      return LegadoPlatformStatus(
        installed: map['installed'] as bool? ?? false,
        packageName: map['packageName']?.toString() ?? '',
        providerAvailable: map['providerAvailable'] as bool? ?? false,
        httpServiceAvailable: map['httpServiceAvailable'] as bool? ?? false,
        webSocketAvailable: map['webSocketAvailable'] as bool? ?? false,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  WebNovelSearchResult _searchResultFromMap(Map<String, dynamic> map) {
    final originName = map['origin']?.toString() ?? 'direct';
    final origin = WebNovelSearchResultOrigin.values.firstWhere(
      (item) => item.name == originName,
      orElse: () => WebNovelSearchResultOrigin.direct,
    );
    return WebNovelSearchResult(
      sourceId: map['sourceId']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      detailUrl: map['detailUrl']?.toString() ?? '',
      author: map['author']?.toString() ?? '',
      coverUrl: map['coverUrl']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      origin: origin,
      platformPayload: map['platformPayload']?.toString() ?? '',
    );
  }
}
