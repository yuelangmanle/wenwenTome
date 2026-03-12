import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wenwen_tome/app/runtime_platform.dart';
import 'package:wenwen_tome/features/reader/local_tts_model_manager.dart';
import 'package:wenwen_tome/features/reader/local_tts_runner.dart';
import 'package:wenwen_tome/features/reader/providers/reader_settings_provider.dart';
import 'package:wenwen_tome/features/reader/sherpa_tts_runtime.dart';
import 'package:wenwen_tome/features/reader/tts_service.dart';

void main() {
  group('ReaderSettings local tts params', () {
    test(
      'persists per-model params and android engine fields through json',
      () {
        final settings = ReaderSettings(
          useAndroidExternalTts: true,
          androidExternalTtsEngine: 'com.example.engine',
          androidExternalTtsVoice: const {
            'name': 'Narrator',
            'locale': 'zh-CN',
          },
          activeLocalTtsId: LocalTtsModelManager.kokoroModelId,
          localTtsParamsByModel: const {
            'kokoro_zh_en': {'speed': 1.2, 'speakerId': 18},
          },
        );

        final roundTrip = ReaderSettings.fromJson(settings.toJson());

        expect(roundTrip.useAndroidExternalTts, isTrue);
        expect(roundTrip.androidExternalTtsEngine, 'com.example.engine');
        expect(roundTrip.androidExternalTtsVoice['name'], 'Narrator');
        expect(roundTrip.activeLocalTtsId, LocalTtsModelManager.kokoroModelId);
        expect(
          roundTrip.localTtsParamsByModel[LocalTtsModelManager
              .kokoroModelId]?['speed'],
          1.2,
        );
        expect(
          roundTrip.localTtsParamsByModel[LocalTtsModelManager
              .kokoroModelId]?['speakerId'],
          18,
        );
      },
    );

    test('fills missing params from model defaults', () {
      final model = LocalTtsModelManager.availableModels.firstWhere(
        (item) => item.id == LocalTtsModelManager.piperModelId,
      );

      final settings = ReaderSettings(
        localTtsParamsByModel: const {
          'piper_zh': {'speed': 1.4},
        },
      );

      final params = settings.effectiveLocalTtsParamsFor(model);

      expect(params['speed'], 1.4);
      expect(params.containsKey('noiseScale'), isTrue);
      expect(params.containsKey('noiseW'), isTrue);
      expect(params.containsKey('sentenceSilence'), isTrue);
    });
  });

  group('LocalTtsRunner.buildPiperArgs', () {
    test('converts persisted params into piper cli args', () {
      final args = LocalTtsRunner.buildPiperArgs(
        modelPath: 'voice.onnx',
        outputPath: 'out.wav',
        params: const {
          'speed': 1.25,
          'noiseScale': 0.45,
          'noiseW': 0.7,
          'sentenceSilence': 0.3,
        },
      );

      expect(args, containsAllInOrder(['-m', 'voice.onnx']));
      expect(args, containsAllInOrder(['--output_file', 'out.wav']));
      expect(args, containsAllInOrder(['--length_scale', '0.80']));
      expect(args, containsAllInOrder(['--noise_scale', '0.45']));
      expect(args, containsAllInOrder(['--noise_w', '0.70']));
      expect(args, containsAllInOrder(['--sentence_silence', '0.30']));
    });
  });

  group('LocalTtsRunner Android synthesis', () {
    test(
      'delegates to sherpa runtime on Android instead of rejecting the platform',
      () async {
        final runtime = _FakeSherpaTtsRuntime();
        final runner = LocalTtsRunner(
          platformResolver: () => LocalRuntimePlatform.android,
          sherpaModelDirResolver: (_) async =>
              Directory(p.join('tmp', 'tts-model')),
          sherpaRuntime: runtime,
          outputDirProvider: () async => Directory.systemTemp,
        );

        final output = await runner.synthesize(
          '你好，世界',
          LocalTtsModelManager.piperModelId,
          const {'speed': 1.0},
        );

        expect(runtime.callCount, 1);
        expect(runtime.lastText, '你好，世界');
        expect(runtime.lastManifest?.directoryName, isNotEmpty);
        expect(output.endsWith('.wav'), isTrue);
      },
    );

    test('tts service treats Android as a supported local runtime', () {
      expect(
        TtsService.supportsLocalTtsPlatform(LocalRuntimePlatform.android),
        isTrue,
      );
      expect(
        TtsService.supportsLocalTtsPlatform(LocalRuntimePlatform.windows),
        isTrue,
      );
      expect(
        TtsService.supportsLocalTtsPlatform(LocalRuntimePlatform.other),
        isFalse,
      );
    });
  });
}

class _FakeSherpaTtsRuntime implements SherpaTtsRuntime {
  int callCount = 0;
  String? lastText;
  SherpaTtsModelManifest? lastManifest;

  @override
  Future<void> synthesizeToFile({
    required String text,
    required String outputPath,
    required SherpaTtsModelManifest manifest,
    required Directory modelDir,
    required Map<String, dynamic> params,
  }) async {
    callCount++;
    lastText = text;
    lastManifest = manifest;
    await File(outputPath).create(recursive: true);
  }
}
