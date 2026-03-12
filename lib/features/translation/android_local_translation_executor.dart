import 'dart:async';
import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path/path.dart' as p;

import '../../app/runtime_platform.dart';
import '../../core/storage/app_storage_paths.dart';
import '../logging/app_run_log_service.dart';
import 'local_translation_executor.dart';

class AndroidLocalTranslationExecutor implements LocalTranslationExecutor {
  AndroidLocalTranslationExecutor({
    Future<Directory> Function()? appSupportDirProvider,
    LocalRuntimePlatform Function()? platformResolver,
    this.modelFileName = 'hy-mt.gguf',
  }) : _appSupportDirProvider =
           appSupportDirProvider ?? getSafeApplicationSupportDirectory,
       _platformResolver = platformResolver ?? detectLocalRuntimePlatform;

  static const _androidContextSize = 512;

  final Future<Directory> Function() _appSupportDirProvider;
  final LocalRuntimePlatform Function() _platformResolver;
  final String modelFileName;

  LlamaController? _controller;
  String? _loadedModelPath;

  Future<String> _resolveModelPath() async {
    final dir = await _appSupportDirProvider();
    return p.join(dir.path, 'models', 'hy-mt', modelFileName);
  }

  @override
  Future<LocalTranslationCheckResult> checkAvailability() async {
    if (_platformResolver() != LocalRuntimePlatform.android) {
      return const LocalTranslationCheckResult(
        success: false,
        message: '当前平台不支持 Android 本地翻译引擎。',
      );
    }

    final modelFile = File(await _resolveModelPath());
    if (!await modelFile.exists()) {
      return const LocalTranslationCheckResult(
        success: false,
        message: '翻译模型文件不存在。',
      );
    }

    final sizeBytes = await modelFile.length();
    if (sizeBytes <= 0) {
      return const LocalTranslationCheckResult(
        success: false,
        message: '翻译模型文件为空或损坏。',
      );
    }

    final sizeGb = (sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2);
    return LocalTranslationCheckResult(
      success: true,
      message: '模型文件已就绪（$sizeGb GB），首次运行会执行预热加载。',
    );
  }

  @override
  Future<LocalTranslationCheckResult> prepare() async {
    final availability = await checkAvailability();
    if (!availability.success) {
      return availability;
    }

    final modelPath = await _resolveModelPath();
    try {
      await _ensureLoaded(modelPath);
      return const LocalTranslationCheckResult(
        success: true,
        message: 'Android 本地翻译模型预热完成，可直接运行。',
      );
    } catch (error) {
      await AppRunLogService.instance.logError('Android 本地翻译模型预热失败：$error');
      return LocalTranslationCheckResult(
        success: false,
        message: 'Android 本地翻译模型加载失败：$error',
      );
    }
  }

  @override
  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  }) async {
    final modelPath = await _resolveModelPath();
    await _ensureLoaded(modelPath);
    final controller = _controller!;

    final prompt = _buildChatMlPrompt(
      text: text,
      sourceLang: sourceLang,
      targetLang: targetLang,
    );

    final buffer = StringBuffer();
    await for (final token in controller.generate(
      prompt: prompt,
      maxTokens: _recommendedMaxTokens(text),
      temperature: 0.1,
      topP: 0.9,
      topK: 32,
      minP: 0.05,
      repeatPenalty: 1.05,
      repeatLastN: 64,
    )) {
      buffer.write(token);
    }

    final output = _sanitizeOutput(buffer.toString());
    if (output.isEmpty) {
      throw Exception('本地翻译返回空内容');
    }
    return output;
  }

  Future<void> _ensureLoaded(String modelPath) async {
    final current = _controller;
    if (current != null &&
        _loadedModelPath == modelPath &&
        await current.isModelLoaded()) {
      return;
    }

    if (current != null) {
      await current.dispose();
    }

    final controller = LlamaController();
    await AppRunLogService.instance.logInfo(
      '加载 Android 本地翻译模型：$modelPath; threads=${_recommendedThreads()}; context=$_androidContextSize',
    );
    await controller
        .loadModel(
          modelPath: modelPath,
          threads: _recommendedThreads(),
          contextSize: _androidContextSize,
        )
        .timeout(const Duration(seconds: 25));
    _controller = controller;
    _loadedModelPath = modelPath;
  }

  int _recommendedThreads() {
    final cpus = Platform.numberOfProcessors;
    if (cpus <= 8) {
      return 1;
    }
    if (cpus >= 12) {
      return 2;
    }
    return 1;
  }

  int _recommendedMaxTokens(String text) {
    final rough = (text.length * 1.6).ceil();
    if (rough < 128) {
      return 128;
    }
    if (rough > 512) {
      return 512;
    }
    return rough;
  }

  String _buildChatMlPrompt({
    required String text,
    required String sourceLang,
    required String targetLang,
  }) {
    return '<|im_start|>system\n'
        'You are a professional translation engine. Translate the user input '
        'from $sourceLang to $targetLang. Preserve markdown, paragraph breaks, '
        'names, emphasis, and punctuation. Output only the translation without '
        'explanations.\n'
        '<|im_end|>\n'
        '<|im_start|>user\n'
        '$text\n'
        '<|im_end|>\n'
        '<|im_start|>assistant\n';
  }

  String _sanitizeOutput(String raw) {
    var text = raw.trim();
    text = text.replaceAll('<|im_end|>', '');
    text = text.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '');
    return text.trim();
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    _loadedModelPath = null;
    if (controller != null) {
      await controller.dispose();
    }
  }
}
