import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wenwen_tome/features/bootstrap/bootstrap_controller.dart';
import 'package:wenwen_tome/features/logging/app_run_log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BootstrapController', () {
    late Directory tempDir;
    late AppRunLogService logService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      tempDir = await Directory.systemTemp.createTemp(
        'wenwen_tome_bootstrap_test_',
      );
      logService = AppRunLogService(
        rootDirProvider: () async => tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
    });

    test('enters routingReady before background warmup completes', () async {
      final controller = BootstrapController(
        logService: logService,
        prewarmTask: () async {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        },
        backgroundWarmupTimeout: const Duration(seconds: 2),
      );

      await controller.start();

      expect(controller.snapshot.stage, BootstrapStage.routingReady);
      expect(controller.snapshot.backgroundWarmupPending, isTrue);
      expect(controller.snapshot.degradedStartup, isTrue);
      expect(controller.snapshot.prefs, isNotNull);
    });

    test('captures background warmup failures without blocking startup', () async {
      final controller = BootstrapController(
        logService: logService,
        prewarmTask: () async => throw StateError('boom'),
        backgroundWarmupTimeout: const Duration(seconds: 1),
      );

      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(controller.snapshot.stage, BootstrapStage.routingReady);
      expect(controller.snapshot.backgroundWarmupPending, isFalse);
      expect(controller.snapshot.backgroundWarmupError, isA<StateError>());
      expect(controller.snapshot.degradedStartup, isTrue);
    });

    test('uses safe mode when previous launch was unfinished', () async {
      SharedPreferences.setMockInitialValues({
        'startup_guard.unfinished': true,
      });

      final controller = BootstrapController(
        logService: logService,
        prewarmTask: () async {},
      );

      await controller.start();

      expect(controller.snapshot.stage, BootstrapStage.routingReady);
      expect(controller.snapshot.safeMode, isTrue);
      expect(controller.snapshot.backgroundWarmupPending, isFalse);
      expect(controller.snapshot.degradedStartup, isFalse);
    });
  });
}
