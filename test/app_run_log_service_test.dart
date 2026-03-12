import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/logging/app_run_log_service.dart';

void main() {
  group('AppRunLogService', () {
    late Directory tempDir;
    late AppRunLogService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('wenwen_tome_log_test_');
      service = AppRunLogService(
        rootDirProvider: () async => tempDir,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('appends and reads log lines', () async {
      await service.logInfo('first');
      await service.logError('second');

      final content = await service.readAll();
      expect(content.contains('first'), isTrue);
      expect(content.contains('second'), isTrue);
      expect(content.contains('[INFO]'), isTrue);
      expect(content.contains('[ERROR]'), isTrue);
    });

    test('stores logs under the project runtime log directory name', () async {
      final path = await service.getLogFilePath();
      expect(
        path,
        '${tempDir.path}${Platform.pathSeparator}运行日志${Platform.pathSeparator}run.log',
      );
    });

    test('exports current log file to target path', () async {
      await service.logInfo('export-me');
      final outPath = '${tempDir.path}${Platform.pathSeparator}out.log';
      final exported = await service.exportToPath(outPath);
      final file = File(exported);
      expect(await file.exists(), isTrue);
      final text = await file.readAsString();
      expect(text.contains('export-me'), isTrue);
    });

    test('clears log content', () async {
      await service.logInfo('will-be-cleared');
      await service.clear();
      final content = await service.readAll();
      expect(content.trim(), isEmpty);
    });
  });
}
