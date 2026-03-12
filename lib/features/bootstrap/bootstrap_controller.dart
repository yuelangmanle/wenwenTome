import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/app_run_log_service.dart';
import '../webnovel/webnovel_repository.dart';
import 'startup_guard_service.dart';

enum BootstrapStage {
  starting,
  logReady,
  prefsReady,
  webNovelReady,
  routingReady,
  failed,
}

class BootstrapSnapshot {
  const BootstrapSnapshot({
    required this.stage,
    required this.message,
    this.safeMode = false,
    this.degradedStartup = false,
    this.backgroundWarmupPending = false,
    this.backgroundWarmupError,
    this.error,
    this.prefs,
  });

  final BootstrapStage stage;
  final String message;
  final bool safeMode;
  final bool degradedStartup;
  final bool backgroundWarmupPending;
  final Object? backgroundWarmupError;
  final Object? error;
  final SharedPreferences? prefs;

  BootstrapSnapshot copyWith({
    BootstrapStage? stage,
    String? message,
    bool? safeMode,
    bool? degradedStartup,
    bool? backgroundWarmupPending,
    Object? backgroundWarmupError = _bootstrapSentinel,
    Object? error = _bootstrapSentinel,
    Object? prefs = _prefsSentinel,
  }) {
    return BootstrapSnapshot(
      stage: stage ?? this.stage,
      message: message ?? this.message,
      safeMode: safeMode ?? this.safeMode,
      degradedStartup: degradedStartup ?? this.degradedStartup,
      backgroundWarmupPending:
          backgroundWarmupPending ?? this.backgroundWarmupPending,
      backgroundWarmupError:
          identical(backgroundWarmupError, _bootstrapSentinel)
              ? this.backgroundWarmupError
              : backgroundWarmupError,
      error: identical(error, _bootstrapSentinel) ? this.error : error,
      prefs: identical(prefs, _prefsSentinel)
          ? this.prefs
          : prefs as SharedPreferences?,
    );
  }
}

const Object _bootstrapSentinel = Object();
const Object _prefsSentinel = Object();

class BootstrapController extends ChangeNotifier {
  BootstrapController({
    Future<SharedPreferences> Function()? prefsLoader,
    StartupGuardService? startupGuardService,
    AppRunLogService? logService,
    Future<void> Function()? prewarmTask,
    this.prefsTimeout = const Duration(seconds: 2),
    this.backgroundWarmupTimeout = const Duration(seconds: 12),
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
       _startupGuardService =
           startupGuardService ?? StartupGuardService.instance,
       _logService = logService ?? AppRunLogService.instance,
       _prewarmTask = prewarmTask ?? (() => WebNovelRepository().prewarm());

  final Future<SharedPreferences> Function() _prefsLoader;
  final StartupGuardService _startupGuardService;
  final AppRunLogService _logService;
  final Future<void> Function() _prewarmTask;
  final Duration prefsTimeout;
  final Duration backgroundWarmupTimeout;

  BootstrapSnapshot _snapshot = const BootstrapSnapshot(
    stage: BootstrapStage.starting,
    message: '正在准备启动环境',
  );
  int _generation = 0;

  BootstrapSnapshot get snapshot => _snapshot;

  void _update(BootstrapSnapshot next) {
    _snapshot = next;
    notifyListeners();
  }

  Future<void> start({bool forceSafeMode = false}) async {
    final generation = ++_generation;

    _update(
      const BootstrapSnapshot(
        stage: BootstrapStage.starting,
        message: '正在准备启动环境',
      ),
    );

    _fireAndForgetLog('bootstrap:start; forceSafeMode=$forceSafeMode');

    SharedPreferences? prefs;
    var safeMode = forceSafeMode;

    try {
      prefs = await _prefsLoader().timeout(prefsTimeout);
      safeMode =
          safeMode || _startupGuardService.shouldEnterSafeMode(prefs: prefs);
      _fireAndForgetLog('bootstrap:prefs_ready; safeMode=$safeMode');
    } catch (error, stackTrace) {
      _fireAndForgetLog(
        'bootstrap:prefs_unavailable; error=$error\n$stackTrace',
        error: true,
      );
      if (!_isCurrent(generation)) {
        return;
      }
      _update(
        BootstrapSnapshot(
          stage: BootstrapStage.routingReady,
          message: '已进入应用，正在使用降级启动',
          safeMode: forceSafeMode,
          degradedStartup: true,
          backgroundWarmupPending: false,
          backgroundWarmupError: error,
        ),
      );
      return;
    }

    if (!_isCurrent(generation)) {
      return;
    }

    _update(
      BootstrapSnapshot(
        stage: BootstrapStage.routingReady,
        message: safeMode ? '安全模式启动完成' : '正在进入书架',
        safeMode: safeMode,
        degradedStartup: !safeMode,
        backgroundWarmupPending: !safeMode,
        prefs: prefs,
      ),
    );

    unawaited(_finalizeLaunch(generation, prefs));
    if (!safeMode) {
      unawaited(_runBackgroundWarmup(generation));
    }
  }

  Future<void> _finalizeLaunch(int generation, SharedPreferences prefs) async {
    try {
      await _startupGuardService.beginLaunch(prefs: prefs);
      await _startupGuardService.completeLaunch(prefs: prefs);
      _fireAndForgetLog('bootstrap:first_frame_rendered');
    } catch (error, stackTrace) {
      _fireAndForgetLog(
        'bootstrap:finalize_launch_failed; error=$error\n$stackTrace',
        error: true,
      );
      if (!_isCurrent(generation)) {
        return;
      }
      _update(
        snapshot.copyWith(degradedStartup: true, backgroundWarmupError: error),
      );
    }
  }

  Future<void> _runBackgroundWarmup(int generation) async {
    try {
      await _prewarmTask().timeout(backgroundWarmupTimeout);
      _fireAndForgetLog('bootstrap:webnovel_ready');
      if (!_isCurrent(generation)) {
        return;
      }
      _update(
        snapshot.copyWith(
          backgroundWarmupPending: false,
          degradedStartup: false,
          backgroundWarmupError: null,
        ),
      );
    } catch (error, stackTrace) {
      _fireAndForgetLog(
        'bootstrap:background_warmup_failed; error=$error\n$stackTrace',
        error: true,
      );
      if (!_isCurrent(generation)) {
        return;
      }
      _update(
        snapshot.copyWith(
          backgroundWarmupPending: false,
          degradedStartup: true,
          backgroundWarmupError: error,
        ),
      );
    }
  }

  bool _isCurrent(int generation) => generation == _generation;

  void _fireAndForgetLog(String message, {bool error = false}) {
    unawaited(
      Future<void>(() async {
        try {
          final logFuture = error
              ? _logService.logError(message)
              : _logService.logInfo(message);
          await logFuture.timeout(const Duration(seconds: 2));
        } catch (_) {}
      }),
    );
  }
}
