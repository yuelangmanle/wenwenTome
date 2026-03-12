import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/features/library/data/library_service.dart';
import 'package:wenwen_tome/features/library/providers/library_providers.dart';
import 'package:wenwen_tome/features/reader/local_tts_model_manager.dart';
import 'package:wenwen_tome/features/translation/local_model_service.dart';

void main() {
  group('Library Import Policy', () {
    test('accepts only supported ebook file types', () {
      expect(LibraryService.isSupportedImportPath('a.epub'), isTrue);
      expect(LibraryService.isSupportedImportPath('a.PDF'), isTrue);
      expect(LibraryService.isSupportedImportPath('a.cbz'), isTrue);
      expect(LibraryService.isSupportedImportPath('a.cbr'), isTrue);

      expect(LibraryService.isSupportedImportPath('a.exe'), isFalse);
      expect(LibraryService.isSupportedImportPath('a.zip'), isFalse);
      expect(LibraryService.isSupportedImportPath('a'), isFalse);
    });
  });

  group('TTS Model Download Policy', () {
    test('exposes three built-in models and one downloadable model', () {
      expect(LocalTtsModelManager.availableModels, hasLength(4));

      final builtIn = LocalTtsModelManager.availableModels
          .where((model) => model.isBuiltIn)
          .toList();
      final downloadable = LocalTtsModelManager.availableModels
          .where((model) => !model.isBuiltIn)
          .toList();

      expect(builtIn, hasLength(3));
      expect(downloadable, hasLength(1));
    });

    test('built-in models have no download candidates', () {
      final builtIn = LocalTtsModelManager.availableModels
          .where((item) => item.isBuiltIn)
          .toList();

      for (final model in builtIn) {
        final candidates = LocalTtsModelManager.downloadCandidates(
          model,
          preferMirror: true,
        );

        expect(candidates, isEmpty, reason: model.id);
      }
    });

    test('built-in sherpa bundles are included in flutter assets', () {
      final builtIn = LocalTtsModelManager.availableModels
          .where((item) => item.isBuiltIn)
          .toList();

      for (final model in builtIn) {
        final manifest = model.sherpaManifest;
        expect(manifest.bundledAssetPrefix, isNotNull, reason: model.id);

        final assetDir = Directory(
          p.join(
            Directory.current.path,
            'assets',
            'local_tts',
            manifest.directoryName,
          ),
        );
        expect(assetDir.existsSync(), isTrue, reason: model.id);
        expect(
          File(p.join(assetDir.path, manifest.modelFileName)).existsSync(),
          isTrue,
          reason: model.id,
        );
        expect(
          File(p.join(assetDir.path, manifest.tokensFileName)).existsSync(),
          isTrue,
          reason: model.id,
        );
      }

      final pubspec = File(
        p.join(Directory.current.path, 'pubspec.yaml'),
      ).readAsStringSync();
      expect(pubspec.contains('assets/local_tts/'), isTrue);
    });

    test('each downloadable model has both official and mirror urls', () {
      final downloadable = LocalTtsModelManager.availableModels
          .where((model) => !model.isBuiltIn)
          .toList();

      for (final model in downloadable) {
        final official = LocalTtsModelManager.downloadCandidates(
          model,
          preferMirror: false,
        );
        final mirror = LocalTtsModelManager.downloadCandidates(
          model,
          preferMirror: true,
        );

        expect(official, isNotEmpty, reason: model.id);
        expect(mirror, isNotEmpty, reason: model.id);
        expect(official.toSet().length, official.length, reason: model.id);
        expect(mirror.toSet().length, mirror.length, reason: model.id);
        expect(
          official.any((url) => url.contains('github.com')),
          isTrue,
          reason: model.id,
        );
        expect(
          mirror.any((url) => url.contains('mirror.ghproxy.com')),
          isTrue,
          reason: model.id,
        );
      }
    });

    test(
      'android download plans expose official github packages and mirrors',
      () {
        final downloadable = LocalTtsModelManager.availableModels
            .where((model) => !model.isBuiltIn)
            .toList();

        for (final model in downloadable) {
          final plan = LocalTtsModelManager.resolveAndroidDownloadPlan(model);
          final mirrorCandidates = plan.candidates(preferMirror: true);

          expect(
            plan.officialPackageUrl,
            contains('github.com'),
            reason: model.id,
          );
          expect(plan.directoryName, isNotEmpty, reason: model.id);
          expect(
            mirrorCandidates.any((url) => url.contains('mirror.ghproxy.com')),
            isTrue,
            reason: model.id,
          );
        }
      },
    );
  });

  group('Translation Model Download Policy', () {
    test('contains both official and mirror urls', () {
      final official = LocalModelNotifier.downloadCandidates(useMirror: false);
      expect(official.first, equals(LocalModelNotifier.modelUrlOfficial));
      expect(official.contains(LocalModelNotifier.modelUrlMirror), isTrue);

      final mirror = LocalModelNotifier.downloadCandidates(useMirror: true);
      expect(mirror.first, equals(LocalModelNotifier.modelUrlMirror));
      expect(mirror.contains(LocalModelNotifier.modelUrlOfficial), isTrue);
    });
  });

  group('Import Picker Normalization', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'wenwen_tome_pick_normalize_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('keeps original path files and persists bytes-only files', () async {
      final onDiskBookPath = p.join(tempDir.path, 'existing.epub');
      await File(onDiskBookPath).writeAsString('existing');

      final picked = <PlatformFile>[
        PlatformFile(name: 'existing.epub', size: 8, path: onDiskBookPath),
        PlatformFile(
          name: 'stream.txt',
          size: 5,
          readStream: Stream<List<int>>.fromIterable([
            Uint8List.fromList([104, 101]),
            Uint8List.fromList([108, 108, 111]),
          ]),
        ),
        PlatformFile(
          name: 'upload.pdf',
          size: 4,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
      ];

      final result = await normalizePickedBookFiles(
        picked,
        bytesImportDir: Directory(p.join(tempDir.path, 'imports')),
      );

      expect(result.any((value) => value == onDiskBookPath), isTrue);
      final persisted = result
          .where((value) => value.endsWith('upload.pdf'))
          .toList();
      expect(persisted.length, 1);
      expect(await File(persisted.first).exists(), isTrue);
      expect(await File(persisted.first).readAsBytes(), [1, 2, 3, 4]);

      final streamPersisted = result
          .where((value) => value.endsWith('stream.txt'))
          .toList();
      expect(streamPersisted.length, 1);
      expect(await File(streamPersisted.first).exists(), isTrue);
      expect(await File(streamPersisted.first).readAsString(), 'hello');
    });
  });

  group('TTS Archive Extraction', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'wenwen_tome_tts_extract_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('extracts zip archive to target directory', () async {
      final archive = Archive()
        ..addFile(
          ArchiveFile('model/config.json', 11, utf8.encode('{"ok":true}')),
        );
      final bytes = ZipEncoder().encode(archive)!;
      final zipPath = p.join(tempDir.path, 'model_payload.bin');
      await File(zipPath).writeAsBytes(bytes);

      final outDir = Directory(p.join(tempDir.path, 'out'));
      await LocalTtsModelManager().extractArchiveFile(File(zipPath), outDir);

      final extracted = File(p.join(outDir.path, 'model', 'config.json'));
      expect(await extracted.exists(), isTrue);
      expect(await extracted.readAsString(), '{"ok":true}');
    });
  });
}
