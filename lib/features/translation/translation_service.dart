import 'dart:convert';
import 'dart:io';

import '../logging/app_run_log_service.dart';
import 'translation_config.dart';

class TranslationService {
  TranslationService();

  final HttpClient _client = HttpClient();

  Future<TranslationCheckResult> checkAvailability({
    required TranslationConfig? config,
  }) async {
    if (config == null ||
        config.baseUrl.trim().isEmpty ||
        config.modelName.trim().isEmpty) {
      return const TranslationCheckResult(
        success: false,
        message: '未配置可用的 API。',
      );
    }

    try {
      final uri = Uri.parse(
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions',
      );
      await AppRunLogService.instance.logInfo(
        'Checking translation API config: ${config.name}; $uri',
      );

      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (config.apiKey.isNotEmpty) {
        request.headers.add('Authorization', 'Bearer ${config.apiKey}');
      }

      request.write(
        jsonEncode({
          'model': config.modelName,
          'messages': const [
            {'role': 'system', 'content': 'You are a concise assistant.'},
            {'role': 'user', 'content': 'Reply with OK only.'},
          ],
          'temperature': 0,
          'max_tokens': 8,
        }),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        await AppRunLogService.instance.logError(
          'Translation API check failed: ${config.name}; HTTP ${response.statusCode}; $body',
        );
        return TranslationCheckResult(
          success: false,
          message: 'HTTP ${response.statusCode}: $body',
        );
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>? ?? const <dynamic>[];
      String? content;
      if (choices.isNotEmpty) {
        final first = choices.first as Map<String, dynamic>;
        final message = first['message'];
        if (message is Map<String, dynamic>) {
          content = message['content'] as String?;
        }
      }

      final snippet = content?.trim();
      if (snippet == null || snippet.isEmpty) {
        await AppRunLogService.instance.logError(
          'Translation API check returned empty content: ${config.name}',
        );
        return const TranslationCheckResult(
          success: false,
          message: '接口可达，但返回内容为空。',
        );
      }

      await AppRunLogService.instance.logInfo(
        'Translation API check succeeded: ${config.name}; $snippet',
      );
      return TranslationCheckResult(success: true, message: '响应正常：$snippet');
    } catch (error) {
      await AppRunLogService.instance.logError(
        'Translation API check error: ${config.name}; $error',
      );
      return TranslationCheckResult(success: false, message: '检测异常：$error');
    }
  }

  Future<String> translate(
    String text, {
    required TranslationConfig? config,
    String sourceLang = 'auto',
    String targetLang = 'zh',
  }) async {
    if (text.trim().isEmpty) {
      return text;
    }
    if (config == null || config.baseUrl.trim().isEmpty) {
      await AppRunLogService.instance.logError(
        'Translation failed: missing API config',
      );
      throw Exception('缺少有效的翻译 API 配置');
    }

    try {
      final uri = Uri.parse(
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions',
      );
      await AppRunLogService.instance.logInfo(
        'Starting translation request: ${config.name}; model=${config.modelName}; target=$targetLang; length=${text.length}',
      );

      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (config.apiKey.isNotEmpty) {
        request.headers.add('Authorization', 'Bearer ${config.apiKey}');
      }

      final prompt =
          'Translate the following text from $sourceLang to $targetLang. Preserve original markdown formatting and line breaks exactly as they are. Output NOTHING but the direct translation:\n\n$text';

      request.write(
        jsonEncode({
          'model': config.modelName,
          'messages': [
            {
              'role': 'system',
              'content': 'You are a highly capable translation assistant.',
            },
            {'role': 'user', 'content': prompt},
          ],
          'temperature': 0.1,
        }),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 40),
      );
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        await AppRunLogService.instance.logError(
          'Translation request failed: ${config.name}; HTTP ${response.statusCode}; $body',
        );
        throw Exception('API 错误 ${response.statusCode}: $body');
      }

      final json = jsonDecode(body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>? ?? const <dynamic>[];
      if (choices.isNotEmpty) {
        final first = choices.first as Map<String, dynamic>;
        final message = first['message'] as Map<String, dynamic>?;
        final content = message?['content'] as String?;
        await AppRunLogService.instance.logInfo(
          'Translation request succeeded: ${config.name}; outputLength=${content?.trim().length ?? 0}',
        );
        return content?.trim() ?? text;
      }

      await AppRunLogService.instance.logInfo(
        'Translation request completed without content: ${config.name}; fallback to source text',
      );
      return text;
    } catch (error) {
      await AppRunLogService.instance.logError(
        'Translation request error: ${config.name}; $error',
      );
      throw Exception('翻译请求异常：$error');
    }
  }

  Stream<TranslationProgress> translateBook({
    required String content,
    required TranslationConfig? config,
    required String sourceLang,
    required String targetLang,
    int chunkSize = 2000,
  }) async* {
    final paragraphs = content.split(RegExp(r'\n{2,}'));
    final translatedParts = <String>[];
    var done = 0;

    for (final paragraph in paragraphs) {
      if (paragraph.trim().isEmpty) {
        translatedParts.add('');
        done++;
        continue;
      }

      if (paragraph.length > chunkSize) {
        final chunks = _splitByLength(paragraph, chunkSize);
        final translatedChunks = <String>[];
        for (final chunk in chunks) {
          translatedChunks.add(
            await translate(
              chunk,
              config: config,
              sourceLang: sourceLang,
              targetLang: targetLang,
            ),
          );
        }
        translatedParts.add(translatedChunks.join(''));
      } else {
        translatedParts.add(
          await translate(
            paragraph,
            config: config,
            sourceLang: sourceLang,
            targetLang: targetLang,
          ),
        );
      }

      done++;
      yield TranslationProgress(
        total: paragraphs.length,
        done: done,
        partial: translatedParts.join('\n\n'),
      );
    }
  }

  Stream<String> askAiStream({
    required String systemPrompt,
    required String userPrompt,
    required TranslationConfig? config,
  }) async* {
    if (config == null || config.baseUrl.trim().isEmpty) {
      await AppRunLogService.instance.logError(
        'AI stream failed: missing API config',
      );
      throw Exception('缺少有效的 API 配置');
    }

    try {
      final uri = Uri.parse(
        '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions',
      );
      await AppRunLogService.instance.logInfo(
        'Starting AI stream: ${config.name}; model=${config.modelName}; promptLength=${userPrompt.length}',
      );

      final request = await _client.postUrl(uri);
      request.headers.contentType = ContentType.json;
      if (config.apiKey.isNotEmpty) {
        request.headers.add('Authorization', 'Bearer ${config.apiKey}');
      }

      request.write(
        jsonEncode({
          'model': config.modelName,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
          'temperature': 0.7,
          'stream': true,
        }),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 40),
      );
      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        await AppRunLogService.instance.logError(
          'AI stream failed: ${config.name}; HTTP ${response.statusCode}; $body',
        );
        throw Exception('API 错误 ${response.statusCode}: $body');
      }

      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data: ')) {
          continue;
        }
        final payload = line.substring(6).trim();
        if (payload == '[DONE]') {
          break;
        }

        try {
          final json = jsonDecode(payload) as Map<String, dynamic>;
          final choices =
              json['choices'] as List<dynamic>? ?? const <dynamic>[];
          if (choices.isEmpty) {
            continue;
          }
          final first = choices.first as Map<String, dynamic>;
          final delta = first['delta'] as Map<String, dynamic>?;
          final content = delta?['content'] as String?;
          if (content != null && content.isNotEmpty) {
            yield content;
          }
        } catch (_) {
          // Keep the stream resilient to partial frames.
        }
      }
    } catch (error) {
      await AppRunLogService.instance.logError(
        'AI stream error: ${config.name}; $error',
      );
      throw Exception('流式读取错误：$error');
    }
  }

  List<String> _splitByLength(String text, int maxLen) {
    final result = <String>[];
    for (var index = 0; index < text.length; index += maxLen) {
      result.add(text.substring(index, (index + maxLen).clamp(0, text.length)));
    }
    return result;
  }

  void dispose() => _client.close(force: true);
}

class TranslationProgress {
  const TranslationProgress({
    required this.total,
    required this.done,
    required this.partial,
  });

  final int total;
  final int done;
  final String partial;

  double get progress => total == 0 ? 0 : done / total;
}

class TranslationCheckResult {
  const TranslationCheckResult({required this.success, required this.message});

  final bool success;
  final String message;
}
