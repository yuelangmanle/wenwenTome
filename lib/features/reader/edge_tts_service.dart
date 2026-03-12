import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../core/storage/app_storage_paths.dart';

class EdgeTtsService {
  WebSocket? _webSocket;
  final Uuid _uuid = Uuid();
  bool _isConnected = false;

  final StreamController<String> _fileReadyController =
      StreamController<String>.broadcast();
  Stream<String> get onAudioFileReady => _fileReadyController.stream;

  final List<int> _audioBuffer = <int>[];
  String _currentReqId = '';

  Future<void> connect() async {
    if (_isConnected) return;
    try {
      const url =
          'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4';
      _webSocket = await WebSocket.connect(url);
      _isConnected = true;
      _webSocket!.listen(
        _onMessage,
        onError: (_) {
          _isConnected = false;
        },
        onDone: () {
          _isConnected = false;
        },
      );
    } catch (error) {
      _isConnected = false;
      throw Exception('Failed to connect to Edge TTS: $error');
    }
  }

  Future<String> synthesizeToTempFile(
    String text, {
    String voice = 'zh-CN-XiaoxiaoNeural',
  }) async {
    late final StreamSubscription<String> subscription;
    final completer = Completer<String>();
    subscription = onAudioFileReady.listen((filePath) {
      if (!completer.isCompleted) {
        completer.complete(filePath);
      }
    });

    try {
      await synthesizeToFile(text, voice: voice);
      return await completer.future.timeout(const Duration(seconds: 45));
    } finally {
      await subscription.cancel();
    }
  }

  void _onMessage(dynamic message) async {
    if (message is String) {
      if (message.contains('Path:turn.end') && _audioBuffer.isNotEmpty) {
        final tempDir = await getSafeTemporaryDirectory();
        final file = File('${tempDir.path}/edge_tts_$_currentReqId.mp3');
        await file.writeAsBytes(_audioBuffer);
        _fileReadyController.add(file.path);
        _audioBuffer.clear();
      }
      return;
    }
    if (message is! List<int>) {
      return;
    }

    // Remove the binary frame header and keep pure audio bytes.
    final data = Uint8List.fromList(message);
    if (data.length <= 2) {
      return;
    }
    final headerLength = (data[0] << 8) | data[1];
    if (data.length <= 2 + headerLength) {
      return;
    }
    final audioData = data.sublist(2 + headerLength);
    _audioBuffer.addAll(audioData);
  }

  Future<void> synthesizeToFile(
    String text, {
    String voice = 'zh-CN-XiaoxiaoNeural',
  }) async {
    if (!_isConnected) await connect();
    _audioBuffer.clear();
    _currentReqId = _uuid.v4().replaceAll('-', '');
    final timestamp = DateTime.now().toUtc().toIso8601String();

    final configMessage =
        'X-Timestamp:$timestamp\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';

    final textSanitized = text
        .replaceAll('<', '')
        .replaceAll('>', '')
        .replaceAll('&', '&amp;');
    final ssmlMessage =
        'X-RequestId:$_currentReqId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:$timestamp\r\n'
        'Path:ssml\r\n\r\n'
        '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xmlns:mstts="https://www.w3.org/2001/mstts" xml:lang="en-US">'
        '<voice name="$voice">'
        '<prosody rate="+0%">'
        '$textSanitized'
        '</prosody>'
        '</voice>'
        '</speak>';

    _webSocket?.add(configMessage);
    _webSocket?.add(ssmlMessage);
  }

  void close() {
    _webSocket?.close();
    _isConnected = false;
  }
}
