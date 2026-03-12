import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/core/downloads/download_task_store.dart';
import 'package:wenwen_tome/features/library/data/book_model.dart';
import 'package:wenwen_tome/features/library/data/library_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('mobile regressions', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await _createTempDir('mobile_regression_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('download task store survives concurrent status writes', () async {
      final store = DownloadTaskStore(appSupportDirProvider: () async => tempDir);
      const finalPath = '/tmp/model.gguf';
      const tempPath = '/tmp/model.gguf.part';

      await store.markQueued(
        kind: DownloadTaskKind.translationModel,
        modelId: 'translation-model',
        source: 'https://example.invalid/model.gguf',
        tempPath: tempPath,
        finalPath: finalPath,
      );

      await Future.wait(
        List<Future<void>>.generate(12, (index) {
          return store.markProgress(
            kind: DownloadTaskKind.translationModel,
            modelId: 'translation-model',
            source: 'https://example.invalid/model.gguf',
            tempPath: tempPath,
            finalPath: finalPath,
            downloadedBytes: (index + 1) * 128,
            totalBytes: 4096,
          );
        }),
      );

      final records = await store.all();
      expect(records, hasLength(1));
      expect(records.single.downloadedBytes, 1536);

      final taskFile = File(
        p.join(tempDir.path, 'wenwen_tome', 'download_tasks.json'),
      );
      expect(await taskFile.exists(), isTrue);

      final decoded = jsonDecode(await taskFile.readAsString()) as List<dynamic>;
      expect(decoded, hasLength(1));
      expect(
        (decoded.single as Map<String, dynamic>)['downloadedBytes'],
        1536,
      );
    });

    test('library import succeeds on an empty bookshelf snapshot', () async {
      final service = LibraryService(
        documentsDirProvider: () async => tempDir,
      );
      final sourceFile = File(p.join(tempDir.path, 'source.txt'));
      await sourceFile.writeAsString('hello bookshelf', flush: true);

      final book = await service.addBook(
        sourceFile.path,
        mode: ImportStorageMode.appCopy,
      );

      expect(book.format, BookFormat.txt);
      final books = await service.loadBooks();
      expect(books, hasLength(1));
      expect(books.single.title, 'source');
      expect(await File(books.single.filePath).exists(), isTrue);
    });

    test('binary asset manifest API reads bundled asset entries', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(
        _FakeAssetManifestBundle(<String, Object>{
          'assets/local_tts/vits-piper-zh_CN-huayan-medium/zh_CN-huayan-medium.onnx':
              <Object>[
                <String, Object>{
                  'asset':
                      'assets/local_tts/vits-piper-zh_CN-huayan-medium/zh_CN-huayan-medium.onnx',
                },
              ],
        }),
      );
      final assets = manifest.listAssets();

      expect(
        assets.contains(
          'assets/local_tts/vits-piper-zh_CN-huayan-medium/zh_CN-huayan-medium.onnx',
        ),
        isTrue,
      );
    });
  });
}

Future<Directory> _createTempDir(String prefix) async {
  final root = Directory(p.join(Directory.current.path, '.tmp'));
  await root.create(recursive: true);
  final dir = Directory(
    p.join(root.path, '$prefix${DateTime.now().microsecondsSinceEpoch}'),
  );
  await dir.create(recursive: true);
  return dir;
}

class _FakeAssetManifestBundle extends CachingAssetBundle {
  _FakeAssetManifestBundle(this._manifest);

  final Map<String, Object> _manifest;

  @override
  Future<ByteData> load(String key) async {
    if (key != 'AssetManifest.bin') {
      throw StateError('Unexpected asset key: $key');
    }
    final bytes = const StandardMessageCodec().encodeMessage(_manifest)!;
    return bytes;
  }
}
