import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../app/runtime_platform.dart';
import '../../core/storage/app_storage_paths.dart';
import '../logging/app_run_log_service.dart';
import 'local_tts_model_manager.dart';
import 'sherpa_tts_runtime.dart';

class LocalTtsRunner {
  LocalTtsRunner({
    Uuid? uuid,
    LocalTtsModelManager? modelManager,
    SherpaTtsRuntime? sherpaRuntime,
    LocalRuntimePlatform Function()? platformResolver,
    Future<Directory> Function()? outputDirProvider,
    Future<Directory?> Function(String modelId)? sherpaModelDirResolver,
  }) : _uuid = uuid ?? const Uuid(),
       _modelManager = modelManager ?? LocalTtsModelManager(),
       _sherpaRuntime = sherpaRuntime ?? SherpaOfflineTtsRuntime(),
       _platformResolver = platformResolver ?? detectLocalRuntimePlatform,
       _outputDirProvider =
           outputDirProvider ?? getSafeApplicationSupportDirectory,
       _sherpaModelDirResolver = sherpaModelDirResolver;

  final Uuid _uuid;
  final LocalTtsModelManager _modelManager;
  final SherpaTtsRuntime _sherpaRuntime;
  final LocalRuntimePlatform Function() _platformResolver;
  final Future<Directory> Function() _outputDirProvider;
  final Future<Directory?> Function(String modelId)? _sherpaModelDirResolver;

  static List<String> buildPiperArgs({
    required String modelPath,
    required String outputPath,
    required Map<String, dynamic> params,
  }) {
    final speed = ((params['speed'] as num?) ?? 1.0).toDouble();
    final noiseScale = ((params['noiseScale'] as num?) ?? 0.67).toDouble();
    final noiseW = ((params['noiseW'] as num?) ?? 0.8).toDouble();
    final sentenceSilence = ((params['sentenceSilence'] as num?) ?? 0.2)
        .toDouble();

    return <String>[
      '-m',
      modelPath,
      '--output_file',
      outputPath,
      '--length_scale',
      (1.0 / speed).toStringAsFixed(2),
      '--noise_scale',
      noiseScale.toStringAsFixed(2),
      '--noise_w',
      noiseW.toStringAsFixed(2),
      '--sentence_silence',
      sentenceSilence.toStringAsFixed(2),
    ];
  }

  Future<String> synthesize(
    String text,
    String modelId,
    Map<String, dynamic> params,
  ) async {
    final dir = await _outputDirProvider();
    final cacheDir = Directory(p.join(dir.path, 'wenwen_tome', 'tts_cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    final outputPath = p.join(cacheDir.path, '${_uuid.v4()}.wav');
    final platform = _platformResolver();
    final model = LocalTtsModelManager.getModelById(modelId);
    if (model == null) {
      throw Exception('未知的本地 TTS 模型：$modelId');
    }
    if (!model.supportsPlatform(platform)) {
      throw Exception('当前平台暂不支持 ${model.name}');
    }

    await AppRunLogService.instance.logInfo(
      '开始本地 TTS 合成：model=$modelId; length=${text.length}; platform=$platform',
    );

    try {
      final modelDir =
          await (_sherpaModelDirResolver?.call(modelId) ??
              _modelManager.resolveSherpaModelDir(modelId));
      if (modelDir == null) {
        throw Exception('未找到可用的离线 TTS 模型文件');
      }

      await _sherpaRuntime.synthesizeToFile(
        text: text,
        outputPath: outputPath,
        manifest: model.sherpaManifest,
        modelDir: modelDir,
        params: params,
      );
      await AppRunLogService.instance.logInfo('本地 TTS 合成成功：$outputPath');
      return outputPath;
    } catch (error) {
      await AppRunLogService.instance.logError(
        '本地 TTS 合成失败：model=$modelId; $error',
      );
      rethrow;
    }
  }

  Future<void> clearCache() async {
    final dir = await _outputDirProvider();
    final cacheDir = Directory(p.join(dir.path, 'wenwen_tome', 'tts_cache'));
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  }
}
