import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/app/runtime_platform.dart';
import 'package:wenwen_tome/core/downloads/download_task_store.dart';
import 'package:wenwen_tome/features/reader/local_tts_model_manager.dart';
import 'package:wenwen_tome/features/translation/local_model_service.dart';
import 'package:wenwen_tome/features/translation/local_translation_executor.dart';

void main() {
  group('Translation model download resume', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createProjectTempDir('wenwen_tome_download_resume_');
    });

    tearDown(() async {
      if (!await tempDir.exists()) {
        return;
      }
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup for test-only directories.
      }
    });

    test('resumes a partial translation download with Range', () async {
      final payload = _sampleBytes(4096);
      const cutAt = 1024;
      final rangeHeaders = <String?>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((request) async {
        rangeHeaders.add(request.headers.value(HttpHeaders.rangeHeader));
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=$cutAt-');
        await _writeRangeResponse(
          request: request,
          payload: payload,
          start: cutAt,
        );
      });

      final container = _createTranslationContainer(
        tempDir: tempDir,
        downloadCandidatesBuilder: ({required bool useMirror}) => <String>[
          'http://${server.address.host}:${server.port}/model.gguf',
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(localModelProvider.notifier);
      final store = container.read(downloadTaskStoreProvider);
      final modelDir = await notifier.ensureInitialized();
      await _seedTranslationPartial(
        store: store,
        modelDir: modelDir,
        source: 'http://${server.address.host}:${server.port}/model.gguf',
        payload: payload,
        cutAt: cutAt,
      );

      await notifier.downloadModel();

      final finalFile = File(
        p.join(modelDir, LocalModelNotifier.savedModelFileName),
      );
      final partFile = File('${finalFile.path}.part');
      expect(await finalFile.exists(), isTrue);
      expect(await partFile.exists(), isFalse);
      expect(await finalFile.readAsBytes(), orderedEquals(payload));
      expect(rangeHeaders, ['bytes=$cutAt-']);
    });

    test(
      'falls back to the mirror source when the official source fails',
      () async {
        final payload = _sampleBytes(3072);
        final rangeHeaders = <String, List<String?>>{
          'official': <String?>[],
          'mirror': <String?>[],
        };
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((request) async {
          if (request.uri.path == '/official/model.gguf') {
            rangeHeaders['official']!.add(
              request.headers.value(HttpHeaders.rangeHeader),
            );
            request.response.statusCode = HttpStatus.internalServerError;
            await request.response.close();
            return;
          }

          rangeHeaders['mirror']!.add(
            request.headers.value(HttpHeaders.rangeHeader),
          );
          await _writeFullResponse(request: request, payload: payload);
        });

        final container = _createTranslationContainer(
          tempDir: tempDir,
          downloadCandidatesBuilder: ({required bool useMirror}) => <String>[
            'http://${server.address.host}:${server.port}/official/model.gguf',
            'http://${server.address.host}:${server.port}/mirror/model.gguf',
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(localModelProvider.notifier);
        final modelDir = await notifier.ensureInitialized();

        await notifier.downloadModel();

        final finalFile = File(
          p.join(modelDir, LocalModelNotifier.savedModelFileName),
        );
        expect(await finalFile.exists(), isTrue);
        expect(await finalFile.readAsBytes(), orderedEquals(payload));
        expect(rangeHeaders['official'], [null]);
        expect(rangeHeaders['mirror'], [null]);
      },
    );

    test(
      'falls back to a full redownload when the server ignores the Range request',
      () async {
        final payload = _sampleBytes(3584);
        const cutAt = 896;
        final rangeHeaders = <String?>[];
        var requestCount = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((request) async {
          rangeHeaders.add(request.headers.value(HttpHeaders.rangeHeader));
          requestCount++;

          if (requestCount == 1) {
            expect(
              request.headers.value(HttpHeaders.rangeHeader),
              'bytes=$cutAt-',
            );
            await _writeFullResponse(request: request, payload: payload);
            return;
          }

          expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
          await _writeFullResponse(request: request, payload: payload);
        });

        final container = _createTranslationContainer(
          tempDir: tempDir,
          downloadCandidatesBuilder: ({required bool useMirror}) => <String>[
            'http://${server.address.host}:${server.port}/model.gguf',
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(localModelProvider.notifier);
        final store = container.read(downloadTaskStoreProvider);
        final modelDir = await notifier.ensureInitialized();
        await _seedTranslationPartial(
          store: store,
          modelDir: modelDir,
          source: 'http://${server.address.host}:${server.port}/model.gguf',
          payload: payload,
          cutAt: cutAt,
        );

        await notifier.downloadModel();

        final finalFile = File(
          p.join(modelDir, LocalModelNotifier.savedModelFileName),
        );
        expect(await finalFile.exists(), isTrue);
        expect(await finalFile.readAsBytes(), orderedEquals(payload));
        expect(rangeHeaders, ['bytes=$cutAt-', null]);
      },
    );

    test(
      'falls back to a full redownload when a 206 response has an invalid Content-Range',
      () async {
        final payload = _sampleBytes(3328);
        const cutAt = 832;
        final rangeHeaders = <String?>[];
        var requestCount = 0;
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((request) async {
          rangeHeaders.add(request.headers.value(HttpHeaders.rangeHeader));
          requestCount++;

          if (requestCount == 1) {
            request.response.statusCode = HttpStatus.partialContent;
            request.response.headers
              ..set(
                HttpHeaders.contentRangeHeader,
                'bytes 0-${payload.length - cutAt - 1}/${payload.length}',
              )
              ..set(HttpHeaders.contentLengthHeader, payload.length - cutAt);
            request.response.add(payload.sublist(cutAt));
            await request.response.close();
            return;
          }

          expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
          await _writeFullResponse(request: request, payload: payload);
        });

        final container = _createTranslationContainer(
          tempDir: tempDir,
          downloadCandidatesBuilder: ({required bool useMirror}) => <String>[
            'http://${server.address.host}:${server.port}/model.gguf',
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(localModelProvider.notifier);
        final store = container.read(downloadTaskStoreProvider);
        final modelDir = await notifier.ensureInitialized();
        await _seedTranslationPartial(
          store: store,
          modelDir: modelDir,
          source: 'http://${server.address.host}:${server.port}/model.gguf',
          payload: payload,
          cutAt: cutAt,
        );

        await notifier.downloadModel();

        final finalFile = File(
          p.join(modelDir, LocalModelNotifier.savedModelFileName),
        );
        expect(await finalFile.exists(), isTrue);
        expect(await finalFile.readAsBytes(), orderedEquals(payload));
        expect(rangeHeaders, ['bytes=$cutAt-', null]);
      },
    );
  });

  group('Windows runtime download resume', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createProjectTempDir('wenwen_tome_runtime_resume_');
    });

    tearDown(() async {
      if (!await tempDir.exists()) {
        return;
      }
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup for test-only directories.
      }
    });

    test('resumes a partial llama-server runtime download with Range', () async {
      final runtimeArchive = _sampleRuntimeZipBytes();
      const cutAt = 128;
      final runtimeRangeHeaders = <String?>[];

      final runtimeServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => runtimeServer.close(force: true));
      runtimeServer.listen((request) async {
        runtimeRangeHeaders.add(request.headers.value(HttpHeaders.rangeHeader));
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=$cutAt-');
        await _writeRangeResponse(
          request: request,
          payload: runtimeArchive,
          start: cutAt,
        );
      });

      final container = _createTranslationContainer(
        tempDir: tempDir,
        platform: LocalRuntimePlatform.windows,
        serverDownloadUrlResolver: () async =>
            'http://${runtimeServer.address.host}:${runtimeServer.port}/llama-server.zip',
        downloadCandidatesBuilder: ({required bool useMirror}) => <String>[
          'http://127.0.0.1:9/model.gguf',
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(localModelProvider.notifier);
      final store = container.read(downloadTaskStoreProvider);
      final modelDir = await notifier.ensureInitialized();
      await Directory(modelDir).create(recursive: true);
      await File(
        p.join(modelDir, LocalModelNotifier.savedModelFileName),
      ).writeAsBytes(const [1, 2, 3], flush: true);
      await _seedRuntimePartial(
        store: store,
        modelDir: modelDir,
        source:
            'http://${runtimeServer.address.host}:${runtimeServer.port}/llama-server.zip',
        archiveBytes: runtimeArchive,
        cutAt: cutAt,
      );

      await notifier.downloadModel();

      final exeFile = File(
        p.join(modelDir, LocalModelNotifier.runtimeExecutableFileName),
      );
      final partFile = File(
        p.join(
          modelDir,
          '${LocalModelNotifier.runtimeArchiveFileName}.part',
        ),
      );
      expect(await exeFile.exists(), isTrue);
      expect(await partFile.exists(), isFalse);
      expect(runtimeRangeHeaders, ['bytes=$cutAt-']);
    });

    test(
      'falls back to a full redownload when the runtime server ignores the Range request',
      () async {
        final runtimeArchive = _sampleRuntimeZipBytes();
        const cutAt = 96;
        final runtimeRangeHeaders = <String?>[];
        var requestCount = 0;

        final runtimeServer = await HttpServer.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(() => runtimeServer.close(force: true));
        runtimeServer.listen((request) async {
          runtimeRangeHeaders.add(request.headers.value(HttpHeaders.rangeHeader));
          requestCount++;
          if (requestCount == 1) {
            expect(
              request.headers.value(HttpHeaders.rangeHeader),
              'bytes=$cutAt-',
            );
          } else {
            expect(request.headers.value(HttpHeaders.rangeHeader), isNull);
          }
          await _writeFullResponse(request: request, payload: runtimeArchive);
        });

        final container = _createTranslationContainer(
          tempDir: tempDir,
          platform: LocalRuntimePlatform.windows,
          serverDownloadUrlResolver: () async =>
              'http://${runtimeServer.address.host}:${runtimeServer.port}/llama-server.zip',
          downloadCandidatesBuilder: ({required bool useMirror}) => <String>[
            'http://127.0.0.1:9/model.gguf',
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(localModelProvider.notifier);
        final store = container.read(downloadTaskStoreProvider);
        final modelDir = await notifier.ensureInitialized();
        await Directory(modelDir).create(recursive: true);
        await File(
          p.join(modelDir, LocalModelNotifier.savedModelFileName),
        ).writeAsBytes(const [1, 2, 3], flush: true);
        await _seedRuntimePartial(
          store: store,
          modelDir: modelDir,
          source:
              'http://${runtimeServer.address.host}:${runtimeServer.port}/llama-server.zip',
          archiveBytes: runtimeArchive,
          cutAt: cutAt,
        );

        await notifier.downloadModel();

        final exeFile = File(
          p.join(modelDir, LocalModelNotifier.runtimeExecutableFileName),
        );
        expect(await exeFile.exists(), isTrue);
        expect(runtimeRangeHeaders, ['bytes=$cutAt-', null]);
      },
    );
  });

  group('TTS model download resume', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createProjectTempDir('wenwen_tome_tts_download_resume_');
    });

    tearDown(() async {
      if (!await tempDir.exists()) {
        return;
      }
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {
        // Best-effort cleanup for test-only directories.
      }
    });

    test(
      'resumes a partial TTS archive download with Range and installs it',
      () async {
        final archiveBytes = _sampleTtsArchiveBytes();
        const cutAt = 128;
        final rangeHeaders = <String?>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));

        server.listen((request) async {
          rangeHeaders.add(request.headers.value(HttpHeaders.rangeHeader));
          expect(
            request.headers.value(HttpHeaders.rangeHeader),
            'bytes=$cutAt-',
          );
          await _writeRangeResponse(
            request: request,
            payload: archiveBytes,
            start: cutAt,
          );
        });

        final store = DownloadTaskStore(
          appSupportDirProvider: () async => tempDir,
        );
        final manager = LocalTtsModelManager(
          appSupportDirProvider: () async => tempDir,
          downloadTaskStore: store,
        );
        final model = _buildTestTtsModel(
          'http://${server.address.host}:${server.port}/tts-model.tar.bz2',
        );

        await _seedTtsPartial(
          store: store,
          tempDir: tempDir,
          model: model,
          source:
              'http://${server.address.host}:${server.port}/tts-model.tar.bz2',
          archiveBytes: archiveBytes,
          cutAt: cutAt,
        );

        await _consumeProgress(
          manager.downloadModel(model, preferMirror: false),
        );

        final root = p.join(tempDir.path, 'wenwen_tome', 'local_tts');
        final partFile = File(p.join(root, '${model.id}.tar.bz2.part'));
        final installDir = Directory(p.join(root, model.id));
        final modelFile = File(
          p.join(installDir.path, model.sherpaManifest.modelFileName),
        );
        final tokensFile = File(
          p.join(installDir.path, model.sherpaManifest.tokensFileName),
        );

        expect(await modelFile.exists(), isTrue);
        expect(await tokensFile.exists(), isTrue);
        expect(await partFile.exists(), isFalse);
        expect(rangeHeaders, ['bytes=$cutAt-']);
      },
    );
  });
}

ProviderContainer _createTranslationContainer({
  required Directory tempDir,
  required List<String> Function({required bool useMirror})
  downloadCandidatesBuilder,
  LocalRuntimePlatform platform = LocalRuntimePlatform.android,
  Future<String> Function()? serverDownloadUrlResolver,
}) {
  final store = DownloadTaskStore(appSupportDirProvider: () async => tempDir);
  return ProviderContainer(
    overrides: [
      downloadTaskStoreProvider.overrideWithValue(store),
      localModelProvider.overrideWith(
        () => LocalModelNotifier(
          appSupportDirProvider: () async => tempDir,
          platformResolver: () => platform,
          localExecutor: _NoopLocalTranslationExecutor(),
          downloadTaskStore: store,
          downloadCandidatesBuilder: downloadCandidatesBuilder,
          serverDownloadUrlResolver: serverDownloadUrlResolver,
        ),
      ),
    ],
  );
}

Future<void> _consumeProgress(Stream<double> stream) async {
  final subscription = stream.listen((_) {});
  try {
    await subscription.asFuture<void>();
  } finally {
    await subscription.cancel();
  }
}

Future<void> _writeFullResponse({
  required HttpRequest request,
  required List<int> payload,
}) async {
  request.response.statusCode = HttpStatus.ok;
  request.response.headers.contentLength = payload.length;
  request.response.add(payload);
  await request.response.close();
}

Future<void> _writeRangeResponse({
  required HttpRequest request,
  required List<int> payload,
  required int start,
}) async {
  request.response.statusCode = HttpStatus.partialContent;
  request.response.headers
    ..set(HttpHeaders.contentLengthHeader, payload.length - start)
    ..set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-${payload.length - 1}/${payload.length}',
    );
  request.response.add(payload.sublist(start));
  await request.response.close();
}

Future<Directory> _createProjectTempDir(String prefix) async {
  final root = Directory(p.join(Directory.current.path, '.tmp'));
  await root.create(recursive: true);
  final dir = Directory(
    p.join(root.path, '$prefix${DateTime.now().microsecondsSinceEpoch}'),
  );
  await dir.create(recursive: true);
  return dir;
}

Future<void> _seedTranslationPartial({
  required DownloadTaskStore store,
  required String modelDir,
  required String source,
  required List<int> payload,
  required int cutAt,
}) async {
  final finalPath = p.join(modelDir, LocalModelNotifier.savedModelFileName);
  final partPath = '$finalPath.part';
  await Directory(modelDir).create(recursive: true);
  await File(partPath).writeAsBytes(payload.sublist(0, cutAt), flush: true);
  await store.markFailed(
    kind: DownloadTaskKind.translationModel,
    modelId: LocalModelNotifier.taskModelId,
    source: source,
    tempPath: partPath,
    finalPath: finalPath,
    error: 'Simulated interrupted download',
    downloadedBytes: cutAt,
    totalBytes: payload.length,
  );
}

Future<void> _seedTtsPartial({
  required DownloadTaskStore store,
  required Directory tempDir,
  required TtsModelConfig model,
  required String source,
  required List<int> archiveBytes,
  required int cutAt,
}) async {
  final root = Directory(p.join(tempDir.path, 'wenwen_tome', 'local_tts'));
  await root.create(recursive: true);
  final partPath = p.join(root.path, '${model.id}.tar.bz2.part');
  final finalPath = p.join(root.path, model.id);
  await File(
    partPath,
  ).writeAsBytes(archiveBytes.sublist(0, cutAt), flush: true);
  await store.markFailed(
    kind: DownloadTaskKind.ttsModel,
    modelId: model.id,
    source: source,
    tempPath: partPath,
    finalPath: finalPath,
    error: 'Simulated interrupted download',
    downloadedBytes: cutAt,
    totalBytes: archiveBytes.length,
  );
}

Future<void> _seedRuntimePartial({
  required DownloadTaskStore store,
  required String modelDir,
  required String source,
  required List<int> archiveBytes,
  required int cutAt,
}) async {
  final finalPath = p.join(
    modelDir,
    LocalModelNotifier.runtimeExecutableFileName,
  );
  final partPath = p.join(
    modelDir,
    '${LocalModelNotifier.runtimeArchiveFileName}.part',
  );
  await Directory(modelDir).create(recursive: true);
  await File(
    partPath,
  ).writeAsBytes(archiveBytes.sublist(0, cutAt), flush: true);
  await store.markFailed(
    kind: DownloadTaskKind.translationModel,
    modelId: LocalModelNotifier.runtimeTaskModelId,
    source: source,
    tempPath: partPath,
    finalPath: finalPath,
    error: 'Simulated interrupted runtime download',
    downloadedBytes: cutAt,
    totalBytes: archiveBytes.length,
  );
}

List<int> _sampleBytes(int length) {
  return List<int>.generate(length, (index) => index % 251);
}

List<int> _sampleTtsArchiveBytes() {
  final archive = Archive()
    ..addFile(ArchiveFile('test-voice/model.onnx', 512, _sampleBytes(512)))
    ..addFile(
      ArchiveFile('test-voice/tokens.txt', 64, List<int>.filled(64, 65)),
    );

  final tarBytes = TarEncoder().encode(archive);
  return BZip2Encoder().encode(tarBytes);
}

List<int> _sampleRuntimeZipBytes() {
  final archive = Archive()
    ..addFile(
      ArchiveFile(
        'bin/llama-server.exe',
        256,
        List<int>.generate(256, (index) => (index * 3) % 251),
      ),
    );
  return ZipEncoder().encode(archive)!;
}

TtsModelConfig _buildTestTtsModel(String url) {
  return TtsModelConfig(
    id: 'test_voice_pack',
    name: 'Test Voice Pack',
    size: '1 MB',
    description: 'Test-only Sherpa voice package.',
    sherpaManifest: SherpaTtsModelManifest(
      kind: SherpaTtsModelKind.vits,
      directoryName: 'test-voice',
      officialPackageUrl: url,
      mirrorPackageUrls: const <String>[],
      modelFileName: 'model.onnx',
      tokensFileName: 'tokens.txt',
    ),
  );
}

class _NoopLocalTranslationExecutor implements LocalTranslationExecutor {
  @override
  Future<LocalTranslationCheckResult> checkAvailability() async {
    return const LocalTranslationCheckResult(success: true, message: 'ready');
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<LocalTranslationCheckResult> prepare() => checkAvailability();

  @override
  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  }) async {
    return text;
  }
}
