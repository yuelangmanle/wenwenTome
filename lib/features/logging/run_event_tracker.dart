import 'dart:async';

import 'app_run_log_service.dart';

class AppOperationCancelledException implements Exception {
  AppOperationCancelledException(this.action);

  final String action;

  @override
  String toString() => 'AppOperationCancelledException(action=$action)';
}

class RunEventTracker {
  RunEventTracker({AppRunLogService? service})
    : _service = service ?? AppRunLogService.instance;

  final AppRunLogService _service;

  Future<T> track<T>({
    required String action,
    required Future<T> Function() operation,
    Map<String, Object?>? context,
    Duration? timeout,
    bool Function()? isCancelled,
  }) async {
    if (isCancelled?.call() == true) {
      await _service.logEvent(
        action: action,
        result: 'cancelled',
        errorCode: 'E_CANCELLED',
        context: context,
      );
      throw AppOperationCancelledException(action);
    }

    final startedAt = DateTime.now();
    await _service.logEvent(action: action, result: 'start', context: context);
    try {
      final future = operation();
      final result = timeout == null ? await future : await future.timeout(timeout);
      if (isCancelled?.call() == true) {
        await _service.logEvent(
          action: action,
          result: 'cancelled',
          errorCode: 'E_CANCELLED',
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          context: context,
        );
        throw AppOperationCancelledException(action);
      }
      await _service.logEvent(
        action: action,
        result: 'ok',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: context,
      );
      return result;
    } on TimeoutException catch (error, stackTrace) {
      await _service.logEvent(
        action: action,
        result: 'timeout',
        errorCode: 'E_TIMEOUT',
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: context,
        error: error,
        stackTrace: stackTrace,
        level: 'ERROR',
      );
      rethrow;
    } catch (error, stackTrace) {
      final code = _mapErrorCode(error);
      await _service.logEvent(
        action: action,
        result: 'error',
        errorCode: code,
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
        context: context,
        error: error,
        stackTrace: stackTrace,
        level: 'ERROR',
      );
      rethrow;
    }
  }

  String _mapErrorCode(Object error) {
    if (error is AppOperationCancelledException) return 'E_CANCELLED';
    if (error is TimeoutException) return 'E_TIMEOUT';
    final type = error.runtimeType.toString();
    if (type.contains('SocketException')) return 'E_NETWORK';
    if (type.contains('HttpException') || type.contains('ClientException')) {
      return 'E_HTTP';
    }
    if (type.contains('FileSystemException')) return 'E_IO';
    if (type.contains('FormatException')) return 'E_PARSE';
    return 'E_UNKNOWN';
  }
}

