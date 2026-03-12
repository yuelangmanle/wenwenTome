import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

import 'android_companion_tts_service.dart';
import 'local_tts_model_manager.dart';

class AndroidTtsEngineService {
  AndroidTtsEngineService({
    FlutterTts? flutterTts,
    AndroidCompanionTtsService? companionService,
  }) : _flutterTts = flutterTts ?? FlutterTts(),
       _companionService = companionService ?? AndroidCompanionTtsService();

  final FlutterTts _flutterTts;
  final AndroidCompanionTtsService _companionService;

  static bool isCompanionEngine(String engine) =>
      AndroidCompanionTtsService.isCompanionEngine(engine);

  static String displayEngineLabel(String engine) =>
      AndroidCompanionTtsService.displayEngineLabel(engine);

  Future<List<String>> getEngines() async {
    if (!Platform.isAndroid) {
      return const <String>[];
    }

    final engines = await _flutterTts.getEngines;
    if (engines is! List) {
      return const <String>[];
    }

    final normalized = engines
        .whereType<String>()
        .where((engine) => engine.trim().isNotEmpty)
        .toSet()
        .toList();
    normalized.add(AndroidCompanionTtsService.engineId);
    normalized.sort((left, right) {
      if (isCompanionEngine(left) && !isCompanionEngine(right)) {
        return -1;
      }
      if (!isCompanionEngine(left) && isCompanionEngine(right)) {
        return 1;
      }
      return left.compareTo(right);
    });
    return normalized;
  }

  Future<String?> getDefaultEngine() async {
    if (!Platform.isAndroid) {
      return null;
    }

    final engine = await _flutterTts.getDefaultEngine;
    return engine is String && engine.trim().isNotEmpty ? engine : null;
  }

  Future<List<Map<String, String>>> getVoices({String? engine}) async {
    if (!Platform.isAndroid) {
      return const <Map<String, String>>[];
    }

    if (engine != null && isCompanionEngine(engine)) {
      return _companionService.getVoices();
    }

    if (engine != null && engine.trim().isNotEmpty) {
      await _flutterTts.setEngine(engine);
    }

    final voices = await _flutterTts.getVoices;
    if (voices is! List) {
      return const <Map<String, String>>[];
    }

    final normalized = <Map<String, String>>[];
    for (final item in voices) {
      if (item is! Map) {
        continue;
      }
      final mapped = <String, String>{};
      for (final entry in item.entries) {
        final key = entry.key?.toString();
        final value = entry.value?.toString();
        if (key == null || value == null || key.isEmpty || value.isEmpty) {
          continue;
        }
        mapped[key] = value;
      }
      if (mapped.isNotEmpty) {
        normalized.add(mapped);
      }
    }

    normalized.sort((a, b) {
      final left = '${a['name'] ?? ''} ${a['locale'] ?? ''}'.toLowerCase();
      final right = '${b['name'] ?? ''} ${b['locale'] ?? ''}'.toLowerCase();
      return left.compareTo(right);
    });
    return normalized;
  }

  Future<TtsModelCheckResult> checkAvailability({
    required String engine,
    Map<String, String> voice = const <String, String>{},
  }) async {
    if (!Platform.isAndroid) {
      return const TtsModelCheckResult(
        success: false,
        message: '当前平台不支持 Android 伴生引擎。',
      );
    }

    if (engine.trim().isEmpty) {
      return const TtsModelCheckResult(
        success: false,
        message: '尚未选择 Android 伴生 TTS 引擎。',
      );
    }

    if (isCompanionEngine(engine)) {
      return _companionService.checkAvailability(voice: voice);
    }

    final engines = await getEngines();
    if (!engines.contains(engine)) {
      return TtsModelCheckResult(success: false, message: '未检测到引擎：$engine');
    }

    if (voice.isEmpty) {
      return TtsModelCheckResult(success: true, message: '已检测到伴生引擎：$engine');
    }

    final voices = await getVoices(engine: engine);
    final exists = voices.any((item) => _sameVoice(item, voice));
    if (!exists) {
      return TtsModelCheckResult(success: false, message: '引擎已安装，但未找到已保存的声线。');
    }

    final voiceName = voice['name'] ?? voice['identifier'] ?? '默认声线';
    return TtsModelCheckResult(
      success: true,
      message: '伴生引擎可用：$engine / $voiceName',
    );
  }

  static bool sameVoice(Map<String, String> left, Map<String, String> right) =>
      _sameVoice(left, right);

  static bool _sameVoice(Map<String, String> left, Map<String, String> right) {
    if (left.isEmpty || right.isEmpty) {
      return false;
    }

    final identifierMatches =
        left['identifier'] != null && left['identifier'] == right['identifier'];
    if (identifierMatches) {
      return true;
    }

    return left['name'] == right['name'] && left['locale'] == right['locale'];
  }
}
