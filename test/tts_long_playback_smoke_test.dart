import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wenwen_tome/features/reader/providers/reader_settings_provider.dart';
import 'package:wenwen_tome/features/reader/tts_service.dart';
import 'package:wenwen_tome/features/reader/tts_session_controller.dart';

class _FakeTtsService implements TtsPlaybackService {
  @override
  TtsState ttsState = TtsState.stopped;

  @override
  Function(TtsState)? onStateChanged;

  int playedSegments = 0;

  @override
  Future<void> speak(
    String text, {
    required ReaderSettings settings,
    required Map<String, dynamic> localTtsParams,
  }) async {
    final segments = TtsService.splitTextForPlayback(
      text,
      maxSegmentChars: 120,
    );
    ttsState = TtsState.playing;
    onStateChanged?.call(ttsState);
    playedSegments = segments.length;
    ttsState = TtsState.stopped;
    onStateChanged?.call(ttsState);
  }

  @override
  Future<void> pause() async {
    ttsState = TtsState.paused;
    onStateChanged?.call(ttsState);
  }

  @override
  Future<void> resume() async {
    ttsState = TtsState.playing;
    onStateChanged?.call(ttsState);
  }

  @override
  Future<void> stop() async {
    ttsState = TtsState.stopped;
    onStateChanged?.call(ttsState);
  }

  @override
  Future<void> handleLifecycleState(AppLifecycleState state) async {}
}

void main() {
  test('TTS long playback stays stable for virtual 30 minutes', () async {
    final fakeService = _FakeTtsService();
    final container = ProviderContainer(
      overrides: [
        ttsServiceProvider.overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(ttsSessionProvider.notifier);

    final text = List.filled(
      2500,
      '这是一次 TTS 稳定性长读测试，用于覆盖长时间朗读。',
    ).join();
    final segments = TtsService.splitTextForPlayback(
      text,
      maxSegmentChars: 120,
    );
    final virtualSeconds = segments.length * 3;

    expect(virtualSeconds, greaterThanOrEqualTo(1800));

    await controller.speak(
      text,
      settings: const ReaderSettings(),
      localTtsParams: const {},
    );

    expect(fakeService.playedSegments, segments.length);
    expect(container.read(ttsSessionProvider).state, TtsState.stopped);
  });
}
