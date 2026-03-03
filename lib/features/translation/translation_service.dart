import 'dart:convert';
import 'dart:io';

/// 全书翻译服务（离线 LibreTranslate 优先，降级到 MyMemory）
class TranslationService {
  // 离线优先：LibreTranslate 本地实例
  static const _localEndpoint = 'http://localhost:5000/translate';
  // 在线备选：MyMemory（免费，每日限额）
  static const _myMemoryEndpoint = 'https://api.mymemory.translated.net/get';

  final _client = HttpClient();

  /// 翻译单段文字（最大 2000 字符）
  Future<String> translate(
    String text, {
    String sourceLang = 'auto',
    String targetLang = 'zh',
  }) async {
    if (text.trim().isEmpty) return text;

    // 先尝试本地 LibreTranslate
    try {
      return await _translateLibre(text, sourceLang, targetLang);
    } catch (_) {
      // 降级到 MyMemory
      try {
        return await _translateMyMemory(text, sourceLang, targetLang);
      } catch (e) {
        return text; // 翻译失败，返回原文
      }
    }
  }

  Future<String> _translateLibre(String text, String src, String tgt) async {
    final req = await _client.postUrl(Uri.parse(_localEndpoint));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'q': text, 'source': src, 'target': tgt}));
    final resp = await req.close().timeout(const Duration(seconds: 5));
    final body = await resp.transform(utf8.decoder).join();
    if (resp.statusCode != 200) throw Exception('LibreTranslate error ${resp.statusCode}');
    return (jsonDecode(body) as Map)['translatedText'] as String;
  }

  Future<String> _translateMyMemory(String text, String src, String tgt) async {
    final langPair = src == 'auto' ? 'zh|$tgt' : '$src|$tgt';
    final uri = Uri.parse('$_myMemoryEndpoint?q=${Uri.encodeComponent(text)}&langpair=$langPair');
    final req = await _client.getUrl(uri);
    final resp = await req.close().timeout(const Duration(seconds: 10));
    final body = await resp.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    return json['responseData']['translatedText'] as String? ?? text;
  }

  /// 全书批量翻译（分段）
  Stream<TranslationProgress> translateBook({
    required String content,
    required String sourceLang,
    required String targetLang,
    int chunkSize = 1000,   // 每段字符数
  }) async* {
    // 按段落切分
    final paragraphs = content.split(RegExp(r'\n{2,}'));
    final translatedParts = <String>[];
    int done = 0;

    for (final para in paragraphs) {
      if (para.trim().isEmpty) {
        translatedParts.add('');
        done++;
        continue;
      }

      // 超长段落继续切分
      if (para.length > chunkSize) {
        final chunks = _splitByLength(para, chunkSize);
        final translatedChunks = <String>[];
        for (final chunk in chunks) {
          final t = await translate(chunk, sourceLang: sourceLang, targetLang: targetLang);
          translatedChunks.add(t);
        }
        translatedParts.add(translatedChunks.join(''));
      } else {
        final t = await translate(para, sourceLang: sourceLang, targetLang: targetLang);
        translatedParts.add(t);
      }

      done++;
      yield TranslationProgress(
        total: paragraphs.length,
        done: done,
        partial: translatedParts.join('\n\n'),
      );
    }
  }

  List<String> _splitByLength(String text, int maxLen) {
    final result = <String>[];
    for (var i = 0; i < text.length; i += maxLen) {
      result.add(text.substring(i, (i + maxLen).clamp(0, text.length)));
    }
    return result;
  }

  void dispose() => _client.close();
}

class TranslationProgress {
  final int total;
  final int done;
  final String partial;
  const TranslationProgress({required this.total, required this.done, required this.partial});
  double get progress => done / total;
}
