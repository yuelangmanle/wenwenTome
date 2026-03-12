import 'dart:convert';

import '../logging/app_run_log_service.dart';
import '../translation/translation_config.dart';
import '../translation/translation_service.dart';
import 'models.dart';

class AiSearchRerankResult {
  const AiSearchRerankResult({
    required this.results,
    this.filteredCount = 0,
    this.applied = false,
  });

  final List<WebNovelAggregatedResult> results;
  final int filteredCount;
  final bool applied;
}

class AiSearchService {
  AiSearchService({TranslationService? translationService})
    : _translationService = translationService ?? TranslationService();

  final TranslationService _translationService;

  Future<AiSearchRerankResult> rerankAggregatedResults({
    required String query,
    required List<WebNovelAggregatedResult> results,
    required TranslationConfig? config,
  }) async {
    if (results.isEmpty || config == null) {
      return AiSearchRerankResult(results: results);
    }
    if (config.baseUrl.trim().isEmpty || config.modelName.trim().isEmpty) {
      return AiSearchRerankResult(results: results);
    }

    final startedAt = DateTime.now();
    await AppRunLogService.instance.logEvent(
      action: 'ai.search_rerank',
      result: 'start',
      context: <String, Object?>{
        'query': query,
        'result_count': results.length,
      },
    );

    try {
      final candidates = results.take(24).toList(growable: false);
      final payload = [
        for (var index = 0; index < candidates.length; index++)
          {
            'id': index,
            'title': candidates[index].title,
            'author': candidates[index].author,
            'sourceCount': candidates[index].sourceCount,
            'description': candidates[index].description,
            'topSource': candidates[index].sources.isEmpty
                ? ''
                : candidates[index].sources.first.sourceId,
          },
      ];

      final systemPrompt =
          'You are a ranking assistant for Chinese web novel search results. '
          'Return ONLY valid JSON with fields: ranked_ids (array of ids ordered best to worst) '
          'and filtered_ids (array of ids to exclude because they are not novels).';
      final userPrompt = 'Query: $query\n'
          'Candidates (JSON array):\n${jsonEncode(payload)}\n'
          'Return JSON now.';

      final raw = await _collectStream(
        systemPrompt: systemPrompt,
        userPrompt: userPrompt,
        config: config,
      );
      final decoded = _extractJsonObject(raw);
      if (decoded == null) {
        throw Exception('AI 未返回可解析的 JSON');
      }
      final rankedIds = <int>[];
      final filteredIds = <int>{};
      final rawFiltered = decoded['filtered_ids'];
      if (rawFiltered is List) {
        for (final item in rawFiltered) {
          final value = _parseIndex(item);
          if (value != null) {
            filteredIds.add(value);
          }
        }
      }
      final rawRanked = decoded['ranked_ids'];
      if (rawRanked is List) {
        for (final item in rawRanked) {
          final value = _parseIndex(item);
          if (value != null && !filteredIds.contains(value)) {
            rankedIds.add(value);
          }
        }
      }

      final remaining = <int>{};
      for (var i = 0; i < candidates.length; i++) {
        if (!filteredIds.contains(i) && !rankedIds.contains(i)) {
          remaining.add(i);
        }
      }
      final finalOrder = <int>[
        ...rankedIds,
        for (var i = 0; i < candidates.length; i++)
          if (remaining.contains(i)) i,
      ];

      final reranked = <WebNovelAggregatedResult>[
        for (final id in finalOrder)
          if (id >= 0 && id < candidates.length) candidates[id],
      ];
      final output = reranked.isEmpty
          ? results
          : <WebNovelAggregatedResult>[
              ...reranked,
              ...results.skip(candidates.length),
            ];

      await AppRunLogService.instance.logEvent(
        action: 'ai.search_rerank',
        result: 'ok',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: <String, Object?>{
          'query': query,
          'result_count': results.length,
          'filtered_count': filteredIds.length,
          'reranked_count': reranked.length,
        },
      );
      return AiSearchRerankResult(
        results: output,
        filteredCount: filteredIds.length,
        applied: true,
      );
    } catch (error, stackTrace) {
      await AppRunLogService.instance.logEvent(
        action: 'ai.search_rerank',
        result: 'error',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        error: error,
        stackTrace: stackTrace,
        level: 'ERROR',
        context: <String, Object?>{'query': query},
      );
      return AiSearchRerankResult(results: results);
    }
  }

  Future<String> _collectStream({
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

  int? _parseIndex(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
