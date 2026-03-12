import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'app_run_log_service.dart';

class AppStabilityMonitor with WidgetsBindingObserver {
  AppStabilityMonitor({
    AppRunLogService? logService,
    Duration tickInterval = const Duration(milliseconds: 250),
    Duration stallThreshold = const Duration(seconds: 2),
    Duration jankThreshold = const Duration(milliseconds: 600),
    Duration minLogInterval = const Duration(seconds: 10),
  }) : _logService = logService ?? AppRunLogService.instance,
       _tickInterval = tickInterval,
       _stallThreshold = stallThreshold,
       _jankThreshold = jankThreshold,
       _minLogInterval = minLogInterval;

  final AppRunLogService _logService;
  final Duration _tickInterval;
  final Duration _stallThreshold;
  final Duration _jankThreshold;
  final Duration _minLogInterval;

  Timer? _timer;
  DateTime? _lastTickAt;
  DateTime? _lastLoggedAt;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addTimingsCallback(_onFrameTimings);

    _lastTickAt = DateTime.now();
    _timer = Timer.periodic(_tickInterval, (_) => _tick());

    unawaited(
      _logService.logEvent(
        action: 'app.start',
        result: 'ok',
        context: <String, Object?>{
          'os': Platform.operatingSystem,
          'os_version': Platform.operatingSystemVersion,
          'dart_version': Platform.version,
        },
      ),
    );
  }

  void stop() {
    if (!_started) return;
    _started = false;

    WidgetsBinding.instance.removeObserver(this);
    WidgetsBinding.instance.removeTimingsCallback(_onFrameTimings);
    _timer?.cancel();
    _timer = null;
  }

  bool _shouldLogNow() {
    final now = DateTime.now();
    final last = _lastLoggedAt;
    if (last != null && now.difference(last) < _minLogInterval) {
      return false;
    }
    _lastLoggedAt = now;
    return true;
  }

  void _tick() {
    final now = DateTime.now();
    final last = _lastTickAt;
    _lastTickAt = now;
    if (last == null) return;

    final gap = now.difference(last);
    if (gap < _stallThreshold) return;
    if (!_shouldLogNow()) return;

    unawaited(
      _logService.logEvent(
        action: 'app.loop_stall',
        result: 'detected',
        errorCode: 'E_STALL',
        durationMs: gap.inMilliseconds,
        context: <String, Object?>{
          'interval_ms': _tickInterval.inMilliseconds,
          'threshold_ms': _stallThreshold.inMilliseconds,
        },
        level: 'ERROR',
      ),
    );
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    if (!_shouldLogNow()) return;

    FrameTiming? worst;
    var worstTotal = Duration.zero;
    for (final timing in timings) {
      final total = timing.totalSpan;
      if (total > worstTotal) {
        worstTotal = total;
        worst = timing;
      }
    }

    if (worst == null) return;
    if (worstTotal < _jankThreshold) return;

    final build = worst.buildDuration;
    final raster = worst.rasterDuration;
    unawaited(
      _logService.logEvent(
        action: 'ui.jank_frame',
        result: 'detected',
        errorCode: 'E_JANK',
        durationMs: worstTotal.inMilliseconds,
        context: <String, Object?>{
          'build_ms': build.inMilliseconds,
          'raster_ms': raster.inMilliseconds,
          'total_ms': worstTotal.inMilliseconds,
        },
        level: 'ERROR',
      ),
    );
  }

  @override
  void didHaveMemoryPressure() {
    if (!_shouldLogNow()) return;
    unawaited(
      _logService.logEvent(
        action: 'app.memory_pressure',
        result: 'detected',
        errorCode: 'E_MEMORY',
        context: const <String, Object?>{'hint': 'memory_pressure'},
        level: 'ERROR',
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(
      _logService.logEvent(
        action: 'app.lifecycle',
        result: 'ok',
        context: <String, Object?>{'state': state.name},
      ),
    );
  }
}
