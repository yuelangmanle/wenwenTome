import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/translation/translation_config.dart';
import 'package:wenwen_tome/features/translation/translation_service.dart';

void main() {
  group('TranslationService.checkAvailability', () {
    late HttpServer server;
    late TranslationConfig config;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      config = TranslationConfig.create(
        name: 'local-test',
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'sk-test',
        modelName: 'demo-model',
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test(
      'returns success when the api responds with assistant content',
      () async {
        server.listen((request) async {
          expect(request.uri.path, '/v1/chat/completions');
          final body = await utf8.decoder.bind(request).join();
          expect(body.contains('demo-model'), isTrue);
          request.response
            ..statusCode = 200
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'OK'},
                  },
                ],
              }),
            );
          await request.response.close();
        });

        final result = await TranslationService().checkAvailability(
          config: config,
        );

        expect(result.success, isTrue);
        expect(result.message.contains('OK'), isTrue);
      },
    );

    test('returns failure when config is missing', () async {
      final result = await TranslationService().checkAvailability(config: null);

      expect(result.success, isFalse);
      expect(result.message.contains('未配置'), isTrue);
    });
  });

  group('TranslationService.translate', () {
    late HttpServer server;
    late TranslationConfig config;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      config = TranslationConfig.create(
        name: 'local-translate',
        baseUrl: 'http://${server.address.host}:${server.port}/v1',
        apiKey: 'sk-test',
        modelName: 'demo-model',
      );
    });

    tearDown(() async {
      await server.close(force: true);
    });

    test('returns assistant content when the api responds with translation', () async {
      server.listen((request) async {
        expect(request.uri.path, '/v1/chat/completions');
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '你好'},
                },
              ],
            }),
          );
        await request.response.close();
      });

      final result = await TranslationService().translate(
        'Hello',
        config: config,
        sourceLang: 'en',
        targetLang: 'zh',
      );

      expect(result, '你好');
    });
  });
}
