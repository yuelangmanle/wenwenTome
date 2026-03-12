import 'app_run_log_service.dart';

class RuntimeLogActions {
  RuntimeLogActions(this._service);

  final AppRunLogService _service;

  String suggestedFileName({DateTime? now}) {
    final ts = (now ?? DateTime.now()).toIso8601String().replaceAll(':', '-');
    return 'wenwen_tome_run_log_$ts.log';
  }

  Future<String?> exportWithPathPicker({
    required Future<String?> Function(String suggestedFileName) pickPath,
  }) async {
    final selected = await pickPath(suggestedFileName());
    if (selected == null || selected.trim().isEmpty) {
      await _service.logEvent(
        action: 'run_log.export',
        result: 'cancelled',
        errorCode: 'E_CANCELLED',
      );
      return null;
    }
    final exported = await _service.exportToPath(selected);
    await _service.logEvent(
      action: 'run_log.export',
      result: 'ok',
      context: <String, Object?>{'path': exported},
    );
    return exported;
  }

  Future<String> shareWith({
    required Future<void> Function(String filePath) shareFile,
  }) async {
    final logPath = await _service.getLogFilePath();
    await shareFile(logPath);
    await _service.logEvent(
      action: 'run_log.share',
      result: 'ok',
      context: <String, Object?>{'path': logPath},
    );
    return logPath;
  }

  Future<void> clear() async {
    await _service.clear();
    await _service.logEvent(
      action: 'run_log.clear',
      result: 'ok',
      message: '运行日志已清空',
    );
  }
}
