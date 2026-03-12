import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../storage/app_storage_paths.dart';

enum DownloadTaskKind { translationModel, ttsModel }

enum DownloadTaskStatus { queued, downloading, staged, completed, failed }

String downloadTaskKey(DownloadTaskKind kind, String modelId) =>
    '${kind.name}:$modelId';

class DownloadTaskRecord {
  const DownloadTaskRecord({
    required this.id,
    required this.kind,
    required this.modelId,
    required this.source,
    required this.tempPath,
    required this.finalPath,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.status,
    required this.updatedAt,
    this.error,
  });

  final String id;
  final DownloadTaskKind kind;
  final String modelId;
  final String source;
  final String tempPath;
  final String finalPath;
  final int downloadedBytes;
  final int totalBytes;
  final DownloadTaskStatus status;
  final String? error;
  final DateTime updatedAt;

  String get key => downloadTaskKey(kind, modelId);

  double get progress {
    if (totalBytes <= 0) {
      return status == DownloadTaskStatus.completed ? 1 : 0;
    }
    return (downloadedBytes / totalBytes).clamp(0, 1);
  }

  bool get isActive =>
      status == DownloadTaskStatus.queued ||
      status == DownloadTaskStatus.downloading ||
      status == DownloadTaskStatus.staged;

  DownloadTaskRecord copyWith({
    String? id,
    DownloadTaskKind? kind,
    String? modelId,
    String? source,
    String? tempPath,
    String? finalPath,
    int? downloadedBytes,
    int? totalBytes,
    DownloadTaskStatus? status,
    Object? error = _taskSentinel,
    DateTime? updatedAt,
  }) {
    return DownloadTaskRecord(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      modelId: modelId ?? this.modelId,
      source: source ?? this.source,
      tempPath: tempPath ?? this.tempPath,
      finalPath: finalPath ?? this.finalPath,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      error: identical(error, _taskSentinel) ? this.error : error as String?,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'kind': kind.name,
    'modelId': modelId,
    'source': source,
    'tempPath': tempPath,
    'finalPath': finalPath,
    'downloadedBytes': downloadedBytes,
    'totalBytes': totalBytes,
    'status': status.name,
    'error': error,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory DownloadTaskRecord.fromJson(Map<String, dynamic> json) {
    return DownloadTaskRecord(
      id: json['id'] as String,
      kind: DownloadTaskKind.values.firstWhere(
        (item) => item.name == json['kind'],
        orElse: () => DownloadTaskKind.ttsModel,
      ),
      modelId: json['modelId'] as String,
      source: json['source'] as String? ?? '',
      tempPath: json['tempPath'] as String? ?? '',
      finalPath: json['finalPath'] as String? ?? '',
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      totalBytes: json['totalBytes'] as int? ?? 0,
      status: DownloadTaskStatus.values.firstWhere(
        (item) => item.name == json['status'],
        orElse: () => DownloadTaskStatus.failed,
      ),
      error: json['error'] as String?,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

const Object _taskSentinel = Object();

class DownloadTaskStore {
  DownloadTaskStore({Future<Directory> Function()? appSupportDirProvider})
    : _appSupportDirProvider =
          appSupportDirProvider ?? getSafeApplicationSupportDirectory;

  static final DownloadTaskStore instance = DownloadTaskStore();

  final Future<Directory> Function() _appSupportDirProvider;
  final StreamController<List<DownloadTaskRecord>> _controller =
      StreamController<List<DownloadTaskRecord>>.broadcast();

  File? _file;
  bool _initialized = false;
  final Map<String, DownloadTaskRecord> _tasks = <String, DownloadTaskRecord>{};
  Future<void> _persistQueue = Future<void>.value();

  Future<void> ensureInitialized() async {
    if (_initialized) {
      return;
    }
    final dir = await _appSupportDirProvider();
    final root = Directory(p.join(dir.path, 'wenwen_tome'));
    await root.create(recursive: true);
    _file = File(p.join(root.path, 'download_tasks.json'));
    if (await _file!.exists()) {
      try {
        final decoded = jsonDecode(await _file!.readAsString());
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final task = DownloadTaskRecord.fromJson(
                Map<String, dynamic>.from(item),
              );
              _tasks[task.key] = task;
            }
          }
        }
      } catch (_) {
        _tasks.clear();
      }
    }
    _initialized = true;
    _emit();
  }

  Future<List<DownloadTaskRecord>> all() async {
    await ensureInitialized();
    return _snapshot();
  }

  Stream<List<DownloadTaskRecord>> watch() async* {
    await ensureInitialized();
    yield _snapshot();
    yield* _controller.stream;
  }

  Future<DownloadTaskRecord?> getTask(
    DownloadTaskKind kind,
    String modelId,
  ) async {
    await ensureInitialized();
    return _tasks[downloadTaskKey(kind, modelId)];
  }

  Future<void> upsert(DownloadTaskRecord task) async {
    await ensureInitialized();
    _tasks[task.key] = task;
    await _persist();
    _emit();
  }

  Future<void> remove(DownloadTaskKind kind, String modelId) async {
    await ensureInitialized();
    _tasks.remove(downloadTaskKey(kind, modelId));
    await _persist();
    _emit();
  }

  Future<void> markQueued({
    required DownloadTaskKind kind,
    required String modelId,
    required String source,
    required String tempPath,
    required String finalPath,
  }) {
    return upsert(
      DownloadTaskRecord(
        id: downloadTaskKey(kind, modelId),
        kind: kind,
        modelId: modelId,
        source: source,
        tempPath: tempPath,
        finalPath: finalPath,
        downloadedBytes: 0,
        totalBytes: 0,
        status: DownloadTaskStatus.queued,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markProgress({
    required DownloadTaskKind kind,
    required String modelId,
    required String source,
    required String tempPath,
    required String finalPath,
    required int downloadedBytes,
    required int totalBytes,
  }) {
    return upsert(
      DownloadTaskRecord(
        id: downloadTaskKey(kind, modelId),
        kind: kind,
        modelId: modelId,
        source: source,
        tempPath: tempPath,
        finalPath: finalPath,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        status: DownloadTaskStatus.downloading,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markCompleted({
    required DownloadTaskKind kind,
    required String modelId,
    required String source,
    required String finalPath,
  }) {
    return upsert(
      DownloadTaskRecord(
        id: downloadTaskKey(kind, modelId),
        kind: kind,
        modelId: modelId,
        source: source,
        tempPath: '',
        finalPath: finalPath,
        downloadedBytes: 1,
        totalBytes: 1,
        status: DownloadTaskStatus.completed,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markStaged({
    required DownloadTaskKind kind,
    required String modelId,
    required String source,
    required String stagedPath,
    required String finalPath,
    String? error,
  }) {
    return upsert(
      DownloadTaskRecord(
        id: downloadTaskKey(kind, modelId),
        kind: kind,
        modelId: modelId,
        source: source,
        tempPath: stagedPath,
        finalPath: finalPath,
        downloadedBytes: 1,
        totalBytes: 1,
        status: DownloadTaskStatus.staged,
        error: error,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markFailed({
    required DownloadTaskKind kind,
    required String modelId,
    required String source,
    required String tempPath,
    required String finalPath,
    required String error,
    int downloadedBytes = 0,
    int totalBytes = 0,
  }) {
    return upsert(
      DownloadTaskRecord(
        id: downloadTaskKey(kind, modelId),
        kind: kind,
        modelId: modelId,
        source: source,
        tempPath: tempPath,
        finalPath: finalPath,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes,
        status: DownloadTaskStatus.failed,
        error: error,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> markStaleActiveTasksAsFailed() async {
    await ensureInitialized();
    var changed = false;
    final now = DateTime.now();
    for (final entry in _tasks.entries.toList()) {
      final task = entry.value;
      if (task.isActive) {
        _tasks[entry.key] = task.copyWith(
          status: DownloadTaskStatus.failed,
          error: '应用重新进入后发现上次下载未完成，请重新开始。',
          updatedAt: now,
        );
        changed = true;
      }
    }
    if (changed) {
      await _persist();
      _emit();
    }
  }

  Future<void> _persist() async {
    final completer = Completer<void>();
    _persistQueue = _persistQueue.then((_) async {
      try {
        await _persistNow();
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<void> _persistNow() async {
    final file = _file;
    if (file == null) {
      return;
    }
    await file.parent.create(recursive: true);
    final part = File('${file.path}.part');
    final payload = jsonEncode(
      _snapshot().map((item) => item.toJson()).toList(growable: false),
    );
    if (await part.exists()) {
      await part.delete();
    }
    await part.parent.create(recursive: true);
    await part.writeAsString(payload, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await file.parent.create(recursive: true);
    await part.rename(file.path);
  }

  void _emit() {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(_snapshot());
  }

  List<DownloadTaskRecord> _snapshot() {
    final items = _tasks.values.toList(growable: false)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return items;
  }
}

final downloadTaskStoreProvider = Provider<DownloadTaskStore>(
  (ref) => DownloadTaskStore.instance,
);

final downloadTasksProvider = StreamProvider<List<DownloadTaskRecord>>((ref) {
  final store = ref.watch(downloadTaskStoreProvider);
  return store.watch();
});

final downloadTaskProvider = Provider.family<DownloadTaskRecord?, String>((
  ref,
  key,
) {
  final tasks = ref.watch(downloadTasksProvider).asData?.value ?? const [];
  for (final task in tasks) {
    if (task.key == key) {
      return task;
    }
  }
  return null;
});
