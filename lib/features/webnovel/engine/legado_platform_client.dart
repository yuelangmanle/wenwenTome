import 'package:flutter/services.dart';

import '../models.dart';

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
      final rawList = await _channel.invokeMethod<List<dynamic>>('searchBooks', {
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
    bool refresh = false,
  }) async {
    try {
      final rawList = await _channel.invokeMethod<List<dynamic>>('getChapters', {
        'webBookId': webBookId,
        'refresh': refresh,
      });
      if (rawList == null) {
        return null;
      }
      return rawList
          .whereType<Map>()
          .map((item) => WebChapterRecord.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
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
    );
  }
}
