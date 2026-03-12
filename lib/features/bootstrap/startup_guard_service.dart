import 'package:shared_preferences/shared_preferences.dart';

class StartupGuardState {
  const StartupGuardState({
    required this.safeMode,
    required this.startedAt,
  });

  final bool safeMode;
  final DateTime startedAt;
}

class StartupGuardService {
  StartupGuardService._();

  static final StartupGuardService instance = StartupGuardService._();

  static const _unfinishedKey = 'startup_guard.unfinished';
  static const _forcedKey = 'startup_guard.forced';
  static const _startedAtKey = 'startup_guard.started_at';
  static const _completedAtKey = 'startup_guard.completed_at';

  bool shouldEnterSafeMode({
    SharedPreferences? prefs,
  }) {
    final store = prefs;
    if (store == null) {
      return false;
    }
    return (store.getBool(_unfinishedKey) ?? false) ||
        (store.getBool(_forcedKey) ?? false);
  }

  Future<StartupGuardState> beginLaunch({
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final safeMode =
        (store.getBool(_unfinishedKey) ?? false) ||
        (store.getBool(_forcedKey) ?? false);
    final now = DateTime.now();

    await store.setBool(_unfinishedKey, true);
    await store.setBool(_forcedKey, false);
    await store.setString(_startedAtKey, now.toIso8601String());

    return StartupGuardState(safeMode: safeMode, startedAt: now);
  }

  Future<void> completeLaunch({
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    await store.setBool(_unfinishedKey, false);
    await store.setBool(_forcedKey, false);
    await store.setString(_completedAtKey, DateTime.now().toIso8601String());
  }

  Future<void> forceSafeModeOnNextLaunch({
    SharedPreferences? prefs,
  }) async {
    final store = prefs ?? await SharedPreferences.getInstance();
    final now = DateTime.now();
    await store.setBool(_unfinishedKey, true);
    await store.setBool(_forcedKey, true);
    await store.setString(_startedAtKey, now.toIso8601String());
  }
}
