import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../core/storage/app_storage_paths.dart';
import 'local_tts_model_manager.dart';

class AndroidCompanionHealth {
  const AndroidCompanionHealth({
    required this.ready,
    required this.engineName,
    required this.capabilities,
    required this.baseUrl,
    required this.message,
  });

  final bool ready;
  final String engineName;
  final List<String> capabilities;
  final String baseUrl;
  final String message;

  factory AndroidCompanionHealth.fromJson(
    Map<String, dynamic> json, {
    required String baseUrl,
  }) {
    final rawCapabilities = json['capabilities'];
    return AndroidCompanionHealth(
      ready: json['ready'] as bool? ?? true,
      engineName: json['engineName'] as String? ?? 'Android 伴生服务',
      capabilities: rawCapabilities is List
          ? rawCapabilities.map((item) => item.toString()).toList()
          : const <String>[],
      baseUrl: json['baseUrl'] as String? ?? baseUrl,
      message: json['message'] as String? ?? '',
    );
  }
}

class AndroidCompanionTtsService {
  AndroidCompanionTtsService({
    http.Client? client,
    Future<Directory> Function()? tempDirProvider,
  }) : _client = client ?? http.Client(),
       _tempDirProvider = tempDirProvider ?? getSafeTemporaryDirectory;

  static const engineId = 'wenwentome.companion.loopback';
  static const engineLabel = '文文伴生服务';
  static const companionPackage = 'com.wenwentome.tts_companion';
  static const companionStartAction = 'com.wenwentome.tts_companion.START';
  static const defaultBaseUrl = 'http://127.0.0.1:18455';
  static const MethodChannel _channel = MethodChannel(
    'wenwen_tome/android_companion',
  );

  final http.Client _client;
  final Future<Directory> Function() _tempDirProvider;

  static bool isCompanionEngine(String? engine) =>
      (engine ?? '').trim() == engineId;

  static String displayEngineLabel(String engine) {
    if (!isCompanionEngine(engine)) {
      return engine;
    }
    return '$engineLabel (127.0.0.1:18455)';
  }

  Future<bool> launchCompanion() async {
    try {
      return await _channel.invokeMethod<bool>('launchCompanion') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> isInstalled() async {
    try {
      return await _channel.invokeMethod<bool>('isCompanionInstalled') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<AndroidCompanionHealth?> tryGetHealth() async {
    try {
      return await getHealth();
    } catch (_) {
      return null;
    }
  }

  Future<AndroidCompanionHealth> getHealth() async {
    final response = await _client
        .get(Uri.parse('$defaultBaseUrl/health'))
        .timeout(const Duration(seconds: 2));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('/health response must be an object');
    }
    return AndroidCompanionHealth.fromJson(decoded, baseUrl: defaultBaseUrl);
  }

  Future<AndroidCompanionHealth> ensureRunning({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final initial = await tryGetHealth();
    if (initial?.ready == true) {
      return initial!;
    }

    await launchCompanion();
    final deadline = DateTime.now().add(timeout);
    AndroidCompanionHealth? latest = initial;

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      latest = await tryGetHealth();
      if (latest?.ready == true) {
        return latest!;
      }
    }

    if (latest != null) {
      return latest;
    }

    throw Exception('未检测到 Android 伴生服务，请先安装并启动伴生 APK。');
  }

  Future<List<Map<String, String>>> getVoices({
    bool startIfNeeded = true,
  }) async {
    if (startIfNeeded) {
      final ready = await tryGetHealth();
      if (ready?.ready != true) {
        try {
          await ensureRunning();
        } catch (_) {
          return const <Map<String, String>>[];
        }
      }
    }

    final response = await _client
        .get(Uri.parse('$defaultBaseUrl/voices'))
        .timeout(const Duration(seconds: 3));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final rawVoices = decoded is List
        ? decoded
        : (decoded is Map<String, dynamic> && decoded['voices'] is List
              ? decoded['voices'] as List<dynamic>
              : const <dynamic>[]);

    final voices = <Map<String, String>>[];
    for (final item in rawVoices) {
      if (item is! Map) {
        continue;
      }
      final voice = <String, String>{};
      for (final entry in item.entries) {
        final key = entry.key?.toString();
        final value = entry.value?.toString();
        if (key == null || value == null || key.isEmpty || value.isEmpty) {
          continue;
        }
        voice[key] = value;
      }
      if (voice.isNotEmpty) {
        voices.add(voice);
      }
    }

    voices.sort((left, right) {
      final a =
          '${left['name'] ?? left['identifier'] ?? ''} ${left['locale'] ?? ''}'
              .toLowerCase();
      final b =
          '${right['name'] ?? right['identifier'] ?? ''} ${right['locale'] ?? ''}'
              .toLowerCase();
      return a.compareTo(b);
    });
    return voices;
  }

  Future<TtsModelCheckResult> checkAvailability({
    Map<String, String> voice = const <String, String>{},
  }) async {
    try {
      final health = await ensureRunning(timeout: const Duration(seconds: 3));
      if (!health.ready) {
        return TtsModelCheckResult(
          success: false,
          message: health.message.isEmpty ? '伴生服务尚未就绪。' : health.message,
        );
      }

      if (voice.isEmpty) {
        return TtsModelCheckResult(
          success: true,
          message: '伴生服务可用: ${health.engineName}',
        );
      }

      final voices = await getVoices(startIfNeeded: false);
      final exists = voices.any(
        (item) =>
            item['identifier'] == voice['identifier'] ||
            (item['name'] == voice['name'] &&
                item['locale'] == voice['locale']),
      );
      if (!exists) {
        return const TtsModelCheckResult(
          success: false,
          message: '伴生服务已启动，但未找到当前保存的声线。',
        );
      }

      final voiceName = voice['name'] ?? voice['identifier'] ?? '默认声线';
      return TtsModelCheckResult(success: true, message: '伴生服务可用: $voiceName');
    } catch (error) {
      return TtsModelCheckResult(
        success: false,
        message: '未检测到 Android 伴生服务: $error',
      );
    }
  }

  Future<String> synthesizeToFile({
    required String text,
    required Map<String, String> voice,
    required double rate,
    required double pitch,
  }) async {
    await ensureRunning(timeout: const Duration(seconds: 5));
    final response = await _client
        .post(
          Uri.parse('$defaultBaseUrl/synthesize'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{
            'text': text,
            'voice': voice,
            'rate': rate,
            'pitch': pitch,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final contentType = response.headers['content-type'] ?? '';
    if (contentType.contains('application/json')) {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('/synthesize response must be an object');
      }

      final filePath = decoded['filePath'] as String?;
      if (filePath != null && filePath.trim().isNotEmpty) {
        return filePath;
      }

      final audioBase64 = decoded['audioBase64'] as String?;
      if (audioBase64 != null && audioBase64.isNotEmpty) {
        return _persistBytes(base64Decode(audioBase64));
      }

      final rawBytes = decoded['audioBytes'];
      if (rawBytes is List) {
        final bytes = Uint8List.fromList(
          rawBytes.map((item) => (item as num).toInt()).toList(),
        );
        return _persistBytes(bytes);
      }

      throw const FormatException('/synthesize JSON response missing audio');
    }

    return _persistBytes(response.bodyBytes);
  }

  Future<String> _persistBytes(List<int> bytes) async {
    if (bytes.isEmpty) {
      throw const FileSystemException('伴生服务未返回音频数据');
    }

    final tempDir = await _tempDirProvider();
    final outDir = Directory(
      p.join(tempDir.path, 'wenwen_tome', 'companion_tts'),
    );
    await outDir.create(recursive: true);

    final file = File(
      p.join(
        outDir.path,
        'companion_${DateTime.now().microsecondsSinceEpoch}.wav',
      ),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  void dispose() {
    _client.close();
  }
}
