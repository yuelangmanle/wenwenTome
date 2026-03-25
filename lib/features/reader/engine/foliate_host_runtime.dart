import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../core/storage/app_storage_paths.dart';

class FoliateHostRuntimeSession {
  const FoliateHostRuntimeSession({
    required this.rootDirectory,
    required this.entryFile,
    required this.assetKeys,
  });

  final Directory rootDirectory;
  final File entryFile;
  final List<String> assetKeys;
}

class FoliateHostRuntime {
  static const String assetPrefix = 'assets/reader/foliate/';
  static const String _entryAsset = '${assetPrefix}reader.html';

  static Future<FoliateHostRuntimeSession> ensureReady() async {
    final supportDir = await getSafeApplicationSupportDirectory();
    final runtimeDir = Directory(
      p.join(supportDir.path, 'reader_engines', 'foliate_host'),
    );
    await runtimeDir.create(recursive: true);

    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assetKeys =
        manifest
            .listAssets()
            .where((key) => key.startsWith(assetPrefix))
            .toList(growable: false)
          ..sort();

    for (final assetKey in assetKeys) {
      final relativePath = assetKey.substring(assetPrefix.length);
      final targetFile = File(p.join(runtimeDir.path, relativePath));
      await targetFile.parent.create(recursive: true);
      await _copyAssetIfNeeded(assetKey, targetFile);
    }

    return FoliateHostRuntimeSession(
      rootDirectory: runtimeDir,
      entryFile: File(p.join(runtimeDir.path, 'reader.html')),
      assetKeys: assetKeys,
    );
  }

  static Future<void> _copyAssetIfNeeded(
    String assetKey,
    File targetFile,
  ) async {
    final data = await rootBundle.load(assetKey);
    final bytes = Uint8List.sublistView(data);
    if (await targetFile.exists()) {
      final existing = await targetFile.readAsBytes();
      if (_bytesEqual(existing, bytes)) {
        return;
      }
    }
    await targetFile.writeAsBytes(bytes, flush: true);
  }

  static bool _bytesEqual(Uint8List left, Uint8List right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  static String assetKeyForRelativePath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    return '$assetPrefix$normalized';
  }

  static bool containsRequiredEntry(Iterable<String> assetKeys) {
    return assetKeys.contains(_entryAsset);
  }
}
