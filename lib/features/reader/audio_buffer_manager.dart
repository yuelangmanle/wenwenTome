import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class AudioBufferManager {
  final AudioPlayer _player = AudioPlayer();
  final List<String> _chunkQueue = [];
  bool _isPlayingSequence = false;

  /// 按标点切分传入的超长文本，每端交给合成引擎
  List<String> chunkText(String rawText, {int maxLen = 200}) {
    // 简易句子分割逻辑，可拓展
    final sentences = rawText.split(RegExp(r'(?<=[。？！；\n])'));
    return sentences.where((s) => s.trim().isNotEmpty).toList();
  }

  /// 后台预合成流水线
  Future<void> preSynthesizeChapter(String fullText, Future<String> Function(String) synthesizeFunc) async {
    final chunks = chunkText(fullText);
    for (final chunk in chunks) {
      // 在这调用大模型推理（如 ChatTTS，MegaTTS）产出 WAV 写入磁盘
      final wavPath = await synthesizeFunc(chunk);
      _chunkQueue.add(wavPath);
    }
  }

  /// 取出缓冲执行无缝播放
  Future<void> playBufferedSequence() async {
    if (_isPlayingSequence || _chunkQueue.isEmpty) return;
    _isPlayingSequence = true;

    _player.onPlayerComplete.listen((_) async {
      _chunkQueue.removeAt(0); // 播完一个删一个
      if (_chunkQueue.isNotEmpty) {
        await _player.play(DeviceFileSource(_chunkQueue.first));
      } else {
        _isPlayingSequence = false;
      }
    });

    await _player.play(DeviceFileSource(_chunkQueue.first));
  }

  Future<void> stop() async {
    _chunkQueue.clear();
    _isPlayingSequence = false;
    await _player.stop();
  }
}
