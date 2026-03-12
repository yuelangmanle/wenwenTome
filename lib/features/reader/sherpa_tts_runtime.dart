import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'local_tts_model_manager.dart';

abstract class SherpaTtsRuntime {
  Future<void> synthesizeToFile({
    required String text,
    required String outputPath,
    required SherpaTtsModelManifest manifest,
    required Directory modelDir,
    required Map<String, dynamic> params,
  });
}

class SherpaOfflineTtsRuntime implements SherpaTtsRuntime {
  SherpaOfflineTtsRuntime() {
    sherpa.initBindings();
  }

  @override
  Future<void> synthesizeToFile({
    required String text,
    required String outputPath,
    required SherpaTtsModelManifest manifest,
    required Directory modelDir,
    required Map<String, dynamic> params,
  }) async {
    final speed = ((params['speed'] as num?) ?? 1.0).toDouble();
    final sentenceSilence = ((params['sentenceSilence'] as num?) ?? 0.2)
        .toDouble();
    final rawSpeakerId =
        ((params['speakerId'] as num?) ?? manifest.defaultSpeakerId).round();
    final speakerId = rawSpeakerId.clamp(0, manifest.maxSpeakerId).toInt();

    final config = sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        numThreads: _threadCount(),
        debug: false,
        provider: 'cpu',
        vits: manifest.kind == SherpaTtsModelKind.vits
            ? sherpa.OfflineTtsVitsModelConfig(
                model: p.join(modelDir.path, manifest.modelFileName),
                lexicon: manifest.lexiconFileNames.isEmpty
                    ? ''
                    : p.join(modelDir.path, manifest.lexiconFileNames.first),
                tokens: p.join(modelDir.path, manifest.tokensFileName),
                dataDir: manifest.dataDirName == null
                    ? ''
                    : p.join(modelDir.path, manifest.dataDirName!),
                noiseScale: ((params['noiseScale'] as num?) ?? 0.67).toDouble(),
                noiseScaleW: ((params['noiseW'] as num?) ?? 0.8).toDouble(),
                lengthScale: 1.0,
              )
            : const sherpa.OfflineTtsVitsModelConfig(),
        kokoro: manifest.kind == SherpaTtsModelKind.kokoro
            ? sherpa.OfflineTtsKokoroModelConfig(
                model: p.join(modelDir.path, manifest.modelFileName),
                voices: p.join(modelDir.path, manifest.voicesFileName!),
                tokens: p.join(modelDir.path, manifest.tokensFileName),
                dataDir: manifest.dataDirName == null
                    ? ''
                    : p.join(modelDir.path, manifest.dataDirName!),
                lexicon: manifest.lexiconFileNames
                    .map((item) => p.join(modelDir.path, item))
                    .join(','),
                lang: manifest.languageCode,
                lengthScale: 1.0,
              )
            : const sherpa.OfflineTtsKokoroModelConfig(),
      ),
      ruleFsts: manifest.ruleFstFiles
          .map((item) => p.join(modelDir.path, item))
          .join(','),
      silenceScale: sentenceSilence,
    );

    final tts = sherpa.OfflineTts(config);
    try {
      final generated = tts.generateWithConfig(
        text: text,
        config: sherpa.OfflineTtsGenerationConfig(
          speed: speed,
          silenceScale: sentenceSilence,
          sid: speakerId,
        ),
      );
      final ok = sherpa.writeWave(
        filename: outputPath,
        samples: generated.samples,
        sampleRate: generated.sampleRate,
      );
      if (!ok) {
        throw Exception('写入 WAV 失败');
      }
    } finally {
      tts.free();
    }
  }

  int _threadCount() {
    final cpuCount = Platform.numberOfProcessors;
    if (cpuCount <= 2) {
      return 2;
    }
    if (cpuCount >= 6) {
      return 4;
    }
    return cpuCount;
  }
}
