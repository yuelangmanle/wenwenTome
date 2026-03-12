import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/features/webnovel/models.dart';
import 'package:wenwen_tome/features/webnovel/webnovel_repository.dart';

class _MockHttpResponse {
  const _MockHttpResponse({
    required this.body,
    this.statusCode = 200,
    this.headers = const <String, String>{'content-type': 'application/json'},
  });

  final String body;
  final int statusCode;
  final Map<String, String> headers;
}

class _MockHttpClient extends http.BaseClient {
  _MockHttpClient(this._handlers);

  final Map<String, _MockHttpResponse Function(http.BaseRequest request)>
  _handlers;
  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount += 1;
    final handler = _handlers[request.url.toString()];
    final response =
        handler?.call(request) ??
        const _MockHttpResponse(body: '{"error":"not found"}', statusCode: 404);
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(response.body)),
      response.statusCode,
      request: request,
      headers: response.headers,
    );
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory(
      p.join(
        Directory.current.path,
        '.dart_tool',
        'test_tmp',
        'webnovel_repository',
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
    await tempDir.create(recursive: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  });

  Future<WebNovelRepository> createRepository(
    _MockHttpClient client, {
    Future<void> Function(Duration)? retryDelay,
  }) async {
    final repository = WebNovelRepository.test(
      client: client,
      databasePathProvider: (fileName) async => p.join(tempDir.path, fileName),
      retryDelay: retryDelay,
      autoSyncOnAdd: false,
    );
    await repository.listSources();
    return repository;
  }

  test(
    'imports JSONPath-aware Legado source and searches JSON payloads',
    () async {
      final client = _MockHttpClient({
        'https://api.example.com/search?q=legend': (_) => _MockHttpResponse(
          body: jsonEncode({
            'data': {
              'list': [
                {'id': '42', 'title': 'Legend of JSON', 'author': 'Parser'},
              ],
            },
          }),
        ),
      });
      final repository = await createRepository(client);

      final report = await repository.importSourcesJsonWithReport(
        jsonEncode([
          {
            'bookSourceName': 'JSON API',
            'bookSourceUrl': 'https://api.example.com',
            'searchUrl': 'https://api.example.com/search?q={{key}}',
            'ruleSearch': {
              'bookList': r'$.data.list[*]',
              'name': r'$.title',
              'author': r'$.author',
              'bookUrl': r'https://api.example.com/book/{{$.id}}',
            },
          },
        ]),
      );

      expect(report.importedCount, 1);
      expect(
        report.warnings.where((item) => item.contains('JSONPath')),
        isEmpty,
      );

      final results = await repository.searchBooks(
        'legend',
        sourceId: 'json_api',
      );
      expect(results, hasLength(1));
      expect(results.single.title, 'Legend of JSON');
      expect(results.single.author, 'Parser');
      expect(results.single.detailUrl, 'https://api.example.com/book/42');
    },
  );

  test('applies simple Legado JS transforms after JSON selection', () async {
    final client = _MockHttpClient({
      'https://api.example.com/search?q=heiyan': (_) => _MockHttpResponse(
        body: jsonEncode({
          'data': {
            'content': [
              {'id': '9001', 'name': 'Black Rock'},
            ],
          },
        }),
      ),
    });
    final repository = await createRepository(client);

    await repository.importSourcesJsonWithReport(
      jsonEncode([
        {
          'bookSourceName': 'JS API',
          'bookSourceUrl': 'https://api.example.com',
          'searchUrl': 'https://api.example.com/search?q={{key}}',
          'ruleSearch': {
            'bookList': r'$.data.content[*]',
            'name': r'$.name',
            'bookUrl': r'''$.id@js:'https://books.example.com/book/'+result''',
          },
        },
      ]),
    );

    final results = await repository.searchBooks('heiyan', sourceId: 'js_api');
    expect(results, hasLength(1));
    expect(results.single.detailUrl, 'https://books.example.com/book/9001');
  });

  test(
    'uses bulk provider fallback instead of per-source provider fan-out',
    () async {
      final providerQuery = Uri.encodeComponent('legend 小说');
      final client = _MockHttpClient({
        'https://search.example.com?q=$providerQuery': (_) =>
            const _MockHttpResponse(
              headers: <String, String>{
                'content-type': 'text/html; charset=utf-8',
              },
              body: '''
              <div class="hit">
                <a href="https://alpha.example.com/book/1">Alpha Legend</a>
                <div class="snippet">alpha</div>
              </div>
              <div class="hit">
                <a href="https://beta.example.com/book/2">Beta Legend</a>
                <div class="snippet">beta</div>
              </div>
            ''',
            ),
      });
      final repository = await createRepository(client);

      await repository.saveSource(
        const WebNovelSource(
          id: 'alpha',
          name: 'Alpha Source',
          baseUrl: 'https://alpha.example.com',
          search: BookSourceSearchRule(
            method: HttpMethod.get,
            pathTemplate: '',
            useSearchProviderFallback: true,
          ),
          siteDomains: <String>['alpha.example.com'],
          builtin: false,
        ),
      );
      await repository.saveSource(
        const WebNovelSource(
          id: 'beta',
          name: 'Beta Source',
          baseUrl: 'https://beta.example.com',
          search: BookSourceSearchRule(
            method: HttpMethod.get,
            pathTemplate: '',
            useSearchProviderFallback: true,
          ),
          siteDomains: <String>['beta.example.com'],
          builtin: false,
        ),
      );
      await repository.saveSearchProvider(
        const WebSearchProvider(
          id: 'provider',
          name: 'Provider',
          searchUrlTemplate: 'https://search.example.com?q={query}',
          resultListSelector: '.hit',
          resultTitleSelector: 'a',
          resultUrlSelector: 'a@href',
          resultSnippetSelector: '.snippet',
        ),
      );

      final results = await repository.searchBooks(
        'legend',
        enableWebFallback: true,
      );
      expect(results, hasLength(2));
      expect(client.requestCount, 1);
    },
  );

  test(
    'adds book first even when chapter sync fails and marks stale',
    () async {
      final client = _MockHttpClient({
        'https://fail.example.com/book/1': (_) => const _MockHttpResponse(
          headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
          body: '''
          <html>
            <body>
              <h1 class="title">失败样本</h1>
              <div class="author">测试作者</div>
            </body>
          </html>
        ''',
        ),
      });
      final repository = await createRepository(
        client,
        retryDelay: (_) async {},
      );

      await repository.saveSource(
        const WebNovelSource(
          id: 'fail_source',
          name: 'Fail Source',
          baseUrl: 'https://fail.example.com',
          detail: BookSourceDetailRule(
            titleRule: SelectorRule(expression: '.title'),
            authorRule: SelectorRule(expression: '.author'),
          ),
          chapters: BookSourceChapterRule(
            itemSelector: '.chapter-list a',
            titleRule: SelectorRule(expression: 'a'),
            urlRule: SelectorRule(
              expression: 'a',
              attr: 'href',
              absoluteUrl: true,
            ),
          ),
          search: BookSourceSearchRule(
            method: HttpMethod.get,
            pathTemplate: '',
          ),
          builtin: false,
        ),
      );

      final meta = await repository.addBookFromSearchResult(
        const WebNovelSearchResult(
          sourceId: 'fail_source',
          title: '失败样本',
          detailUrl: 'https://fail.example.com/book/1',
          author: '测试作者',
        ),
      );

      await repository.requestChapterSync(meta.id, force: true);
      final status = await repository.describeChapterSyncState(meta.id);

      expect(meta.libraryBookId, isNotEmpty);
      expect(status, contains('失效'));
    },
  );

  test(
    'can add book when result sourceId is stale by falling back to host source',
    () async {
      final client = _MockHttpClient({
        'https://hosted.example.com/book/88': (_) => const _MockHttpResponse(
          headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
          body: '''
          <html>
            <body>
              <div class="book-title">宿主书名</div>
              <div class="book-author">宿主作者</div>
            </body>
          </html>
        ''',
        ),
      });
      final repository = await createRepository(client);

      await repository.saveSource(
        const WebNovelSource(
          id: 'host_source',
          name: 'Host Source',
          baseUrl: 'https://hosted.example.com',
          siteDomains: <String>['hosted.example.com'],
          detail: BookSourceDetailRule(
            titleRule: SelectorRule(expression: '.book-title'),
            authorRule: SelectorRule(expression: '.book-author'),
          ),
          search: BookSourceSearchRule(
            method: HttpMethod.get,
            pathTemplate: '',
          ),
          builtin: false,
        ),
      );

      final meta = await repository.addBookFromSearchResult(
        const WebNovelSearchResult(
          sourceId: 'missing_source',
          title: 'Fallback Title',
          detailUrl: 'https://hosted.example.com/book/88',
          author: 'Fallback Author',
        ),
      );

      expect(meta.sourceId, 'host_source');
      expect(meta.title, '宿主书名');
    },
  );

  test('retries chapter sync and marks synced after later success', () async {
    var detailCalls = 0;
    _MockHttpResponse retryDetailHandler(http.BaseRequest _) {
      detailCalls += 1;
      if (detailCalls == 1) {
        return const _MockHttpResponse(
          headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
          body: '''
              <html>
                <body>
                  <h1 class="title">重试样本</h1>
                  <div class="author">测试作者</div>
                </body>
              </html>
            ''',
        );
      }
      if (detailCalls == 2) {
        return const _MockHttpResponse(
          body: 'upstream timeout',
          statusCode: 502,
        );
      }
      return const _MockHttpResponse(
        headers: <String, String>{'content-type': 'text/html; charset=utf-8'},
        body: '''
            <html>
              <body>
                <h1 class="title">重试样本</h1>
                <div class="author">测试作者</div>
                <div class="chapter-list">
                  <a href="https://retry.example.com/ch/1">第一章</a>
                  <a href="https://retry.example.com/ch/2">第二章</a>
                  <a href="https://retry.example.com/ch/3">第三章</a>
                </div>
              </body>
            </html>
          ''',
      );
    }

    final client = _MockHttpClient({
      'https://retry.example.com/book/1': retryDetailHandler,
      'https://retry.example.com/book/1/': retryDetailHandler,
    });
    final repository = await createRepository(client, retryDelay: (_) async {});

    await repository.saveSource(
      const WebNovelSource(
        id: 'retry_source',
        name: 'Retry Source',
        baseUrl: 'https://retry.example.com',
        detail: BookSourceDetailRule(
          titleRule: SelectorRule(expression: '.title'),
          authorRule: SelectorRule(expression: '.author'),
        ),
        chapters: BookSourceChapterRule(
          itemSelector: '.chapter-list a',
          titleRule: SelectorRule(expression: 'a'),
          urlRule: SelectorRule(
            expression: 'a',
            attr: 'href',
            absoluteUrl: true,
          ),
        ),
        search: BookSourceSearchRule(method: HttpMethod.get, pathTemplate: ''),
        builtin: false,
      ),
    );

    final meta = await repository.addBookFromSearchResult(
      const WebNovelSearchResult(
        sourceId: 'retry_source',
        title: '重试样本',
        detailUrl: 'https://retry.example.com/book/1',
        author: '测试作者',
      ),
    );

    await repository.requestChapterSync(meta.id, force: true);
    final chapters = await repository.getChapters(meta.id);
    final status = await repository.describeChapterSyncState(meta.id);

    expect(chapters.length, greaterThanOrEqualTo(3));
    expect(status, contains('目录已拉取'));
    expect(client.requestCount, greaterThanOrEqualTo(3));
  });
}
