import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../settings/providers/global_settings_provider.dart';
import '../translation_service.dart';
import '../translation_db_service.dart';

enum ChapterTranslationStatus { none, pending, translating, completed, failed }

class ChapterTranslationState {
  final String id;
  final String bookId;
  final String chapterId;
  final ChapterTranslationStatus status;
  final double progress;
  final String? translatedText;
  final String? errorMsg;

  ChapterTranslationState({
    required this.id,
    required this.bookId,
    required this.chapterId,
    this.status = ChapterTranslationStatus.none,
    this.progress = 0.0,
    this.translatedText,
    this.errorMsg,
  });

  ChapterTranslationState copyWith({
    ChapterTranslationStatus? status,
    double? progress,
    String? translatedText,
    String? errorMsg,
  }) {
    return ChapterTranslationState(
      id: id,
      bookId: bookId,
      chapterId: chapterId,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      translatedText: translatedText ?? this.translatedText,
      errorMsg: errorMsg ?? this.errorMsg,
    );
  }
}

class ChapterTranslationManager extends Notifier<Map<String, ChapterTranslationState>> {
  final TranslationDbService _db = TranslationDbService();
  final TranslationService _translator = TranslationService();
  final _uuid = const Uuid();

  // 任务队列调度
  final List<ChapterTranslationState> _queue = [];
  bool _isProcessing = false;

  @override
  Map<String, ChapterTranslationState> build() {
    return {};
  }

  /// 初始化某本书的翻译状态
  Future<void> loadBookTranslations(String bookId) async {
    final records = await _db.getTranslationsByBook(bookId);
    final newState = <String, ChapterTranslationState>{...state};
    
    for (final row in records) {
      final statusStr = row['status'] as String;
      final status = ChapterTranslationStatus.values.firstWhere(
        (e) => e.name == statusStr, 
        orElse: () => ChapterTranslationStatus.none
      );
      
      newState['${row['book_id']}_${row['chapter_id']}'] = ChapterTranslationState(
        id: row['id'],
        bookId: row['book_id'],
        chapterId: row['chapter_id'],
        status: status,
        progress: row['progress'] ?? 0.0,
        translatedText: row['translated_text'],
        errorMsg: row['error_msg'],
      );
    }
    
    state = newState;
  }

  /// 批量请求翻译章节
  Future<void> requestTranslation(String bookId, List<String> chapterIds, List<String> originalTexts) async {
    for (int i = 0; i < chapterIds.length; i++) {
      final chapterId = chapterIds[i];
      final key = '${bookId}_$chapterId';
      
      // 避免重复排队（除非是失败重试）
      if (state.containsKey(key) && 
         (state[key]!.status == ChapterTranslationStatus.translating || 
          state[key]!.status == ChapterTranslationStatus.pending || 
          state[key]!.status == ChapterTranslationStatus.completed)) {
        continue;
      }

      final id = _uuid.v4();
      final newState = ChapterTranslationState(
        id: id,
        bookId: bookId,
        chapterId: chapterId,
        status: ChapterTranslationStatus.pending,
      );
      
      // 按 pending 存入库
      await _db.saveTranslation(
        id: id,
        bookId: bookId,
        chapterId: chapterId,
        status: ChapterTranslationStatus.pending.name,
        originalText: originalTexts.isNotEmpty ? originalTexts[i] : null,
      );

      final updatedState = <String, ChapterTranslationState>{...state};
      updatedState[key] = newState;
      state = updatedState;
      _queue.add(newState);
    }
    
    _processQueue();
  }

  /// 后台队列消费
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final task = _queue.removeAt(0);
      final key = '${task.bookId}_${task.chapterId}';
      
      // 获取最新鲜的 config
      final globalState = ref.read(globalSettingsProvider);
      final configs = globalState.translationConfigs;
      final config = configs.isEmpty
          ? null
          : configs.firstWhere(
              (c) => c.id == globalState.translationConfigId,
              orElse: () => configs.first,
            );

      try {
        // 更新 UI 为 translating
        final stMap = <String, ChapterTranslationState>{...state};
        stMap[key] = task.copyWith(status: ChapterTranslationStatus.translating);
        state = stMap;

        await _db.saveTranslation(
          id: task.id, bookId: task.bookId, chapterId: task.chapterId, 
          status: ChapterTranslationStatus.translating.name,
        );

        // 获取待翻译原文
        final record = await _db.getTranslationByChapter(task.bookId, task.chapterId);
        final original = record?['original_text'] as String?;
        if (original == null || original.trim().isEmpty) {
            throw Exception('原文提取失败');
        }

        double prog = 0;
        String finalOutput = '';
        
        await for (final progress in _translator.translateBook(
          content: original, 
          sourceLang: 'auto',
          config: config, 
          targetLang: globalState.translateTo
        )) {
            prog = progress.done / progress.total;
            finalOutput = progress.partial;
            // 每当流产出更新一次进度
            final partialStMap = <String, ChapterTranslationState>{...state};
            partialStMap[key] = task.copyWith(status: ChapterTranslationStatus.translating, progress: prog);
            state = partialStMap;

            await _db.saveTranslation(
                id: task.id, 
                bookId: task.bookId, 
                chapterId: task.chapterId, 
                status: ChapterTranslationStatus.translating.name,
                progress: prog,
                translatedText: finalOutput,
            );
        }

        // 完成
        final doneStMap = <String, ChapterTranslationState>{...state};
        doneStMap[key] = task.copyWith(
            status: ChapterTranslationStatus.completed, 
            progress: 1.0, 
            translatedText: finalOutput
        );
        state = doneStMap;

        await _db.saveTranslation(
            id: task.id, 
            bookId: task.bookId, 
            chapterId: task.chapterId, 
            status: ChapterTranslationStatus.completed.name,
            progress: 1.0,
            translatedText: finalOutput,
        );

      } catch (e) {
        // 失败
        final failStMap = <String, ChapterTranslationState>{...state};
        failStMap[key] = task.copyWith(status: ChapterTranslationStatus.failed, errorMsg: e.toString());
        state = failStMap;

        await _db.saveTranslation(
            id: task.id, 
            bookId: task.bookId, 
            chapterId: task.chapterId, 
            status: ChapterTranslationStatus.failed.name,
            errorMsg: e.toString()
        );
      }
    }

    _isProcessing = false;
  }
}

final chapterTranslationProvider = NotifierProvider<ChapterTranslationManager, Map<String, ChapterTranslationState>>(() {
  return ChapterTranslationManager();
});
