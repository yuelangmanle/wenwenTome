import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/reader_settings_provider.dart';
import 'tts_service.dart';

final ttsSessionProvider =
    NotifierProvider<TtsSessionController, TtsSessionState>(
      TtsSessionController.new,
    );

@immutable
class TtsSessionState {
  const TtsSessionState({
    this.state = TtsState.stopped,
    this.activeText = '',
    this.startedAt,
    this.lastUpdatedAt,
  });

  final TtsState state;
  final String activeText;
  final DateTime? startedAt;
  final DateTime? lastUpdatedAt;

  bool get hasActiveText => activeText.trim().isNotEmpty;
  bool get isPlaying => state == TtsState.playing;
  bool get isPaused => state == TtsState.paused;

  TtsSessionState copyWith({
    TtsState? state,
    String? activeText,
    DateTime? startedAt,
    DateTime? lastUpdatedAt,
  }) {
    return TtsSessionState(
      state: state ?? this.state,
      activeText: activeText ?? this.activeText,
      startedAt: startedAt ?? this.startedAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
    );
  }
}

class TtsSessionController extends Notifier<TtsSessionState> {
  late final TtsPlaybackService _service;

  @override
  TtsSessionState build() {
    _service = ref.watch(ttsServiceProvider);
    _service.onStateChanged = _handleStateChanged;
    ref.onDispose(() {
      if (_service.onStateChanged == _handleStateChanged) {
        _service.onStateChanged = null;
      }
    });
    return const TtsSessionState();
  }

  void _handleStateChanged(TtsState next) {
    state = state.copyWith(state: next, lastUpdatedAt: DateTime.now());
  }

  Future<void> speak(
    String text, {
    required ReaderSettings settings,
    required Map<String, dynamic> localTtsParams,
  }) async {
    state = state.copyWith(
      activeText: text,
      startedAt: DateTime.now(),
      lastUpdatedAt: DateTime.now(),
    );
    await _service.speak(
      text,
      settings: settings,
      localTtsParams: localTtsParams,
    );
  }

  Future<void> pause() => _service.pause();

  Future<void> resume() => _service.resume();

  Future<void> stop({bool clearText = false}) async {
    await _service.stop();
    if (clearText) {
      state = state.copyWith(activeText: '', startedAt: null);
    }
  }

  Future<void> handleLifecycleState(AppLifecycleState state) =>
      _service.handleLifecycleState(state);
}
