import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/app/runtime_platform.dart';
import 'package:wenwen_tome/core/downloads/download_task_store.dart';
import 'package:wenwen_tome/features/translation/local_model_service.dart';
import 'package:wenwen_tome/features/translation/local_translation_executor.dart';

void main() {
  group('LocalModelNotifier initialization', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'wenwen_tome_local_model_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('initializes model directory before download flow', () async {
      final notifier = LocalModelNotifier(
        appSupportDirProvider: () async => tempDir,
      );

      final resolved = await notifier.ensureInitialized();

      expect(resolved, p.join(tempDir.path, 'models', 'hy-mt'));
      expect(notifier.modelDirectoryPath, resolved);
    });

    test(
      'android availability no longer reports windows only when local executor is ready',
      () async {
        final container = ProviderContainer(
          overrides: [
            localModelProvider.overrideWith(
              () => LocalModelNotifier(
                appSupportDirProvider: () async => tempDir,
                platformResolver: () => LocalRuntimePlatform.android,
                localExecutor: _ReadyLocalTranslationExecutor(),
                downloadTaskStore: DownloadTaskStore(
                  appSupportDirProvider: () async => tempDir,
                ),
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        final notifier = container.read(localModelProvider.notifier);
        final resolved = await notifier.ensureInitialized();
        await File(
          p.join(resolved, LocalModelNotifier.savedModelFileName),
        ).create(recursive: true);

        final result = await notifier.checkAvailability();

        expect(result.success, isTrue);
        expect(result.message.contains('Windows'), isFalse);
      },
    );

    test('android start and stop use prepare and dispose hooks', () async {
      final executor = _TrackingLocalTranslationExecutor();
      final container = ProviderContainer(
        overrides: [
          localModelProvider.overrideWith(
            () => LocalModelNotifier(
              appSupportDirProvider: () async => tempDir,
              platformResolver: () => LocalRuntimePlatform.android,
              localExecutor: executor,
              downloadTaskStore: DownloadTaskStore(
                appSupportDirProvider: () async => tempDir,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(localModelProvider.notifier);
      final resolved = await notifier.ensureInitialized();
      await File(
        p.join(resolved, LocalModelNotifier.savedModelFileName),
      ).create(recursive: true);

      final availability = await notifier.checkAvailability();
      expect(availability.success, isTrue);
      expect(executor.checkCount, 1);
      expect(executor.prepareCount, 0);

      await notifier.startServer();
      expect(executor.prepareCount, 1);
      expect(container.read(localModelProvider).isRunning, isTrue);

      await notifier.stopServer();
      expect(executor.disposeCount, 1);
      expect(container.read(localModelProvider).isRunning, isFalse);
    });

    test('android start deduplicates concurrent prepare requests', () async {
      final executor = _BlockingLocalTranslationExecutor();
      final container = ProviderContainer(
        overrides: [
          localModelProvider.overrideWith(
            () => LocalModelNotifier(
              appSupportDirProvider: () async => tempDir,
              platformResolver: () => LocalRuntimePlatform.android,
              localExecutor: executor,
              downloadTaskStore: DownloadTaskStore(
                appSupportDirProvider: () async => tempDir,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(localModelProvider.notifier);
      final resolved = await notifier.ensureInitialized();
      await File(
        p.join(resolved, LocalModelNotifier.savedModelFileName),
      ).create(recursive: true);
      final availability = await notifier.checkAvailability();
      expect(availability.success, isTrue);

      final first = notifier.startServer();
      await executor.prepareStarted.future;
      final second = notifier.startServer();
      executor.completePrepare();
      await Future.wait([first, second]);

      expect(executor.prepareCount, 1);
      expect(container.read(localModelProvider).isRunning, isTrue);
    });

    test('android start surfaces prepare timeout instead of hanging', () async {
      final executor = _NeverCompletesLocalTranslationExecutor();
      final container = ProviderContainer(
        overrides: [
          localModelProvider.overrideWith(
            () => LocalModelNotifier(
              appSupportDirProvider: () async => tempDir,
              platformResolver: () => LocalRuntimePlatform.android,
              localExecutor: executor,
              downloadTaskStore: DownloadTaskStore(
                appSupportDirProvider: () async => tempDir,
              ),
              androidPrepareTimeout: const Duration(milliseconds: 10),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(localModelProvider.notifier);
      final resolved = await notifier.ensureInitialized();
      await File(
        p.join(resolved, LocalModelNotifier.savedModelFileName),
      ).create(recursive: true);
      final availability = await notifier.checkAvailability();
      expect(availability.success, isTrue);

      await notifier.startServer();

      expect(executor.prepareCount, 1);
      expect(container.read(localModelProvider).isRunning, isFalse);
      expect(container.read(localModelProvider).statusText, isNotEmpty);
    });
  });
}

class _ReadyLocalTranslationExecutor implements LocalTranslationExecutor {
  @override
  Future<LocalTranslationCheckResult> checkAvailability() async {
    return const LocalTranslationCheckResult(
      success: true,
      message: 'Android 本地推理可用',
    );
  }

  @override
  Future<LocalTranslationCheckResult> prepare() => checkAvailability();

  @override
  Future<void> dispose() async {}

  @override
  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  }) async {
    return text;
  }
}

class _TrackingLocalTranslationExecutor implements LocalTranslationExecutor {
  int checkCount = 0;
  int prepareCount = 0;
  int disposeCount = 0;

  @override
  Future<LocalTranslationCheckResult> checkAvailability() async {
    checkCount++;
    return const LocalTranslationCheckResult(success: true, message: 'ready');
  }

  @override
  Future<LocalTranslationCheckResult> prepare() async {
    prepareCount++;
    return const LocalTranslationCheckResult(
      success: true,
      message: 'prepared',
    );
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }

  @override
  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  }) async {
    return text;
  }
}

class _BlockingLocalTranslationExecutor implements LocalTranslationExecutor {
  _BlockingLocalTranslationExecutor();

  final Completer<void> prepareStarted = Completer<void>();
  final Completer<void> _gate = Completer<void>();
  int prepareCount = 0;

  void completePrepare() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<LocalTranslationCheckResult> checkAvailability() async {
    return const LocalTranslationCheckResult(success: true, message: 'ready');
  }

  @override
  Future<LocalTranslationCheckResult> prepare() async {
    prepareCount++;
    if (!prepareStarted.isCompleted) {
      prepareStarted.complete();
    }
    await _gate.future;
    return const LocalTranslationCheckResult(
      success: true,
      message: 'prepared',
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  }) async {
    return text;
  }
}

class _NeverCompletesLocalTranslationExecutor
    implements LocalTranslationExecutor {
  int prepareCount = 0;

  @override
  Future<LocalTranslationCheckResult> checkAvailability() async {
    return const LocalTranslationCheckResult(success: true, message: 'ready');
  }

  @override
  Future<LocalTranslationCheckResult> prepare() {
    prepareCount++;
    return Completer<LocalTranslationCheckResult>().future;
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  }) async {
    return text;
  }
}
