import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/features/webnovel/webnovel_repository.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = Directory(
      p.join(
        Directory.current.path,
        '.dart_tool',
        'test_tmp',
        'webnovel_source_pack',
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

  test(
    'imports the local large Legado source pack with broad compatibility',
    () async {
      final packageRoot = Directory.current;
      final sourceFile = packageRoot
          .listSync()
          .whereType<File>()
          .where((file) => p.extension(file.path).toLowerCase() == '.json')
          .where((file) => file.lengthSync() > 10 * 1024 * 1024)
          .cast<File?>()
          .firstWhere((file) => file != null, orElse: () => null);

      if (sourceFile == null) {
        fail('Missing the local large source pack JSON in the package root.');
      }

      final repository = WebNovelRepository.test(
        databasePathProvider: (fileName) async =>
            p.join(tempDir.path, fileName),
      );
      await repository.listSources();

      final report = await repository.importSourcesInputWithReport(
        await sourceFile.readAsString(),
      );
      final sources = await repository.listSources();
      final customSourceCount = sources
          .where((source) => !source.builtin)
          .length;

      // Keep a visible probe in CI/local runs so compatibility regressions are obvious.
      // ignore: avoid_print
      print(
        'large-source-pack: total=${report.totalEntries}, imported=${report.importedCount}, '
        'skipped=${report.skippedCount}, legacy=${report.legacyMappedCount}, '
        'warnings=${report.warnings.length}, stored=${sources.length}',
      );

      expect(report.totalEntries, greaterThan(3000));
      expect(report.importedCount, greaterThan(2800));
      expect(report.importedCount + report.skippedCount, report.totalEntries);
      expect(customSourceCount, greaterThan(3300));
      expect(report.importedCount - customSourceCount, lessThanOrEqualTo(16));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
