import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../storage/app_storage_paths.dart';

bool _ffiReady = false;

DatabaseFactory get appDatabaseFactory {
  if (Platform.isWindows || Platform.isLinux) {
    if (!_ffiReady) {
      sqfliteFfiInit();
      _ffiReady = true;
    }
    return databaseFactoryFfi;
  }
  return databaseFactory;
}

Future<String> getAppDatabasePath(String fileName) async {
  if (Platform.isWindows || Platform.isLinux) {
    final supportDir = await getApplicationSupportDirectory();
    final dbDir = Directory(p.join(supportDir.path, 'wenwen_tome', 'databases'));
    await dbDir.create(recursive: true);
    return p.join(dbDir.path, fileName);
  }

  final supportDir = await getSafeApplicationSupportDirectory();
  final dbDir = Directory(p.join(supportDir.path, 'wenwen_tome', 'databases'));
  await dbDir.create(recursive: true);
  return p.join(dbDir.path, fileName);
}
