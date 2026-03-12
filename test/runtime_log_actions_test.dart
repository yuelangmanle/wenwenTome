import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/logging/app_run_log_service.dart';
import 'package:wenwen_tome/features/logging/runtime_log_actions.dart';

void main() {
  group('RuntimeLogActions', () {
    late Directory tempDir;
    late AppRunLogService service;
    late RuntimeLogActions actions;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'wenwen_tome_log_actions_',
      );
      service = AppRunLogService(rootDirProvider: () async => tempDir);
      actions = RuntimeLogActions(service);
      await service.logInfo('seed');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('exports to the user selected path', () async {
      final expectedPath =
          '${tempDir.path}${Platform.pathSeparator}picked${Platform.pathSeparator}run.log';
      final out = await actions.exportWithPathPicker(
        pickPath: (_) async => expectedPath,
      );

      expect(out, expectedPath);
      expect(await File(expectedPath).exists(), isTrue);
      expect(
        (await File(expectedPath).readAsString()).contains('seed'),
        isTrue,
      );
    });

    test('returns null when user cancels path picker', () async {
      final out = await actions.exportWithPathPicker(
        pickPath: (_) async => null,
      );
      expect(out, isNull);
    });

    test('shares the current log file through share callback', () async {
      String? sharedPath;
      final resolvedPath = await actions.shareWith(
        shareFile: (path) async {
          sharedPath = path;
        },
      );

      expect(sharedPath, isNotNull);
      expect(sharedPath, resolvedPath);
      expect(await File(sharedPath!).exists(), isTrue);
    });

    test('clear removes all current log content', () async {
      await actions.clear();
      final content = await service.readAll();
      expect(content.contains('运行日志已清空'), isTrue);
    });
  });
}
