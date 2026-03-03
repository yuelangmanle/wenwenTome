import 'package:http/http.dart' as http;

/// 网文来源配置
class WebNovelSource {
  final String id;
  final String name;
  final String baseUrl;
  final String searchUrl;   // {query} 占位符
  final String listPattern; // 正则
  final String contentPattern;

  const WebNovelSource({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.searchUrl,
    required this.listPattern,
    required this.contentPattern,
  });
}

/// 网文章节元数据
class WebChapter {
  final String title;
  final String url;
  final int index;
  const WebChapter({required this.title, required this.url, required this.index});
}

/// 网文基础抓取引擎（示例：使用 HTTP 请求 + 通用 HTML 解析）
class WebNovelScraper {
  // ── 内置规则集（可扩展 JSON 配置文件）──
  static final List<WebNovelSource> builtinSources = [
    WebNovelSource(
      id: 'biquge',
      name: '笔趣阁（示例）',
      baseUrl: 'https://www.biquge.info',
      searchUrl: 'https://www.biquge.info/search/?q={query}',
      listPattern: r'<li><a href="(/\d+/\d+/)">(.+?)</a></li>',
      contentPattern: r'<div id="content">([\s\S]+?)</div>',
    ),
  ];

  final http.Client _client;
  WebNovelScraper() : _client = http.Client();

  /// 搜索网文（返回书名+URL列表）
  Future<List<Map<String, String>>> search(String sourceName, String query) async {
    final source = builtinSources.firstWhere(
      (s) => s.name == sourceName,
      orElse: () => builtinSources.first,
    );
    final url = source.searchUrl.replaceAll('{query}', Uri.encodeComponent(query));

    try {
      final response = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      // 简易 HTML 解析（生产中应使用 html package）
      final results = <Map<String, String>>[];
      final re = RegExp(r'<a href="([^"]+)"[^>]*>([^<]+)</a>');
      for (final m in re.allMatches(response.body)) {
        final href = m.group(1) ?? '';
        final title = m.group(2) ?? '';
        if (href.contains('/') && title.isNotEmpty && !title.contains('<')) {
          results.add({'url': href, 'title': title.trim()});
        }
      }
      return results.take(20).toList();
    } catch (e) {
      return [];
    }
  }

  /// 获取章节列表
  Future<List<WebChapter>> fetchChapterList(String sourceName, String bookUrl) async {
    final source = builtinSources.firstWhere(
      (s) => s.name == sourceName,
      orElse: () => builtinSources.first,
    );
    final fullUrl = bookUrl.startsWith('http') ? bookUrl : '${source.baseUrl}$bookUrl';

    try {
      final response = await _client.get(Uri.parse(fullUrl)).timeout(const Duration(seconds: 10));
      final chapters = <WebChapter>[];
      final re = RegExp(source.listPattern);
      int idx = 0;
      for (final m in re.allMatches(response.body)) {
        chapters.add(WebChapter(
          title: m.group(2)?.trim() ?? '第${idx + 1}章',
          url: '${source.baseUrl}${m.group(1)}',
          index: idx++,
        ));
      }
      return chapters;
    } catch (e) {
      return [];
    }
  }

  /// 获取章节正文
  Future<String> fetchChapterContent(String sourceName, String chapterUrl) async {
    final source = builtinSources.firstWhere(
      (s) => s.name == sourceName,
      orElse: () => builtinSources.first,
    );
    try {
      final response = await _client.get(Uri.parse(chapterUrl)).timeout(const Duration(seconds: 10));
      final re = RegExp(source.contentPattern, dotAll: true);
      final match = re.firstMatch(response.body);
      if (match == null) return '（内容提取失败）';

      // 清理 HTML 标签
      var text = match.group(1) ?? '';
      text = text.replaceAll(RegExp(r'<[^>]+>'), '');
      text = text.replaceAll(RegExp(r'&nbsp;'), ' ');
      text = text.replaceAll(RegExp(r'&lt;'), '<');
      text = text.replaceAll(RegExp(r'&gt;'), '>');
      text = text.replaceAll(RegExp(r'\s{3,}'), '\n\n');
      return text.trim();
    } catch (e) {
      return '（网络错误：$e）';
    }
  }

  void dispose() => _client.close();
}
