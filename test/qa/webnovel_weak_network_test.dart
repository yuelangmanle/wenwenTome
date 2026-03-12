import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/features/webnovel/webnovel_repository.dart';

class _DelayedHttpClient extends http.BaseClient {
  _DelayedHttpClient({required this.delay});

  final Duration delay;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await Future<void>.delayed(delay);
    final body = '<html><body>ok</body></html>';
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      request: request,
      headers: const <String, String>{'content-type': 'text/html; charset=utf-8'},
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
        'qa_weak_network',
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

  Future<WebNovelRepository> createRepository(http.Client client) async {
    final repository = WebNovelRepository.test(
      client: client,
      databasePathProvider: (fileName) async => p.join(tempDir.path, fileName),
      autoSyncOnAdd: false,
    );
    await repository.listSources();
    return repository;
  }

  test('times out quickly under high latency when requested', () async {
    final repository = await createRepository(
      _DelayedHttpClient(delay: const Duration(milliseconds: 200)),
    );
    expect(
      () => repository.requestPageHtmlForTest(
        'https://example.com/',
        timeout: const Duration(milliseconds: 60),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('succeeds under mild latency when timeout allows', () async {
    final repository = await createRepository(
      _DelayedHttpClient(delay: const Duration(milliseconds: 30)),
    );
    final html = await repository.requestPageHtmlForTest(
      'https://example.com/',
      timeout: const Duration(milliseconds: 200),
    );
    expect(html, contains('ok'));
  });
}

