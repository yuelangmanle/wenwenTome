import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../app/runtime_platform.dart';
import '../../core/storage/app_storage_paths.dart';

class AppRunLogService {
  AppRunLogService({
    Future<Directory> Function()? rootDirProvider,
    String logDirName = '运行日志',
  }) : _rootDirProvider = rootDirProvider ?? _defaultRootDirProvider,
       _logDirName = logDirName;

  static final AppRunLogService instance = AppRunLogService();

  final Future<Directory> Function() _rootDirProvider;
  final String _logDirName;

  static Directory? _findProjectRoot(Directory startDir) {
    var current = startDir.absolute;
    while (true) {
      if (File(p.join(current.path, 'pubspec.yaml')).existsSync()) {
        return current;
      }
      final parent = current.parent;
      if (parent.path == current.path) {
        return null;
      }
      current = parent;
    }
  }

  static Future<Directory> _defaultRootDirProvider() async {
    final platform = detectLocalRuntimePlatform();
    if (platform != LocalRuntimePlatform.windows) {
      return await getSafeApplicationSupportDirectory();
    }

    final currentProjectRoot = _findProjectRoot(Directory.current);
    if (currentProjectRoot != null) {
      return currentProjectRoot;
    }

    final exeDir = File(Platform.resolvedExecutable).parent;
    final exeProjectRoot = _findProjectRoot(exeDir);
    if (exeProjectRoot != null) {
      return exeProjectRoot;
    }

    try {
      return await getSafeApplicationSupportDirectory();
    } catch (_) {
      return exeDir;
    }
  }

  Future<Directory> _logDir() async {
    final platform = detectLocalRuntimePlatform();
    final root = await _rootDirProvider();
    final preferred = platform == LocalRuntimePlatform.windows
        ? Directory(p.join(root.path, _logDirName))
        : Directory(p.join(root.path, 'wenwen_tome', 'logs'));
    try {
      await preferred.create(recursive: true);
      return preferred;
    } catch (_) {
      try {
        final supportDir = await getSafeApplicationSupportDirectory();
        final fallback = Directory(
          p.join(supportDir.path, 'wenwen_tome', 'logs'),
        );
        await fallback.create(recursive: true);
        return fallback;
      } catch (_) {
        final tempFallback = Directory(
          p.join(Directory.systemTemp.path, 'wenwen_tome', 'logs'),
        );
        await tempFallback.create(recursive: true);
        return tempFallback;
      }
    }
  }

  Future<File> _logFile() async {
    final logDir = await _logDir();
    final file = File(p.join(logDir.path, 'run.log'));
    await _migrateLegacyLogIfNeeded(file);
    if (!await file.exists()) {
      await file.writeAsString('');
    }
    return file;
  }

  Future<void> _migrateLegacyLogIfNeeded(File target) async {
    if (await target.exists()) {
      return;
    }

    for (final candidate in await _legacyLogCandidates(target)) {
      if (candidate.path == target.path || !await candidate.exists()) {
        continue;
      }
      final content = await candidate.readAsString();
      if (content.trim().isEmpty) {
        continue;
      }
      await target.parent.create(recursive: true);
      await target.writeAsString(content, flush: true);
      return;
    }
  }

  Future<List<File>> _legacyLogCandidates(File target) async {
    final candidates = <String>{};
    final currentProjectRoot = _findProjectRoot(Directory.current);
    if (currentProjectRoot != null) {
      candidates.add(p.join(currentProjectRoot.path, _logDirName, 'run.log'));
    }

    final exeDir = File(Platform.resolvedExecutable).parent;
    final exeProjectRoot = _findProjectRoot(exeDir);
    if (exeProjectRoot != null) {
      candidates.add(p.join(exeProjectRoot.path, _logDirName, 'run.log'));
    }

    candidates.add(
      p.join(Directory.systemTemp.path, 'wenwen_tome', 'logs', 'run.log'),
    );
    candidates.remove(target.path);
    return candidates.map(File.new).toList(growable: false);
  }

  Future<String> getLogFilePath() async => (await _logFile()).path;

  Future<void> _append(String level, String message) async {
    final file = await _logFile();
    final timestamp = DateTime.now().toIso8601String();
    await file.writeAsString(
      '[$timestamp] [$level] $message\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> logInfo(String message) => _append('INFO', message);

  Future<void> logError(String message) => _append('ERROR', message);

  Future<void> logEvent({
    required String action,
    required String result,
    String? errorCode,
    String? message,
    Map<String, Object?>? context,
    int? durationMs,
    Object? error,
    StackTrace? stackTrace,
    String level = 'INFO',
  }) async {
    final payload = <String, Object?>{
      'action': action,
      'result': result,
      if (errorCode?.trim().isNotEmpty == true) 'error_code': errorCode,
      ...?(durationMs == null
          ? null
          : <String, Object?>{'duration_ms': durationMs}),
      if (message?.trim().isNotEmpty == true) 'message': message,
      if (context?.isNotEmpty == true) 'context': context,
      if (error != null) 'error': error.toString(),
      if (stackTrace != null) 'stack': stackTrace.toString(),
    };
    await _append(level, 'RUN_EVENT ${jsonEncode(payload)}');
  }

  Future<String> readAll() async {
    final file = await _logFile();
    if (!await file.exists()) return '';
    return file.readAsString();
  }

  Future<void> clear() async {
    final file = await _logFile();
    await file.writeAsString('');
  }

  Future<String> exportToPath(String targetPath) async {
    final source = await _logFile();
    final target = File(targetPath);
    await target.parent.create(recursive: true);
    await source.copy(target.path);
    return target.path;
  }
}
