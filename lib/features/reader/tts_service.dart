import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../app/runtime_platform.dart';
import '../logging/app_run_log_service.dart';
import 'android_companion_tts_service.dart';
import 'edge_tts_service.dart';
import 'local_tts_model_manager.dart';
import 'local_tts_runner.dart';
import 'providers/reader_settings_provider.dart';

final ttsServiceProvider = Provider<TtsPlaybackService>((ref) => TtsService());

enum TtsState { playing, stopped, paused }

abstract class TtsPlaybackService {
  TtsState get ttsState;
  Function(TtsState)? get onStateChanged;
  set onStateChanged(Function(TtsState)? callback);

  Future<void> speak(
    String text, {
    required ReaderSettings settings,
    required Map<String, dynamic> localTtsParams,
  });
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> handleLifecycleState(AppLifecycleState state);
}

class TtsService implements TtsPlaybackService {
  static Future<void> _globalLocalSynthesisQueue = Future<void>.value();
  static const int _defaultSegmentChars = 420;

  static bool supportsLocalTtsPlatform(LocalRuntimePlatform platform) =>
      platform == LocalRuntimePlatform.windows ||
      platform == LocalRuntimePlatform.android;

  final FlutterTts _flutterTts;
  final EdgeTtsService _edgeTts;
  final AudioPlayer _audioPlayer;
  final LocalTtsRunner _localTts;
  final LocalTtsModelManager _localTtsModelManager;
  final AndroidCompanionTtsService _androidCompanionTts;

  Future<void> _speakQueue = Future<void>.value();
  Completer<void>? _segmentPlaybackCompleter;
  int _playbackToken = 0;
  int _speakRequestId = 0;

  String _lastSpokenText = '';
  ReaderSettings? _lastSettings;
  Map<String, dynamic> _lastLocalTtsParams = const <String, dynamic>{};
  List<String> _activeSegments = const <String>[];
  int _activeSegmentIndex = 0;
  bool _resumeOnForeground = false;

  @override
  TtsState ttsState = TtsState.stopped;
  Function()? onComplete;
  @override
  Function(TtsState)? onStateChanged;

  TtsService({
    FlutterTts? flutterTts,
    EdgeTtsService? edgeTts,
    AudioPlayer? audioPlayer,
    LocalTtsRunner? localTts,
    LocalTtsModelManager? localTtsModelManager,
    AndroidCompanionTtsService? androidCompanionTts,
  }) : _flutterTts = flutterTts ?? FlutterTts(),
       _edgeTts = edgeTts ?? EdgeTtsService(),
       _audioPlayer = audioPlayer ?? AudioPlayer(),
       _localTts = localTts ?? LocalTtsRunner(),
       _localTtsModelManager = localTtsModelManager ?? LocalTtsModelManager(),
       _androidCompanionTts =
           androidCompanionTts ?? AndroidCompanionTtsService() {
    _initTts();
  }

  static List<String> splitTextForPlayback(
    String text, {
    int maxSegmentChars = _defaultSegmentChars,
  }) {
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) {
      return const <String>[];
    }

    final sentencePattern = RegExp(
      r'(?<=[.!?;:,\n\u3002\uff01\uff1f\uff1b\uff0c])',
    );
    final sentences = normalized
        .split(sentencePattern)
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (sentences.isEmpty) {
      return const <String>[];
    }

    final segments = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) {
        segments.add(value);
      }
      buffer.clear();
    }

    for (final sentence in sentences) {
      if (sentence.length > maxSegmentChars) {
        flush();
        var start = 0;
        while (start < sentence.length) {
          final end = (start + maxSegmentChars).clamp(0, sentence.length);
          final part = sentence.substring(start, end).trim();
          if (part.isNotEmpty) {
            segments.add(part);
          }
          start = end;
        }
        continue;
      }

      final candidateLength =
          buffer.length + (buffer.isEmpty ? 0 : 1) + sentence.length;
      if (candidateLength > maxSegmentChars) {
        flush();
      }
      if (buffer.isNotEmpty) {
        buffer.write('\n');
      }
      buffer.write(sentence);
    }

    flush();
    return segments;
  }

  void _initTts() {
    _flutterTts.setStartHandler(() {
      _setState(TtsState.playing, force: true);
    });

    _flutterTts.setCompletionHandler(() {
      _setState(TtsState.stopped, force: true);
      _completeSegmentPlayback();
    });

    _flutterTts.setCancelHandler(() {
      _setState(TtsState.stopped, force: true);
      _completeSegmentPlayback();
    });

    _flutterTts.setPauseHandler(() {
      _setState(TtsState.paused, force: true);
    });

    _flutterTts.setContinueHandler(() {
      _setState(TtsState.playing, force: true);
    });

    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing) {
        _setState(TtsState.playing, force: true);
      } else if (state == PlayerState.paused) {
        _setState(TtsState.paused, force: true);
      } else if (state == PlayerState.stopped ||
          state == PlayerState.completed) {
        _setState(TtsState.stopped, force: true);
        _completeSegmentPlayback();
      }
    });
  }

  void _setState(TtsState next, {bool force = false}) {
    if (!force && ttsState == next) {
      return;
    }
    ttsState = next;
    onStateChanged?.call(ttsState);
  }

  @override
  Future<void> speak(
    String text, {
    required ReaderSettings settings,
    required Map<String, dynamic> localTtsParams,
  }) {
    final segments = splitTextForPlayback(text);
    if (segments.isEmpty) {
      return Future<void>.value();
    }

    _lastSpokenText = text;
    _lastSettings = settings;
    _lastLocalTtsParams = Map<String, dynamic>.from(localTtsParams);
    _resumeOnForeground = false;

    final requestId = ++_speakRequestId;
    _playbackToken++;
    _completeSegmentPlayback();

    final queued = _speakQueue.then((_) async {
      if (requestId != _speakRequestId) {
        return;
      }
      await _hardStop(incrementToken: false, notify: false);
      if (requestId != _speakRequestId) {
        return;
      }
      await _speakSegments(
        segments,
        settings: settings,
        localTtsParams: localTtsParams,
      );
    });
    _speakQueue = queued.catchError((_) {});
    return queued;
  }

  Future<void> _speakSegments(
    List<String> segments, {
    required ReaderSettings settings,
    required Map<String, dynamic> localTtsParams,
  }) async {
    final token = ++_playbackToken;
    _activeSegments = List<String>.unmodifiable(segments);
    _activeSegmentIndex = 0;

    try {
      String? preparedLocalPath;
      for (var index = 0; index < segments.length; index++) {
        if (token != _playbackToken) {
          return;
        }

        _activeSegmentIndex = index;
        Future<String?>? nextPrefetch;
        if (settings.useLocalTts && index + 1 < segments.length) {
          nextPrefetch = _prefetchLocalSegment(
            segments[index + 1],
            modelId: settings.activeLocalTtsId,
            params: localTtsParams,
          );
        }

        await _playSingleSegmentAndWait(
          segments[index],
          settings: settings,
          localTtsParams: localTtsParams,
          token: token,
          preparedLocalPath: preparedLocalPath,
        );

        if (token != _playbackToken) {
          return;
        }
        preparedLocalPath = nextPrefetch == null ? null : await nextPrefetch;
      }

      if (token == _playbackToken) {
        _setState(TtsState.stopped, force: true);
        onComplete?.call();
      }
    } finally {
      if (token == _playbackToken) {
        _activeSegments = const <String>[];
        _activeSegmentIndex = 0;
      }
    }
  }

  Future<String?> _prefetchLocalSegment(
    String text, {
    required String modelId,
    required Map<String, dynamic> params,
  }) async {
    try {
      return await _runLocalSynthesisLocked(
        text,
        modelId,
        params,
      ).timeout(const Duration(seconds: 45));
    } catch (error) {
      await AppRunLogService.instance.logError(
        'local tts prefetch failed: $error',
      );
      return null;
    }
  }

  Future<void> _playSingleSegmentAndWait(
    String text, {
    required ReaderSettings settings,
    required Map<String, dynamic> localTtsParams,
    required int token,
    String? preparedLocalPath,
  }) async {
    if (token != _playbackToken) {
      return;
    }
    _segmentPlaybackCompleter = Completer<void>();

    await _startSingleSegmentPlayback(
      text,
      settings: settings,
      localTtsParams: localTtsParams,
      token: token,
      preparedLocalPath: preparedLocalPath,
    );

    final completer = _segmentPlaybackCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    await completer.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () {
        throw TimeoutException('tts segment playback timeout');
      },
    );
  }

  Future<void> _startSingleSegmentPlayback(
    String text, {
    required ReaderSettings settings,
    required Map<String, dynamic> localTtsParams,
    required int token,
    String? preparedLocalPath,
  }) async {
    if (text.trim().isEmpty || token != _playbackToken) {
      _completeSegmentPlayback();
      return;
    }

    if (settings.useLocalTts) {
      await _playLocalSegment(
        text,
        settings: settings,
        localTtsParams: localTtsParams,
        token: token,
        preparedLocalPath: preparedLocalPath,
      );
      return;
    }

    if (settings.useAndroidExternalTts) {
      await _playAndroidExternalSegment(text, settings: settings, token: token);
      return;
    }

    if (settings.useEdgeTts) {
      await _playEdgeSegment(text, settings: settings, token: token);
      return;
    }

    await _speakWithSystemTts(
      text,
      rate: settings.ttsRate,
      pitch: settings.ttsPitch,
    );
  }

  Future<void> _playLocalSegment(
    String text, {
    required ReaderSettings settings,
    required Map<String, dynamic> localTtsParams,
    required int token,
    String? preparedLocalPath,
  }) async {
    final platform = detectLocalRuntimePlatform();
    if (!supportsLocalTtsPlatform(platform)) {
      await AppRunLogService.instance.logInfo(
        'local tts unsupported on current platform, fallback to system tts',
      );
      await _speakWithSystemTts(
        text,
        rate: settings.ttsRate,
        pitch: settings.ttsPitch,
      );
      return;
    }

    final availability = await _localTtsModelManager.checkAvailability(
      settings.activeLocalTtsId,
    );
    if (!availability.success) {
      await AppRunLogService.instance.logInfo(
        'local tts model unavailable, fallback to system tts: ${availability.message}',
      );
      await _speakWithSystemTts(
        text,
        rate: settings.ttsRate,
        pitch: settings.ttsPitch,
      );
      return;
    }

    try {
      _setState(TtsState.playing, force: true);
      final filePath =
          preparedLocalPath ??
          await _runLocalSynthesisLocked(
            text,
            settings.activeLocalTtsId,
            localTtsParams,
          ).timeout(const Duration(seconds: 45));
      if (token != _playbackToken) {
        _completeSegmentPlayback();
        return;
      }
      await _audioPlayer.setPlaybackRate(1.0);
      await _audioPlayer.play(DeviceFileSource(filePath));
    } catch (error) {
      await AppRunLogService.instance.logError(
        'local tts segment playback failed, fallback to system tts: $error',
      );
      _setState(TtsState.stopped, force: true);
      await _speakWithSystemTts(
        text,
        rate: settings.ttsRate,
        pitch: settings.ttsPitch,
      );
    }
  }

  Future<void> _playAndroidExternalSegment(
    String text, {
    required ReaderSettings settings,
    required int token,
  }) async {
    final platform = detectLocalRuntimePlatform();
    if (platform == LocalRuntimePlatform.android &&
        AndroidCompanionTtsService.isCompanionEngine(
          settings.androidExternalTtsEngine,
        )) {
      try {
        _setState(TtsState.playing, force: true);
        final filePath = await _androidCompanionTts.synthesizeToFile(
          text: text,
          voice: settings.androidExternalTtsVoice,
          rate: settings.ttsRate,
          pitch: settings.ttsPitch,
        );
        if (token != _playbackToken) {
          _completeSegmentPlayback();
          return;
        }
        await _audioPlayer.setPlaybackRate(1.0);
        await _audioPlayer.play(DeviceFileSource(filePath));
        return;
      } catch (error) {
        await AppRunLogService.instance.logError(
          'android companion tts failed, fallback to system tts: $error',
        );
      }
    }

    if (platform == LocalRuntimePlatform.android) {
      try {
        if (settings.androidExternalTtsEngine.trim().isNotEmpty) {
          await _flutterTts.setEngine(settings.androidExternalTtsEngine);
        }
        if (settings.androidExternalTtsVoice.isNotEmpty) {
          await _flutterTts.setVoice(settings.androidExternalTtsVoice);
        }
      } catch (error) {
        await AppRunLogService.instance.logError(
          'android external tts setup failed, fallback to system tts: $error',
        );
      }
    }

    await _speakWithSystemTts(
      text,
      rate: settings.ttsRate,
      pitch: settings.ttsPitch,
    );
  }

  Future<void> _playEdgeSegment(
    String text, {
    required ReaderSettings settings,
    required int token,
  }) async {
    try {
      _setState(TtsState.playing, force: true);
      final filePath = await _edgeTts
          .synthesizeToTempFile(text, voice: settings.edgeTtsVoice)
          .timeout(const Duration(seconds: 50));
      if (token != _playbackToken) {
        _completeSegmentPlayback();
        return;
      }
      await _audioPlayer.setPlaybackRate(settings.ttsRate.clamp(0.5, 2.0));
      await _audioPlayer.play(DeviceFileSource(filePath));
    } catch (error) {
      await AppRunLogService.instance.logError(
        'edge tts segment playback failed, fallback to system tts: $error',
      );
      _setState(TtsState.stopped, force: true);
      await _speakWithSystemTts(
        text,
        rate: settings.ttsRate,
        pitch: settings.ttsPitch,
      );
    }
  }

  Future<void> _speakWithSystemTts(
    String text, {
    required double rate,
    required double pitch,
  }) async {
    _setState(TtsState.playing, force: true);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setSpeechRate(rate.clamp(0.1, 1.5));
    await _flutterTts.setPitch(pitch.clamp(0.5, 2.0));
    await _flutterTts.setSharedInstance(true);
    await _flutterTts
        .setIosAudioCategory(IosTextToSpeechAudioCategory.playback, [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ]);
    await _flutterTts.speak(text);
  }

  Future<String> _runLocalSynthesisLocked(
    String text,
    String modelId,
    Map<String, dynamic> params,
  ) {
    final task = _globalLocalSynthesisQueue.then<String>((_) {
      return _localTts.synthesize(text, modelId, params);
    });
    _globalLocalSynthesisQueue = task.then<void>((_) {}).catchError((_) {});
    return task;
  }

  @override
  Future<void> handleLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (ttsState == TtsState.playing) {
        _resumeOnForeground = true;
        await pause();
      }
      return;
    }
    if (state != AppLifecycleState.resumed || !_resumeOnForeground) {
      return;
    }

    _resumeOnForeground = false;
    await resume();
  }

  String _remainingTextForResume() {
    if (_activeSegments.isEmpty) {
      return _lastSpokenText;
    }
    final safeIndex = _activeSegmentIndex.clamp(0, _activeSegments.length - 1);
    return _activeSegments.sublist(safeIndex).join('\n').trim();
  }

  Future<void> _hardStop({
    bool incrementToken = true,
    bool notify = true,
  }) async {
    if (incrementToken) {
      _playbackToken++;
    }
    _completeSegmentPlayback();
    await _flutterTts.stop();
    await _audioPlayer.stop();
    if (notify) {
      _setState(TtsState.stopped, force: true);
    }
  }

  void _completeSegmentPlayback() {
    final completer = _segmentPlaybackCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  @override
  Future<void> stop() async {
    _resumeOnForeground = false;
    _speakRequestId++;
    _activeSegments = const <String>[];
    _activeSegmentIndex = 0;
    await _hardStop();
  }

  @override
  Future<void> pause() async {
    if (ttsState != TtsState.playing) {
      return;
    }
    final remaining = _remainingTextForResume();
    if (remaining.isNotEmpty) {
      _lastSpokenText = remaining;
    }
    _speakRequestId++;
    await _hardStop(notify: false);
    _setState(TtsState.paused, force: true);
  }

  @override
  Future<void> resume() async {
    final settings = _lastSettings;
    if (settings == null || _lastSpokenText.trim().isEmpty) {
      return;
    }
    await speak(
      _lastSpokenText,
      settings: settings,
      localTtsParams: _lastLocalTtsParams,
    );
  }
}
