import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'features/bootstrap/app_bootstrap_screen.dart';
import 'features/bootstrap/bootstrap_controller.dart';
import 'features/logging/app_run_log_service.dart';
import 'features/logging/app_stability_monitor.dart';
import 'features/settings/providers/global_settings_provider.dart';

final AppStabilityMonitor _stabilityMonitor = AppStabilityMonitor();

void _installGlobalErrorLogging() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    unawaited(
      AppRunLogService.instance.logEvent(
        action: 'crash.flutter_error',
        result: 'error',
        errorCode: 'E_FLUTTER_ERROR',
        message: details.exceptionAsString(),
        error: details.exception,
        stackTrace: details.stack,
        level: 'ERROR',
      ),
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    unawaited(
      AppRunLogService.instance.logEvent(
        action: 'crash.platform_dispatcher',
        result: 'error',
        errorCode: 'E_PLATFORM_ERROR',
        error: error,
        stackTrace: stack,
        level: 'ERROR',
      ),
    );
    return false;
  };

  final port = ReceivePort();
  Isolate.current.addErrorListener(port.sendPort);
  port.listen((dynamic message) {
    Object? error;
    StackTrace? stack;
    if (message is List && message.length >= 2) {
      error = message[0];
      final rawStack = message[1];
      stack = rawStack is StackTrace ? rawStack : StackTrace.fromString('$rawStack');
    } else {
      error = message;
    }
    unawaited(
      AppRunLogService.instance.logEvent(
        action: 'crash.isolate',
        result: 'error',
        errorCode: 'E_ISOLATE_ERROR',
        error: error,
        stackTrace: stack,
        level: 'ERROR',
      ),
    );
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorLogging();
  _stabilityMonitor.start();
  runZonedGuarded(
    () => runApp(const BootstrapApp()),
    (error, stack) {
      unawaited(
        AppRunLogService.instance.logEvent(
          action: 'crash.zone',
          result: 'error',
          errorCode: 'E_ZONE_ERROR',
          error: error,
          stackTrace: stack,
          level: 'ERROR',
        ),
      );
    },
  );
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  final BootstrapController _controller = BootstrapController();
  bool _forceSafeMode = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    unawaited(_controller.start(forceSafeMode: _forceSafeMode));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;
        if (snapshot.stage == BootstrapStage.routingReady) {
          final prefs = snapshot.prefs;
          return ProviderScope(
            overrides: prefs == null
                ? const []
                : [sharedPreferencesProvider.overrideWithValue(prefs)],
            child: const MyApp(),
          );
        }

        return MaterialApp(
          title: '文文Tome',
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.system,
          home: AppBootstrapScreen(
            controller: _controller,
            onRetry: () {
              _forceSafeMode = false;
              _start();
            },
            onEnterSafeMode: () {
              _forceSafeMode = true;
              _start();
            },
          ),
        );
      },
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '文文Tome',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
    );
  }
}
