import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<Directory> getSafeApplicationSupportDirectory() async {
  try {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return dir;
  } catch (_) {
    final dir = Directory(
      p.join(Directory.systemTemp.path, 'wenwen_tome', 'support'),
    );
    await dir.create(recursive: true);
    return dir;
  }
}

Future<Directory> getSafeApplicationDocumentsDirectory() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    return dir;
  } catch (_) {
    final dir = Directory(
      p.join(Directory.systemTemp.path, 'wenwen_tome', 'documents'),
    );
    await dir.create(recursive: true);
    return dir;
  }
}

Future<Directory> getSafeTemporaryDirectory() async {
  try {
    final dir = await getTemporaryDirectory();
    await dir.create(recursive: true);
    return dir;
  } catch (_) {
    final dir = Directory(p.join(Directory.systemTemp.path, 'wenwen_tome', 'tmp'));
    await dir.create(recursive: true);
    return dir;
  }
}
