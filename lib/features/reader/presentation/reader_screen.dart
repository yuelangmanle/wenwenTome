import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import '../../../app/runtime_platform.dart';
import '../../../core/async/app_timeouts.dart';
import '../../../core/utils/text_sanitizer.dart';
import '../../annotations/annotation_service.dart';
import '../../library/data/book_model.dart';
import '../../library/mobi_converter_service.dart';
import '../../library/providers/library_providers.dart';
import '../../logging/app_run_log_service.dart';
import '../../logging/run_event_tracker.dart';
import '../../webnovel/models.dart';
import '../../webnovel/webnovel_repository.dart';
import '../android_tts_engine_service.dart';
import '../book_text_loader.dart';
import '../local_tts_model_manager.dart';
import '../reader_style.dart';
import '../providers/reader_settings_provider.dart';
import '../reader_document_probe.dart';
import '../reader_volume_key_service.dart';
import '../text_render_chunker.dart';
import '../tts_service.dart';
import '../tts_session_controller.dart';
import 'paged_text_reader.dart';

enum _CacheRangeChoice { fromCurrent, all }

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  static const int _syntheticTextSectionChars = 140000;
  static const int _syntheticTextSectionThreshold = 280000;
  static const int _forceScrollEmergencyLength = 60000000;
  static const int _minReadableSectionChars = 1200;
  static const int _maxPagedSectionChars = 220000;
  static const int _quickScrollChunkChars = 180000;
  static const int _deferTextTocThreshold = 280000;
  static const int _largeTxtLazyBytes = 24 * 1024 * 1024;
  static const int _largeTxtLazyChars = 6000000;
  static const int _largeTxtPreviewBytes = 256 * 1024;
  static const double _tapCancelDistance = 36;
  static const double _tapMenuDistance = 56;
  static const Map<String, String> _builtInFontLabels = <String, String>{
    'default': '系统默认',
    'serif': '衬线字体',
    'monospace': '等宽字体',
    'MiSans': 'MiSans',
    'LXGWWenKai': '霞鹜文楷',
    'LXGWWenKaiMono': '霞鹜文楷 Mono',
  };

  String? _pdfFilePath;
  final PdfViewerController _pdfViewerController = PdfViewerController();
  int _pdfPageCount = 0;
  int _pdfPageNumber = 1;
  int _pdfInitialPageNumber = 1;
  int? _pdfPendingPageNumber;
  Timer? _pdfProgressDebounce;
  final WebNovelRepository _webNovelRepository = WebNovelRepository();
  late final BooksNotifier _booksNotifier;
  final RunEventTracker _runEventTracker = RunEventTracker();

  bool _loading = true;
  String? _error;
  BookFormat? _openedFormat;
  String _txtContent = '';
  List<String> _textChunks = const <String>[];
  List<ReaderTocEntry> _txtToc = const <ReaderTocEntry>[];
  bool _txtTocDeferred = false;
  bool _txtLazyLoading = false;
  bool _deferTextProgressRestore = false;
  int _txtLazyRequestId = 0;
  Future<void>? _txtLazyTask;
  int _fullTextLength = 0;
  bool _fullTextLoaded = false;
  List<_ReaderTextSection> _textSections = const <_ReaderTextSection>[];
  int _currentTextSectionIndex = 0;
  List<String> _comicImagePaths = const <String>[];
  List<WebChapterRecord> _webChapters = const <WebChapterRecord>[];
  int _currentWebChapterIndex = 0;
  String _currentWebChapterContent = '';
  String _currentWebBookId = '';
  WebNovelBookMeta? _currentWebBookMeta;
  String _metaText = '';
  bool _epubFallbackUsed = false;
  bool _forceScrollTextView = false;
  bool _autoScrollForLargeTxt = false;
  bool _autoScrollTipShown = false;
  bool _textChunksLoading = false;
  Future<void>? _textChunkBuildTask;
  int _textChunkRequestId = 0;
  Future<void>? _textTocBuildTask;
  int _textTocRequestId = 0;
  bool _showOverlay = true;
  Timer? _overlayTimer;
  PageController? _cbzPageController;
  final ScrollController _txtScrollController = ScrollController();
  final GlobalKey<ReaderPagedTextViewState> _pagedTextViewKey =
      GlobalKey<ReaderPagedTextViewState>();
  final AnnotationService _annotationService = AnnotationService();
  final LocalTtsModelManager _localTtsModelManager = LocalTtsModelManager();
  final AndroidTtsEngineService _androidTtsEngineService =
      AndroidTtsEngineService();
  final ReaderVolumeKeyService _readerVolumeKeyService =
      ReaderVolumeKeyService();
  late final TtsSessionController _ttsSessionController;
  final Battery _battery = Battery();
  Timer? _batteryRefreshTimer;
  int? _batteryLevel;
  DateTime? _etaBaselineAt;
  double? _etaBaselineProgress;
  ProviderSubscription<ReaderSettings>? _readerSettingsSubscription;
  StreamSubscription<String>? _volumeKeyEventSubscription;
  bool _volumePagingHookEnabled = false;
  List<Bookmark> _bookmarks = const <Bookmark>[];
  double _textProgress = 0;
  Timer? _textProgressDebounce;
  Timer? _seekCommitDebounce;
  double? _progressDragValue;
  bool _isProgressDragging = false;
  Future<void>? _seekInFlightTask;
  int _seekRequestId = 0;
  bool _textJumping = false;
  bool _webChapterLoading = false;
  int? _webChapterLoadingIndex;
  int _webChapterRequestId = 0;
  DateTime? _readingSessionStartedAt;
  late Book _latestBookSnapshot;
  Offset? _tapDownPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _booksNotifier = ref.read(booksProvider.notifier);
    _ttsSessionController = ref.read(ttsSessionProvider.notifier);
    _openedFormat = widget.book.format;
    _latestBookSnapshot = widget.book;
    _textProgress = widget.book.readingProgress.clamp(0, 1).toDouble();
    _readingSessionStartedAt = DateTime.now();
    _etaBaselineAt = DateTime.now();
    _etaBaselineProgress = _textProgress;
    _startBatteryMonitor();
    _txtScrollController.addListener(_handleTextScroll);
    _readerSettingsSubscription = ref.listenManual<ReaderSettings>(
      readerSettingsProvider,
      (previous, next) {
        unawaited(_syncVolumePagingHook(next));
        if (previous != null && previous.readingMode != next.readingMode) {
          unawaited(_handleReadingModeChange(previous, next));
        }
      },
      fireImmediately: true,
    );
    _loadBook();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlayTimer?.cancel();
    _pdfProgressDebounce?.cancel();
    _textProgressDebounce?.cancel();
    _seekCommitDebounce?.cancel();
    _readerSettingsSubscription?.close();
    _volumeKeyEventSubscription?.cancel();
    _batteryRefreshTimer?.cancel();
    if (_volumePagingHookEnabled) {
      unawaited(_readerVolumeKeyService.setPagingEnabled(false));
    }
    _txtScrollController.removeListener(_handleTextScroll);
    _txtScrollController.dispose();
    _cbzPageController?.dispose();
    unawaited(_ttsSessionController.stop());
    unawaited(_persistReadingTime());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) {
      return;
    }
    unawaited(_ttsSessionController.handleLifecycleState(state));
  }

  Future<void> _persistReadingTime() async {
    final startedAt = _readingSessionStartedAt;
    if (startedAt == null) {
      return;
    }
    _readingSessionStartedAt = null;

    final elapsedSeconds = DateTime.now().difference(startedAt).inSeconds;
    if (elapsedSeconds < 5) {
      return;
    }

    final today = DateTime.now();
    final lastReadDay =
        '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final currentBook = _latestBookSnapshot.id.isEmpty
        ? widget.book
        : _latestBookSnapshot;
    final updatedBook = currentBook.copyWith(
      readingTimeSeconds: currentBook.readingTimeSeconds + elapsedSeconds,
      lastReadDay: lastReadDay,
    );
    _latestBookSnapshot = updatedBook;
    await _booksNotifier.updateBook(updatedBook);
  }

  void _handleTextScroll() {
    if (_loading || !_txtScrollController.hasClients) {
      return;
    }

    final maxScroll = _txtScrollController.position.maxScrollExtent;
    final progress = maxScroll <= 0
        ? 0.0
        : (_txtScrollController.offset / maxScroll).clamp(0.0, 1.0);
    if ((progress - _textProgress).abs() >= 0.01 && mounted) {
      setState(() => _textProgress = progress);
    } else {
      _textProgress = progress;
    }
    _updateEtaBaseline(progress);

    _textProgressDebounce?.cancel();
    _textProgressDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(
        _updateReadingProgress(
          (_effectiveTextLength * _textProgress).round(),
          _textProgress,
        ),
      );
    });
    _keepOverlayAlive();
  }

  Future<bool> _shouldDeferTextTocForFile(String filePath) async {
    try {
      final size = await File(filePath).length();
      return size >= _deferTextTocThreshold || size >= _largeTxtLazyBytes;
    } catch (_) {
      return false;
    }
  }

  void _updateEtaBaseline(double progress) {
    final now = DateTime.now();
    final baseline = _etaBaselineProgress;
    if (_etaBaselineAt == null || baseline == null) {
      _etaBaselineAt = now;
      _etaBaselineProgress = progress;
      return;
    }
    if ((progress - baseline).abs() >= 0.2) {
      _etaBaselineAt = now;
      _etaBaselineProgress = progress;
    }
  }

  String _formatRemainingTime(double progress) {
    final baselineAt = _etaBaselineAt;
    final baselineProgress = _etaBaselineProgress;
    if (baselineAt == null || baselineProgress == null) {
      return '';
    }
    final delta = (progress - baselineProgress).abs();
    if (delta < 0.01) {
      return '';
    }
    final elapsed = DateTime.now().difference(baselineAt).inSeconds;
    if (elapsed < 30) {
      return '';
    }
    final secondsPerProgress = elapsed / delta;
    if (!secondsPerProgress.isFinite) {
      return '';
    }
    final remainingSeconds =
        ((1 - progress).clamp(0.0, 1.0)) * secondsPerProgress;
    if (remainingSeconds <= 0 || !remainingSeconds.isFinite) {
      return '';
    }
    return _formatDuration(Duration(seconds: remainingSeconds.round()));
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}小时${minutes.toString().padLeft(2, '0')}分';
    }
    return '${minutes.clamp(1, 59)}分钟';
  }

  Future<int> _safeFileSize(String filePath) async {
    try {
      return await File(filePath).length();
    } catch (_) {
      return 0;
    }
  }

  void _scheduleTextTocBuildIfNeeded() {
    if (!_txtTocDeferred || _txtContent.isEmpty) {
      return;
    }
    if (_textTocBuildTask != null) {
      return;
    }
    final requestId = ++_textTocRequestId;
    final task = _buildTextTocInBackground(requestId);
    _textTocBuildTask = task;
    unawaited(task);
  }

  Future<void> _buildTextTocInBackground(int requestId) async {
    try {
      final toc = await ReaderDocumentProbe.buildTextTocAsync(
        _txtContent,
      ).timeout(const Duration(seconds: 60));
      if (!mounted || requestId != _textTocRequestId) {
        return;
      }
      setState(() {
        _txtToc = toc;
        _txtTocDeferred = false;
        _rebuildTextRenderingState();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || requestId != _textTocRequestId) {
          return;
        }
        _restoreTextProgress();
      });
    } catch (error, stackTrace) {
      await AppRunLogService.instance.logError(
        'TXT 目录后台解析失败：$error\n$stackTrace',
      );
    } finally {
      if (requestId == _textTocRequestId) {
        _textTocBuildTask = null;
      }
    }
  }

  Future<void> _handleReadingModeChange(
    ReaderSettings previous,
    ReaderSettings next,
  ) async {
    if (_txtContent.isEmpty && _textChunks.isEmpty) {
      return;
    }
    if (next.readingMode != 'scroll' && !_fullTextLoaded) {
      await _prepareFullTextForPaging();
      if (!_fullTextLoaded) {
        return;
      }
    }
    final totalLength = _effectiveTextLength;
    final offset = _currentTextOffset().clamp(0, totalLength);
    _textProgress = totalLength == 0
        ? 0
        : (offset / totalLength).clamp(0.0, 1.0);
    if (next.readingMode == 'scroll') {
      await _ensureTextChunksLoaded();
      await _waitForNextFrame();
      if (_txtScrollController.hasClients) {
        final maxScroll = _txtScrollController.position.maxScrollExtent;
        _txtScrollController.jumpTo(
          (_textProgress * maxScroll).clamp(0.0, maxScroll),
        );
      }
    } else {
      await _jumpToTextProgress(_textProgress, animated: false);
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _prepareFullTextForPaging() async {
    if (_txtLazyLoading) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('全文仍在后台加载中，请稍后再切换分页')));
      return;
    }
    if (_fullTextLoaded &&
        _txtContent.isNotEmpty &&
        _txtContent.length == _fullTextLength) {
      return;
    }
    if (_textChunks.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('正在准备分页内容，请稍候…')));
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    final buffer = StringBuffer();
    for (final chunk in _textChunks) {
      buffer.write(chunk);
    }
    _txtContent = buffer.toString();
    _fullTextLength = _txtContent.length;
    _fullTextLoaded = true;
    _rebuildTextRenderingState();
    if (mounted) {
      setState(() => _loading = false);
    } else {
      _loading = false;
    }
  }

  void _restoreTextProgress() {
    if (_deferTextProgressRestore && _txtLazyLoading) {
      return;
    }
    if (_usesPagedTextView(ref.read(readerSettingsProvider))) {
      unawaited(_jumpToTextProgress(_textProgress, animated: false));
      return;
    }
    if (!_txtScrollController.hasClients) {
      return;
    }
    final maxScroll = _txtScrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      return;
    }
    final target = (_textProgress.clamp(0.0, 1.0) * maxScroll).toDouble();
    _txtScrollController.jumpTo(target.clamp(0.0, maxScroll));
  }

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      completer.complete();
    });
    return completer.future;
  }

  void _startBatteryMonitor() {
    if (detectLocalRuntimePlatform() != LocalRuntimePlatform.android) {
      return;
    }
    unawaited(_refreshBatteryLevel());
    _batteryRefreshTimer?.cancel();
    _batteryRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_refreshBatteryLevel()),
    );
  }

  Future<void> _refreshBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      if (!mounted) {
        _batteryLevel = level;
        return;
      }
      setState(() => _batteryLevel = level);
    } catch (_) {
      // ignore battery query failures on unsupported platforms
    }
  }

  void _maybeShowAutoScrollTip() {
    if (_autoScrollTipShown || !_autoScrollForLargeTxt) {
      return;
    }
    if (!mounted) {
      return;
    }
    _autoScrollTipShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('检测到大 TXT，已自动切换为滚动阅读模式'),
        action: SnackBarAction(
          label: '切回分页',
          onPressed: () {
            if (!mounted) {
              return;
            }
            setState(() {
              _autoScrollForLargeTxt = false;
              _forceScrollTextView = false;
            });
            _rebuildTextRenderingState();
            _restoreTextProgress();
          },
        ),
      ),
    );
  }

  int _currentTextOffset() {
    final pagedOffset = _pagedTextViewKey.currentState?.currentOffset;
    if (pagedOffset != null) {
      return pagedOffset;
    }
    final totalLength = _effectiveTextLength;
    return (totalLength * _textProgress.clamp(0.0, 1.0)).round();
  }

  int get _effectiveTextLength =>
      _fullTextLength > 0 ? _fullTextLength : _txtContent.length;

  bool _usesPagedTextView(ReaderSettings settings) {
    return !_forceScrollTextView && settings.readingMode != 'scroll';
  }

  _ReaderTextSection _activeTextSection() {
    if (_textSections.isEmpty) {
      return _ReaderTextSection(
        title: widget.book.title,
        startOffset: 0,
        endOffset: _txtContent.length,
      );
    }
    return _textSections[_currentTextSectionIndex.clamp(
      0,
      _textSections.length - 1,
    )];
  }

  String _activeTextSectionText() {
    if (_txtContent.isEmpty) {
      return '';
    }
    final section = _activeTextSection();
    final safeStart = section.startOffset.clamp(0, _txtContent.length);
    final safeEnd = section.endOffset.clamp(safeStart, _txtContent.length);
    return _txtContent.substring(safeStart, safeEnd);
  }

  void _rebuildTextSections() {
    if (_txtContent.isEmpty) {
      _textSections = const <_ReaderTextSection>[];
      _currentTextSectionIndex = 0;
      return;
    }

    var effectiveToc = _txtToc
        .where(
          (entry) => entry.position >= 0 && entry.position < _txtContent.length,
        )
        .toList(growable: true);
    if (effectiveToc.isEmpty &&
        _txtContent.length >= _syntheticTextSectionThreshold) {
      effectiveToc = _buildSyntheticTextTocEntries(_txtContent);
      if (effectiveToc.isNotEmpty) {
        _txtToc = effectiveToc;
      }
    }

    final ordered = effectiveToc
      ..sort((left, right) => left.position.compareTo(right.position));
    if (ordered.isEmpty) {
      _textSections = <_ReaderTextSection>[
        _ReaderTextSection(
          title: widget.book.title,
          startOffset: 0,
          endOffset: _txtContent.length,
        ),
      ];
      _currentTextSectionIndex = 0;
      return;
    }

    final sections = <_ReaderTextSection>[];
    if (ordered.first.position > 0) {
      sections.add(
        _ReaderTextSection(
          title: widget.book.title,
          startOffset: 0,
          endOffset: ordered.first.position,
        ),
      );
    }
    for (var index = 0; index < ordered.length; index++) {
      final current = ordered[index];
      final nextOffset = index + 1 < ordered.length
          ? ordered[index + 1].position
          : _txtContent.length;
      if (nextOffset <= current.position) {
        continue;
      }
      sections.add(
        _ReaderTextSection(
          title: current.title.trim().isEmpty
              ? widget.book.title
              : current.title,
          startOffset: current.position,
          endOffset: nextOffset,
        ),
      );
    }

    final mergedSections = _mergeTinyTextSections(sections);
    final normalizedSections = _splitOversizedTextSections(mergedSections);
    _textSections = normalizedSections.isEmpty
        ? <_ReaderTextSection>[
            _ReaderTextSection(
              title: widget.book.title,
              startOffset: 0,
              endOffset: _txtContent.length,
            ),
          ]
        : normalizedSections;
    _currentTextSectionIndex = _sectionIndexForOffset(_currentTextOffset());
  }

  List<_ReaderTextSection> _mergeTinyTextSections(
    List<_ReaderTextSection> sections,
  ) {
    if (sections.length <= 1) {
      return sections;
    }
    final merged = <_ReaderTextSection>[];
    for (final section in sections) {
      if (merged.isEmpty) {
        merged.add(section);
        continue;
      }
      final length = section.endOffset - section.startOffset;
      if (length < _minReadableSectionChars) {
        final last = merged.removeLast();
        merged.add(
          _ReaderTextSection(
            title: last.title,
            startOffset: last.startOffset,
            endOffset: section.endOffset,
          ),
        );
        continue;
      }
      merged.add(section);
    }
    return merged;
  }

  List<_ReaderTextSection> _splitOversizedTextSections(
    List<_ReaderTextSection> sections,
  ) {
    if (sections.isEmpty) {
      return sections;
    }
    final split = <_ReaderTextSection>[];
    for (final section in sections) {
      final length = section.endOffset - section.startOffset;
      if (length <= _maxPagedSectionChars) {
        split.add(section);
        continue;
      }
      var cursor = section.startOffset;
      while (cursor < section.endOffset) {
        final remaining = section.endOffset - cursor;
        if (remaining <= _maxPagedSectionChars) {
          split.add(
            _ReaderTextSection(
              title: section.title,
              startOffset: cursor,
              endOffset: section.endOffset,
            ),
          );
          break;
        }
        final candidate = (cursor + _maxPagedSectionChars).clamp(
          cursor + 1,
          section.endOffset,
        );
        var snapped = _snapTextOffsetToSoftBreak(_txtContent, candidate);
        if (snapped <= cursor) {
          snapped = candidate;
        }
        split.add(
          _ReaderTextSection(
            title: section.title,
            startOffset: cursor,
            endOffset: snapped,
          ),
        );
        cursor = snapped;
      }
    }
    return split;
  }

  int _sectionIndexForOffset(int offset) {
    if (_textSections.isEmpty) {
      return 0;
    }
    final normalized = offset.clamp(0, _txtContent.length);
    for (var index = 0; index < _textSections.length; index++) {
      final section = _textSections[index];
      final isLast = index == _textSections.length - 1;
      if (normalized < section.endOffset || isLast) {
        return index;
      }
    }
    return _textSections.length - 1;
  }

  void _rebuildTextRenderingState() {
    _rebuildTextSections();
    final contentLength = _txtContent.length;
    final hasToc = _textSections.length > 1;
    _forceScrollTextView =
        !hasToc && contentLength >= _forceScrollEmergencyLength;
    if (_forceScrollTextView) {
      final tip = _autoScrollForLargeTxt
          ? '检测到大文本，已自动切换为滚动阅读模式，可在提示中切回分页。'
          : '文本过长，已自动切换为滚动阅读模式以避免翻页卡顿。';
      _metaText = _metaText.isEmpty ? tip : '$_metaText\n$tip';
    }
  }

  List<ReaderTocEntry> _buildSyntheticTextTocEntries(String content) {
    if (content.length < _syntheticTextSectionThreshold) {
      return const <ReaderTocEntry>[];
    }
    final toc = <ReaderTocEntry>[];
    final usedOffsets = <int>{};
    var sectionIndex = 1;
    for (
      var cursor = 0;
      cursor < content.length;
      cursor += _syntheticTextSectionChars
    ) {
      final snapped = _snapTextOffsetToSoftBreak(content, cursor);
      if (!usedOffsets.add(snapped)) {
        continue;
      }
      toc.add(ReaderTocEntry(title: '分段 $sectionIndex', position: snapped));
      sectionIndex++;
    }
    return toc;
  }

  int _snapTextOffsetToSoftBreak(String text, int offset) {
    if (text.isEmpty) {
      return 0;
    }
    final normalizedOffset = offset.clamp(0, text.length);
    if (normalizedOffset == 0 || normalizedOffset >= text.length) {
      return normalizedOffset;
    }
    const lookaround = 240;
    final start = (normalizedOffset - lookaround).clamp(0, text.length);
    final end = (normalizedOffset + lookaround).clamp(0, text.length);
    for (var index = normalizedOffset; index < end; index++) {
      if (text[index] == '\n') {
        return index + 1;
      }
    }
    for (var index = normalizedOffset; index > start; index--) {
      if (text[index - 1] == '\n') {
        return index;
      }
    }
    return normalizedOffset;
  }

  Future<void> _ensureTextChunksLoaded() async {
    if (_txtContent.isEmpty) {
      return;
    }
    if (_textChunkBuildTask != null) {
      return;
    }

    final requestId = _textChunkRequestId;
    if (mounted) {
      setState(() {
        _textChunksLoading = true;
        if (_textChunks.isEmpty) {
          _textChunks = _buildQuickTextChunks(_txtContent);
        }
      });
    } else {
      _textChunksLoading = true;
      if (_textChunks.isEmpty) {
        _textChunks = _buildQuickTextChunks(_txtContent);
      }
    }

    _textChunkBuildTask = _buildFullTextChunksInBackground(requestId);
    unawaited(_textChunkBuildTask);
  }

  List<String> _buildQuickTextChunks(String content) {
    if (content.isEmpty) {
      return const <String>[];
    }
    if (content.length <= _quickScrollChunkChars) {
      return ReaderTextChunker.chunk(content);
    }
    final quickEnd = _snapTextOffsetToSoftBreak(
      content,
      _quickScrollChunkChars.clamp(0, content.length),
    );
    return ReaderTextChunker.chunk(content.substring(0, quickEnd));
  }

  Future<void> _buildFullTextChunksInBackground(int requestId) async {
    try {
      final chunks = await ReaderTextChunker.chunkAsync(
        _txtContent,
      ).timeout(const Duration(seconds: 50));
      if (!mounted || requestId != _textChunkRequestId) {
        return;
      }
      setState(() {
        _textChunks = chunks;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || requestId != _textChunkRequestId) {
          return;
        }
        _restoreTextProgress();
      });
    } catch (error, stackTrace) {
      await AppRunLogService.instance.logError(
        '文本分块后台构建失败：$error\n$stackTrace',
      );
      if (requestId != _textChunkRequestId) {
        return;
      }
      if (mounted) {
        setState(() {
          if (_textChunks.isEmpty) {
            _textChunks = <String>[_txtContent];
          }
        });
      } else if (_textChunks.isEmpty) {
        _textChunks = <String>[_txtContent];
      }
    } finally {
      _textChunkBuildTask = null;
      if (requestId == _textChunkRequestId) {
        if (mounted) {
          setState(() => _textChunksLoading = false);
        } else {
          _textChunksLoading = false;
        }
      }
    }
  }

  Future<void> _startLazyTxtStreamLoad(
    Book book, {
    required int fileSize,
    required int previewChars,
    required String previewEncoding,
  }) async {
    final requestId = ++_txtLazyRequestId;
    final startedAt = DateTime.now();
    _txtLazyTask = () async {
      try {
        var skipChars = previewChars;
        var totalChars = _fullTextLength;
        var pendingBuffer = StringBuffer();
        var pendingLength = 0;
        var appendedSinceUi = 0;
        final uiWatch = Stopwatch()..start();
        final yieldWatch = Stopwatch()..start();
        _textChunks = List<String>.from(_textChunks);
        final stream = BookTextLoader.streamTextFileChunks(book.filePath);

        await for (final chunk in stream) {
          if (!mounted || requestId != _txtLazyRequestId) {
            return;
          }
          var text = chunk.text;
          if (skipChars > 0) {
            if (text.length <= skipChars) {
              skipChars -= text.length;
              continue;
            }
            text = text.substring(skipChars);
            skipChars = 0;
          }
          if (text.isEmpty) {
            continue;
          }

          totalChars += text.length;
          _fullTextLength = totalChars;
          pendingBuffer.write(text);
          pendingLength += text.length;

          if (pendingLength >= _quickScrollChunkChars) {
            final buffered = pendingBuffer.toString();
            final parts = ReaderTextChunker.chunk(buffered);
            if (parts.isNotEmpty) {
              final tail = parts.removeLast();
              _textChunks.addAll(parts);
              appendedSinceUi += parts.length;
              pendingBuffer = StringBuffer()..write(tail);
              pendingLength = tail.length;
            }
          }

          if (yieldWatch.elapsedMilliseconds >= 12) {
            await Future<void>.delayed(Duration.zero);
            yieldWatch.reset();
          }
          if (appendedSinceUi > 0 && uiWatch.elapsedMilliseconds >= 200) {
            if (mounted) {
              setState(() {});
            }
            appendedSinceUi = 0;
            uiWatch.reset();
          }
        }

        if (!mounted || requestId != _txtLazyRequestId) {
          return;
        }

        final buffered = pendingBuffer.toString();
        if (buffered.isNotEmpty) {
          _textChunks.addAll(ReaderTextChunker.chunk(buffered));
        }
        _fullTextLength = totalChars;
        _fullTextLoaded = true;
        _txtLazyLoading = false;
        _deferTextProgressRestore = false;
        _textChunksLoading = false;
        _textChunkBuildTask = null;
        _textTocBuildTask = null;
        _metaText = 'TXT 编码：$previewEncoding';
        if (totalChars >= _largeTxtLazyChars) {
          _metaText = '$_metaText\n超大 TXT 已完成加载';
        }
        if (mounted) {
          setState(() {});
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || requestId != _txtLazyRequestId) {
            return;
          }
          _restoreTextProgress();
          _maybeShowAutoScrollTip();
        });
        await AppRunLogService.instance.logEvent(
          action: 'reader.txt.load',
          result: 'ok',
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          context: <String, Object?>{
            'lazy': true,
            'stream': true,
            'size_bytes': fileSize,
            'chars': totalChars,
            'encoding': previewEncoding,
          },
        );
      } catch (error, stackTrace) {
        _txtLazyLoading = false;
        _textChunksLoading = false;
        if (mounted) {
          setState(() {});
        }
        await AppRunLogService.instance.logEvent(
          action: 'reader.txt.load',
          result: 'error',
          durationMs: DateTime.now().difference(startedAt).inMilliseconds,
          context: <String, Object?>{
            'lazy': true,
            'stream': true,
            'size_bytes': fileSize,
          },
          error: error,
          stackTrace: stackTrace,
          level: 'ERROR',
        );
      }
    }();
    unawaited(_txtLazyTask);
  }

  int _currentTextChunkIndex() {
    if (_textChunks.isEmpty) {
      return 0;
    }
    final offset = _currentTextOffset();
    var consumed = 0;
    for (var index = 0; index < _textChunks.length; index++) {
      consumed += _textChunks[index].length;
      if (offset <= consumed) {
        return index;
      }
    }
    return _textChunks.length - 1;
  }

  String _currentSectionTitle() {
    if ((_openedFormat ?? widget.book.format) == BookFormat.webnovel &&
        _webChapters.isNotEmpty) {
      return _webChapters[_currentWebChapterIndex].title;
    }
    if ((_openedFormat ?? widget.book.format) == BookFormat.pdf) {
      return _currentPdfSectionTitle();
    }
    if (_textSections.length > 1) {
      return _activeTextSection().title;
    }
    final position = _currentTextOffset();
    ReaderTocEntry? current;
    for (final entry in _txtToc) {
      if (entry.position > position) {
        break;
      }
      current = entry;
    }
    return current?.title ?? widget.book.title;
  }

  int _currentTextTocIndex() {
    if (_txtToc.isEmpty) {
      return -1;
    }
    final position = _currentTextOffset();
    for (var index = _txtToc.length - 1; index >= 0; index--) {
      if (_txtToc[index].position <= position) {
        return index;
      }
    }
    return 0;
  }

  int _currentPdfTocIndex() {
    if (_txtToc.isEmpty) {
      return -1;
    }
    final page = _pdfPageNumber;
    for (var index = _txtToc.length - 1; index >= 0; index--) {
      if (_txtToc[index].position <= page) {
        return index;
      }
    }
    return 0;
  }

  String _currentPdfSectionTitle() {
    final page = _pdfPageNumber <= 0 ? 1 : _pdfPageNumber;
    if (_txtToc.isEmpty) {
      return '第 $page 页';
    }
    final index = _currentPdfTocIndex();
    if (index < 0 || index >= _txtToc.length) {
      return '第 $page 页';
    }
    final title = _txtToc[index].title.trim();
    if (title.isEmpty) {
      return '第 $page 页';
    }
    return '$title（第 $page 页）';
  }

  Future<bool> _goToAdjacentTextSection(int delta) async {
    if (_textSections.length <= 1) {
      return false;
    }
    final nextSectionIndex = (_currentTextSectionIndex + delta).clamp(
      0,
      _textSections.length - 1,
    );
    if (nextSectionIndex == _currentTextSectionIndex) {
      return false;
    }
    if (mounted) {
      setState(() => _currentTextSectionIndex = nextSectionIndex);
    } else {
      _currentTextSectionIndex = nextSectionIndex;
    }
    await _waitForNextFrame();
    final section = _activeTextSection();
    final targetOffset = delta > 0
        ? section.startOffset
        : (section.endOffset - 1).clamp(section.startOffset, section.endOffset);
    await _pagedTextViewKey.currentState?.jumpToOffset(
      targetOffset,
      animated: false,
    );
    return true;
  }

  Future<void> _handlePagedBoundaryRequest(int delta) async {
    await _goToAdjacentTextSection(delta);
  }

  Future<void> _loadBookmarks() async {
    final bookmarks = await _annotationService.loadBookmarks(widget.book.id);
    if (!mounted) {
      return;
    }
    setState(() => _bookmarks = bookmarks);
  }

  Future<void> _persistCurrentBook(Book updatedBook) async {
    _latestBookSnapshot = updatedBook;
    await _booksNotifier.updateBook(updatedBook);
  }

  Future<void> _updateReadingProgress(int position, double progress) async {
    final normalizedProgress = progress.clamp(0.0, 1.0);
    _latestBookSnapshot = _latestBookSnapshot.copyWith(
      lastPosition: position,
      readingProgress: normalizedProgress,
    );
    await _booksNotifier.updateProgress(
      widget.book.id,
      position,
      normalizedProgress,
    );
  }

  Future<void> _loadBook() async {
    setState(() {
      _loading = true;
      _error = null;
      _openedFormat = widget.book.format;
      _txtContent = '';
      _textChunks = const <String>[];
      _txtToc = const <ReaderTocEntry>[];
      _txtTocDeferred = false;
      _txtLazyLoading = false;
      _deferTextProgressRestore = false;
      _txtLazyTask = null;
      _fullTextLength = 0;
      _fullTextLoaded = false;
      _textSections = const <_ReaderTextSection>[];
      _currentTextSectionIndex = 0;
      _pdfFilePath = null;
      _pdfPageCount = 0;
      _pdfPageNumber = 1;
      _pdfInitialPageNumber = 1;
      _pdfPendingPageNumber = null;
      _comicImagePaths = const <String>[];
      _metaText = '';
      _epubFallbackUsed = false;
      _forceScrollTextView = false;
      _autoScrollForLargeTxt = false;
      _autoScrollTipShown = false;
      _textChunksLoading = false;
      _textChunkBuildTask = null;
      _textTocBuildTask = null;
    });
    _textChunkRequestId++;
    _textTocRequestId++;
    _txtLazyRequestId++;
    final initialReadingMode = ref.read(readerSettingsProvider).readingMode;

    final openContext = <String, Object?>{
      'book_id': widget.book.id,
      'title': widget.book.title,
      'format': widget.book.format.name,
      'path': widget.book.filePath,
    };

    try {
      final readableBook = await _runEventTracker.track<Book>(
        action: 'reader.open_book',
        timeout: AppTimeouts.readerOpenBook,
        context: openContext,
        isCancelled: () => !mounted,
        operation: () async {
          final resolved = await _resolveReadableBook(widget.book);
          _latestBookSnapshot = resolved;
          _openedFormat = resolved.format;

          switch (resolved.format) {
            case BookFormat.epub:
              final probe = await ReaderDocumentProbe.probe(resolved);
              if (probe.kind != ReaderDocumentKind.epub) {
                throw Exception('EPUB 解析失败：未读取到正文');
              }
              _txtContent = probe.epubContent.trim().isEmpty
                  ? 'EPUB 正文为空，请检查源文件或尝试重新导入。'
                  : probe.epubContent;
              _fullTextLength = _txtContent.length;
              _fullTextLoaded = true;
              _txtToc = probe.epubToc;
              _epubFallbackUsed = probe.epubFallbackUsed;
              _metaText =
                  widget.book.format == BookFormat.mobi ||
                      widget.book.format == BookFormat.azw3
                  ? 'EPUB（由 MOBI/AZW3 转换）'
                  : 'EPUB 解析完成';
              if (_epubFallbackUsed) {
                _metaText = 'EPUB 已启用备用解析通道';
              }
              _rebuildTextRenderingState();
              if (_forceScrollTextView || initialReadingMode == 'scroll') {
                await _ensureTextChunksLoaded();
              }
              break;
            case BookFormat.pdf:
              final probe = await ReaderDocumentProbe.probe(resolved);
              if (probe.kind != ReaderDocumentKind.pdf) {
                throw Exception('PDF 解析失败：文档不可读');
              }
              _pdfFilePath = resolved.filePath;
              _txtToc = probe.pdfToc;
              _pdfPageCount = probe.pdfPageCount;
              final storedPage = resolved.lastPosition <= 0
                  ? 1
                  : resolved.lastPosition;
              _pdfInitialPageNumber = storedPage
                  .clamp(1, math.max(1, _pdfPageCount))
                  .toInt();
              _pdfPageNumber = _pdfInitialPageNumber;
              _metaText = 'PDF ${probe.pdfPageCount} 页';
              break;
            case BookFormat.txt:
              final fileSize = await _safeFileSize(resolved.filePath);
              final shouldLazy = fileSize > _largeTxtLazyBytes;
              _autoScrollForLargeTxt = false;
              await AppRunLogService.instance.logEvent(
                action: 'reader.txt.load',
                result: 'start',
                context: <String, Object?>{
                  'path': resolved.filePath,
                  'size_bytes': fileSize,
                  'lazy': shouldLazy,
                },
              );
              if (shouldLazy) {
                final preview = await BookTextLoader.readTextFilePreview(
                  resolved.filePath,
                  maxBytes: _largeTxtPreviewBytes,
                );
                _txtContent = preview.text;
                _fullTextLength = _txtContent.length;
                _fullTextLoaded = false;
                _txtToc = const <ReaderTocEntry>[];
                _txtTocDeferred = true;
                _txtLazyLoading = true;
                _deferTextProgressRestore = true;
                _metaText = 'TXT 编码：${preview.encoding}\n超大 TXT 预览，后台加载中…';
                _rebuildTextRenderingState();
                _textChunks = _buildQuickTextChunks(_txtContent);
                _textChunksLoading = true;
                _textChunkBuildTask = null;
                await AppRunLogService.instance.logEvent(
                  action: 'reader.txt.load',
                  result: 'partial',
                  context: <String, Object?>{
                    'lazy': true,
                    'size_bytes': fileSize,
                    'preview_chars': _txtContent.length,
                    'encoding': preview.encoding,
                  },
                );
                await _startLazyTxtStreamLoad(
                  resolved,
                  fileSize: fileSize,
                  previewChars: _txtContent.length,
                  previewEncoding: preview.encoding,
                );
                break;
              } else {
                final shouldDeferToc = await _shouldDeferTextTocForFile(
                  resolved.filePath,
                );
                final probe = await ReaderDocumentProbe.probe(
                  resolved,
                  deferTextToc: shouldDeferToc,
                );
                _txtContent = probe.txtContent;
                _fullTextLength = _txtContent.length;
                _fullTextLoaded = true;
                _txtToc = probe.txtToc;
                _txtTocDeferred = probe.txtTocDeferred;
                _metaText = 'TXT 编码：${probe.txtEncoding}';
                _rebuildTextRenderingState();
                if (_forceScrollTextView || initialReadingMode == 'scroll') {
                  await _ensureTextChunksLoaded();
                }
                _scheduleTextTocBuildIfNeeded();
                await AppRunLogService.instance.logEvent(
                  action: 'reader.txt.load',
                  result: 'ok',
                  context: <String, Object?>{
                    'lazy': false,
                    'size_bytes': fileSize,
                    'chars': _txtContent.length,
                    'encoding': probe.txtEncoding,
                  },
                );
              }
              break;
            case BookFormat.cbz:
            case BookFormat.cbr:
              final probe = await ReaderDocumentProbe.probe(resolved);
              _comicImagePaths = probe.comicImagePaths;
              _cbzPageController = PageController(
                initialPage: resolved.lastPosition,
              );
              break;
            case BookFormat.webnovel:
              await _loadWebNovel();
              break;
            case BookFormat.mobi:
            case BookFormat.azw3:
              throw Exception('MOBI / AZW3 暂不支持直接阅读，请先转换为 EPUB');
            case BookFormat.unknown:
              throw Exception('当前格式暂不支持阅读');
          }

          return resolved;
        },
      );

      if (!mounted) {
        return;
      }
      _latestBookSnapshot = readableBook;
      await _loadBookmarks();
      setState(() => _loading = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreTextProgress();
        _maybeShowAutoScrollTip();
      });
      _startOverlayDismissTimer();
      unawaited(_syncVolumePagingHook(ref.read(readerSettingsProvider)));
    } on AppOperationCancelledException {
      return;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
      unawaited(_syncVolumePagingHook(ref.read(readerSettingsProvider)));
    }
  }

  Future<Book> _resolveReadableBook(Book book) async {
    if (book.format != BookFormat.mobi && book.format != BookFormat.azw3) {
      return book;
    }

    String convertedPath;
    try {
      final converted = await MobiConverterService.convertToEpub(book.filePath);
      if (converted == null) {
        throw Exception('暂不支持直接读取该格式');
      }
      convertedPath = converted.outputPath;
    } on MobiConvertFailure catch (e) {
      throw Exception(e.toString());
    }

    final updatedBook = book.copyWith(
      filePath: convertedPath,
      title: p.basenameWithoutExtension(convertedPath),
      format: BookFormat.epub,
    );
    await _persistCurrentBook(updatedBook);
    await AppRunLogService.instance.logInfo(
      'MOBI/AZW3 converted to EPUB: ${book.filePath} -> $convertedPath',
    );
    return updatedBook;
  }

  Future<void> _loadWebNovel() async {
    final uri = widget.book.filePath;
    if (!uri.startsWith('webnovel://book/')) {
      throw Exception('网文链接格式无效');
    }

    _currentWebBookId = uri.substring('webnovel://book/'.length).trim();
    if (_currentWebBookId.isEmpty) {
      throw Exception('网文链接缺少书籍 ID');
    }
    _currentWebBookMeta = await _webNovelRepository.getBookMeta(
      _currentWebBookId,
    );
    if (_currentWebBookMeta == null) {
      throw Exception('未找到网文元数据');
    }
    _webChapters = await _webNovelRepository.getChapters(_currentWebBookId);
    if (_webChapters.isEmpty) {
      final state = await _webNovelRepository.describeChapterSyncState(
        _currentWebBookId,
      );
      throw Exception('未获取到网文章节：$state');
    }

    _currentWebChapterIndex = widget.book.lastPosition.clamp(
      0,
      _webChapters.length - 1,
    );
    final chapter = await _webNovelRepository.getChapterContent(
      _currentWebBookId,
      _currentWebChapterIndex,
    );
    _currentWebChapterContent = chapter.text;
  }

  void _toggleOverlay() {
    final next = !_showOverlay;
    if (mounted) {
      setState(() => _showOverlay = next);
    } else {
      _showOverlay = next;
    }
    if (next) {
      _startOverlayDismissTimer();
    } else {
      _overlayTimer?.cancel();
    }
  }

  void _startOverlayDismissTimer() {
    if (!_showOverlay) {
      return;
    }
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 4), () {
      if (_isProgressDragging || _textJumping || _webChapterLoading) {
        _startOverlayDismissTimer();
        return;
      }
      if (mounted) {
        setState(() => _showOverlay = false);
      }
    });
  }

  void _keepOverlayAlive() {
    if (!_showOverlay) {
      return;
    }
    _startOverlayDismissTimer();
  }

  Future<String> _extractSpeakText() async {
    const maxChars = 1800;
    switch (_openedFormat ?? widget.book.format) {
      case BookFormat.txt:
      case BookFormat.epub:
        final pagedSpeakWindow =
            _pagedTextViewKey.currentState?.currentSpeakWindowText;
        if (pagedSpeakWindow != null && pagedSpeakWindow.trim().isNotEmpty) {
          return _clipSpeakText(pagedSpeakWindow, maxChars: maxChars);
        }
        if (_textChunks.isEmpty) {
          return _clipSpeakText(_txtContent, maxChars: maxChars);
        }
        final start = _currentTextChunkIndex();
        final end = (start + 2).clamp(0, _textChunks.length);
        return _clipSpeakText(
          _textChunks.sublist(start, end).join('\n\n'),
          maxChars: maxChars,
        );
      case BookFormat.webnovel:
        return _clipSpeakText(_currentWebChapterContent, maxChars: maxChars);
      default:
        return '当前格式不支持朗读';
    }
  }

  String _clipSpeakText(String text, {required int maxChars}) {
    final normalized = text.trim();
    if (normalized.length <= maxChars) {
      return normalized;
    }
    return normalized.substring(0, maxChars);
  }

  String _currentTtsModeValue(ReaderSettings settings) {
    if (settings.useLocalTts) {
      return 'local';
    }
    if (settings.useAndroidExternalTts) {
      return 'android_external';
    }
    if (settings.useEdgeTts) {
      return 'edge';
    }
    return 'system';
  }

  String _ttsStateLabel(TtsState state) {
    return switch (state) {
      TtsState.playing => '播放中',
      TtsState.paused => '已暂停',
      TtsState.stopped => '已停止',
    };
  }

  Future<void> _openBookmark(Bookmark bookmark) async {
    switch (_openedFormat ?? widget.book.format) {
      case BookFormat.txt:
      case BookFormat.epub:
        if (_txtContent.isEmpty) {
          return;
        }
        await _jumpToTextOffsetWithPlaceholder(bookmark.position);
        return;
      case BookFormat.pdf:
        await _jumpToPdfPage(bookmark.position);
        return;
      case BookFormat.webnovel:
        await _openWebChapter(bookmark.position, trigger: 'bookmark');
        return;
      case BookFormat.cbz:
      case BookFormat.cbr:
        if (_cbzPageController == null) {
          return;
        }
        await _cbzPageController!.animateToPage(
          bookmark.position,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return;
      default:
        return;
    }
  }

  Future<void> _showNavigationSheet() async {
    final hasToc = _txtToc.isNotEmpty || _webChapters.isNotEmpty;
    final hasBookmarks = _bookmarks.isNotEmpty;
    if (!hasToc && !hasBookmarks) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前书籍暂无目录或书签')));
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final openedFormat = _openedFormat ?? widget.book.format;
        final currentTocIndex = openedFormat == BookFormat.pdf
            ? _currentPdfTocIndex()
            : _currentTextTocIndex();
        final tocRowBase = _txtToc.isEmpty ? 0 : 2;
        final webRowBase = _txtToc.isEmpty ? 0 : (2 + _txtToc.length);

        var focusRowIndex = 0;
        if (_txtToc.isNotEmpty && currentTocIndex >= 0) {
          focusRowIndex = tocRowBase + currentTocIndex;
        } else if (_webChapters.isNotEmpty) {
          focusRowIndex = webRowBase + 2 + _currentWebChapterIndex;
        }

        final initialOffset = focusRowIndex <= 1
            ? 0.0
            : ((focusRowIndex - 1) * 56.0);
        final listController = ScrollController(
          initialScrollOffset: initialOffset,
        );
        return SafeArea(
          child: SizedBox(
            height: 420,
            child: ListView.builder(
              controller: listController,
              padding: const EdgeInsets.all(16),
              itemCount: _navigationSheetRowCount(
                hasToc: _txtToc.isNotEmpty,
                hasWeb: _webChapters.isNotEmpty,
                hasBookmarks: _bookmarks.isNotEmpty,
              ),
              itemBuilder: (context, rowIndex) {
                return _buildNavigationSheetRow(
                  context,
                  rowIndex: rowIndex,
                  openedFormat: openedFormat,
                  currentTocIndex: currentTocIndex,
                );
              },
            ),
          ),
        );
      },
    );
  }

  int _navigationSheetRowCount({
    required bool hasToc,
    required bool hasWeb,
    required bool hasBookmarks,
  }) {
    var count = 0;
    if (hasToc) {
      count += 2 + _txtToc.length; // header + spacer + items
    }
    if (hasWeb) {
      count += 2 + _webChapters.length; // header + spacer + items
    }
    if (hasBookmarks) {
      count += 3 + _bookmarks.length; // spacer + header + spacer + items
    }
    return count;
  }

  Widget _buildNavigationSheetRow(
    BuildContext context, {
    required int rowIndex,
    required BookFormat openedFormat,
    required int currentTocIndex,
  }) {
    var cursor = 0;

    if (_txtToc.isNotEmpty) {
      if (rowIndex == cursor) {
        return const Text(
          '目录',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        );
      }
      cursor += 1;
      if (rowIndex == cursor) {
        return const SizedBox(height: 8);
      }
      cursor += 1;

      final localIndex = rowIndex - cursor;
      if (localIndex >= 0 && localIndex < _txtToc.length) {
        return ListTile(
          dense: true,
          selected: localIndex == currentTocIndex,
          title: Text(_txtToc[localIndex].title),
          onTap: () {
            Navigator.pop(context);
            final position = _txtToc[localIndex].position;
            if (openedFormat == BookFormat.pdf) {
              unawaited(_jumpToPdfPage(position));
              return;
            }
            if (_txtContent.isEmpty) {
              return;
            }
            unawaited(_jumpToTextOffsetWithPlaceholder(position));
          },
        );
      }
      cursor += _txtToc.length;
    }

    if (_webChapters.isNotEmpty) {
      if (rowIndex == cursor) {
        return const Text(
          '网文章节',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        );
      }
      cursor += 1;
      if (rowIndex == cursor) {
        return const SizedBox(height: 8);
      }
      cursor += 1;

      final localIndex = rowIndex - cursor;
      if (localIndex >= 0 && localIndex < _webChapters.length) {
        return ListTile(
          dense: true,
          title: Text(_webChapters[localIndex].title),
          selected: localIndex == _currentWebChapterIndex,
          onTap: () {
            Navigator.pop(context);
            unawaited(_openWebChapter(localIndex, trigger: 'toc'));
          },
        );
      }
      cursor += _webChapters.length;
    }

    if (_bookmarks.isNotEmpty) {
      if (rowIndex == cursor) {
        return const SizedBox(height: 12);
      }
      cursor += 1;
      if (rowIndex == cursor) {
        return const Text(
          '书签',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        );
      }
      cursor += 1;
      if (rowIndex == cursor) {
        return const SizedBox(height: 8);
      }
      cursor += 1;

      final localIndex = rowIndex - cursor;
      if (localIndex >= 0 && localIndex < _bookmarks.length) {
        final bookmark = _bookmarks[_bookmarks.length - 1 - localIndex];
        return ListTile(
          dense: true,
          title: Text(bookmark.title),
          subtitle: Text(bookmark.createdAt.toLocal().toString()),
          trailing: IconButton(
            onPressed: () async {
              await _annotationService.deleteBookmark(bookmark.id);
              await _loadBookmarks();
              if (!context.mounted) {
                return;
              }
              Navigator.pop(context);
            },
            icon: const Icon(Icons.delete_outline),
          ),
          onTap: () {
            Navigator.pop(context);
            unawaited(_openBookmark(bookmark));
          },
        );
      }
    }

    return const SizedBox.shrink();
  }

  Future<void> _openWebChapter(int index, {String trigger = 'direct'}) async {
    if (_currentWebBookId.isEmpty || _webChapters.isEmpty) {
      return;
    }
    final targetIndex = index.clamp(0, _webChapters.length - 1);
    final requestId = ++_webChapterRequestId;
    if (mounted) {
      setState(() {
        _webChapterLoading = true;
        _webChapterLoadingIndex = targetIndex;
      });
    } else {
      _webChapterLoading = true;
      _webChapterLoadingIndex = targetIndex;
    }

    try {
      final content = await _runEventTracker.track(
        action: 'reader.open_web_chapter',
        timeout: AppTimeouts.readerOpenWebChapter,
        context: <String, Object?>{
          'web_book_id': _currentWebBookId,
          'chapter_index': targetIndex,
          'trigger': trigger,
        },
        isCancelled: () => !mounted || requestId != _webChapterRequestId,
        operation: () => _webNovelRepository.getChapterContent(
          _currentWebBookId,
          targetIndex,
        ),
      );
      if (!mounted || requestId != _webChapterRequestId) {
        return;
      }
      setState(() {
        _currentWebChapterIndex = targetIndex;
        _currentWebChapterContent = content.text;
      });
      final progress = _webChapters.length <= 1
          ? 1.0
          : (targetIndex / (_webChapters.length - 1)).clamp(0.0, 1.0);
      _updateEtaBaseline(progress);
      unawaited(_updateReadingProgress(targetIndex, progress));
    } catch (error) {
      if (error is AppOperationCancelledException) {
        return;
      }
      if (!mounted || requestId != _webChapterRequestId) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('章节加载失败：$error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (requestId == _webChapterRequestId) {
        if (mounted) {
          setState(() {
            _webChapterLoading = false;
            _webChapterLoadingIndex = null;
          });
        } else {
          _webChapterLoading = false;
          _webChapterLoadingIndex = null;
        }
      }
    }
  }

  Future<void> _jumpToTextOffsetWithPlaceholder(int offset) async {
    if (_txtContent.isEmpty) {
      return;
    }
    if (mounted) {
      setState(() => _textJumping = true);
    } else {
      _textJumping = true;
    }
    try {
      await _jumpToTextOffset(offset);
    } finally {
      if (mounted) {
        setState(() => _textJumping = false);
      } else {
        _textJumping = false;
      }
    }
  }

  Future<void> _jumpToPdfPage(int pageNumber) async {
    if (_pdfFilePath == null || _pdfPageCount <= 0) {
      return;
    }
    final safePage = pageNumber.clamp(1, math.max(1, _pdfPageCount)).toInt();
    if (!_pdfViewerController.isReady) {
      _pdfPendingPageNumber = safePage;
      _pdfInitialPageNumber = safePage;
      if (mounted) {
        setState(() {});
      }
      return;
    }

    _pdfPendingPageNumber = null;
    try {
      await _pdfViewerController.goToPage(pageNumber: safePage);
    } catch (_) {}

    _pdfPageNumber = safePage;
    final progress = _pdfPageCount <= 1
        ? 0.0
        : ((_pdfPageNumber - 1) / (_pdfPageCount - 1)).clamp(0.0, 1.0);
    await _updateReadingProgress(_pdfPageNumber, progress);
    if (mounted) {
      setState(() {});
    }
  }

  void _handleProgressChanged(BookFormat openedFormat, double value) {
    final normalized = value.clamp(0.0, 1.0);
    _updateEtaBaseline(normalized);
    if (mounted) {
      setState(() {
        _isProgressDragging = true;
        _progressDragValue = normalized;
        if (openedFormat == BookFormat.txt || openedFormat == BookFormat.epub) {
          _textProgress = normalized;
        }
      });
    } else {
      _isProgressDragging = true;
      _progressDragValue = normalized;
      if (openedFormat == BookFormat.txt || openedFormat == BookFormat.epub) {
        _textProgress = normalized;
      }
    }
    _keepOverlayAlive();
  }

  void _handleProgressChangeEnd(double value) {
    final normalized = value.clamp(0.0, 1.0);
    _seekCommitDebounce?.cancel();
    _seekCommitDebounce = Timer(const Duration(milliseconds: 140), () {
      unawaited(_runSeekToProgress(normalized));
    });
    if (mounted) {
      setState(() {
        _isProgressDragging = false;
        _progressDragValue = null;
      });
    } else {
      _isProgressDragging = false;
      _progressDragValue = null;
    }
    _keepOverlayAlive();
  }

  Future<void> _runSeekToProgress(double progress) async {
    final requestId = ++_seekRequestId;
    final inFlight = _seekInFlightTask;
    if (inFlight != null) {
      await inFlight;
      if (requestId != _seekRequestId) {
        return;
      }
    }
    final openedFormat = (_openedFormat ?? widget.book.format).name;
    final task = _runEventTracker.track<void>(
      action: 'reader.seek_progress',
      timeout: AppTimeouts.readerSeekProgress,
      context: <String, Object?>{
        'book_id': widget.book.id,
        'format': openedFormat,
        'progress': progress,
      },
      isCancelled: () => requestId != _seekRequestId || !mounted,
      operation: () => _seekToProgress(progress),
    );
    _seekInFlightTask = task;
    try {
      await task;
    } on AppOperationCancelledException {
      return;
    } finally {
      if (identical(_seekInFlightTask, task)) {
        _seekInFlightTask = null;
      }
    }
  }

  Future<void> _seekToProgress(double progress) async {
    final normalized = progress.clamp(0.0, 1.0);
    switch (_openedFormat ?? widget.book.format) {
      case BookFormat.txt:
      case BookFormat.epub:
        await _jumpToTextProgress(normalized);
        return;
      case BookFormat.pdf:
        if (_pdfPageCount <= 0) {
          return;
        }
        final pageNumber = _pdfPageCount <= 1
            ? 1
            : (normalized * (_pdfPageCount - 1)).round() + 1;
        await _jumpToPdfPage(pageNumber);
        return;
      case BookFormat.webnovel:
        if (_webChapters.isEmpty) {
          return;
        }
        final index = (normalized * (_webChapters.length - 1)).round();
        await _openWebChapter(
          index.clamp(0, _webChapters.length - 1),
          trigger: 'seek',
        );
        return;
      case BookFormat.cbz:
      case BookFormat.cbr:
        if (_cbzPageController == null || _comicImagePaths.isEmpty) {
          return;
        }
        final page = (normalized * (_comicImagePaths.length - 1)).round();
        await _cbzPageController!.animateToPage(
          page.clamp(0, _comicImagePaths.length - 1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return;
      default:
        return;
    }
  }

  Future<void> _cacheRemainingWebNovelChapters() async {
    if (_currentWebBookId.isEmpty || _webChapters.isEmpty) {
      return;
    }
    final total = _webChapters.length;
    final choice = await showDialog<_CacheRangeChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('缓存章节'),
        content: Text('当前共 $total 章，从哪里开始缓存？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _CacheRangeChoice.fromCurrent),
            child: const Text('从当前章开始'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, _CacheRangeChoice.all),
            child: const Text('缓存全部'),
          ),
        ],
      ),
    );
    if (choice == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('已开始后台缓存章节...')));
    try {
      final startIndex = choice == _CacheRangeChoice.all
          ? 0
          : _currentWebChapterIndex;
      final enqueuedCount = await _runEventTracker.track<int>(
        action: 'webnovel.cache_chapters',
        context: <String, Object?>{
          'web_book_id': _currentWebBookId,
          'start_index': startIndex,
          'background': true,
        },
        isCancelled: () => !mounted,
        operation: () => _webNovelRepository.cacheBookChapters(
          _currentWebBookId,
          startIndex: startIndex,
          background: true,
        ),
      );
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('已加入缓存任务：$enqueuedCount 章（可在缓存管理查看进度）')),
      );
    } catch (error) {
      if (error is AppOperationCancelledException) {
        return;
      }
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('缓存失败：$error'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _openOriginWebPage() async {
    final meta = _currentWebBookMeta;
    if (meta == null) {
      return;
    }
    final url = meta.originUrl.trim();
    if (url.isEmpty) {
      return;
    }
    if (!mounted) {
      return;
    }
    context.push('/webnovel', extra: url);
  }

  double _currentProgressValue() {
    switch (_openedFormat ?? widget.book.format) {
      case BookFormat.txt:
      case BookFormat.epub:
        return _textProgress.clamp(0.0, 1.0);
      case BookFormat.pdf:
        if (_pdfPageCount <= 1) {
          return 0;
        }
        return ((_pdfPageNumber - 1) / (_pdfPageCount - 1)).clamp(0.0, 1.0);
      case BookFormat.webnovel:
        if (_webChapters.length <= 1) {
          return 0;
        }
        return (_currentWebChapterIndex / (_webChapters.length - 1)).clamp(
          0.0,
          1.0,
        );
      case BookFormat.cbz:
      case BookFormat.cbr:
        final page = _cbzPageController?.hasClients == true
            ? _cbzPageController!.page?.round() ?? 0
            : widget.book.lastPosition;
        if (_comicImagePaths.length <= 1) {
          return 0;
        }
        return (page / (_comicImagePaths.length - 1)).clamp(0.0, 1.0);
      default:
        return widget.book.readingProgress.clamp(0, 1).toDouble();
    }
  }

  Future<void> _jumpToTextProgress(
    double progress, {
    bool animated = true,
  }) async {
    _textProgress = progress.clamp(0.0, 1.0);
    if (_usesPagedTextView(ref.read(readerSettingsProvider)) &&
        _txtContent.isNotEmpty) {
      final offset = (_txtContent.length * _textProgress).round();
      await _jumpToTextOffset(offset, animated: animated);
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (_txtScrollController.hasClients) {
      final maxScroll = _txtScrollController.position.maxScrollExtent;
      await _txtScrollController.animateTo(
        (_textProgress * maxScroll).clamp(0.0, maxScroll),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    await _updateReadingProgress(
      (_txtContent.length * _textProgress).round(),
      _textProgress,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _jumpToTextOffset(int offset, {bool animated = true}) async {
    if (_txtContent.isEmpty) {
      return;
    }
    final normalizedProgress = (offset / _txtContent.length).clamp(0.0, 1.0);
    if (_usesPagedTextView(ref.read(readerSettingsProvider)) &&
        _textSections.isNotEmpty) {
      final targetSectionIndex = _sectionIndexForOffset(offset);
      if (_currentTextSectionIndex != targetSectionIndex && mounted) {
        setState(() => _currentTextSectionIndex = targetSectionIndex);
        await _waitForNextFrame();
      }
      await _pagedTextViewKey.currentState?.jumpToOffset(
        offset,
        animated: animated,
      );
      _textProgress = normalizedProgress;
      if (mounted) {
        setState(() {});
      }
      return;
    }
    await _jumpToTextProgress(normalizedProgress);
  }

  void _handlePagedTextLocationChanged(ReaderPagedTextLocation location) {
    _textProgress = location.progress;
    _currentTextSectionIndex = _sectionIndexForOffset(location.startOffset);
    _updateEtaBaseline(location.progress);
    _textProgressDebounce?.cancel();
    _textProgressDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(
        _updateReadingProgress(location.startOffset, location.progress),
      );
    });
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _addBookmark() async {
    final openedFormat = _openedFormat ?? widget.book.format;
    var position = 0;
    var title = widget.book.title;
    switch (openedFormat) {
      case BookFormat.txt:
      case BookFormat.epub:
        position = _currentTextOffset();
        title = _currentSectionTitle();
        break;
      case BookFormat.pdf:
        position = _pdfPageNumber;
        title = _currentPdfSectionTitle();
        break;
      case BookFormat.webnovel:
        position = _currentWebChapterIndex;
        title = _webChapters.isEmpty
            ? widget.book.title
            : _webChapters[_currentWebChapterIndex].title;
        break;
      case BookFormat.cbz:
      case BookFormat.cbr:
        position = _cbzPageController?.hasClients == true
            ? _cbzPageController!.page?.round() ?? 0
            : widget.book.lastPosition;
        title = '第 ${position + 1} 页';
        break;
      default:
        return;
    }

    await _annotationService.addBookmark(
      bookId: widget.book.id,
      title: title,
      position: position,
    );
    await _loadBookmarks();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('书签已添加')));
  }

  Future<void> _showReaderAppearanceSettings() async {
    final notifier = ref.read(readerSettingsProvider.notifier);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final current = ref.read(readerSettingsProvider);
            final isAndroid =
                detectLocalRuntimePlatform() == LocalRuntimePlatform.android;
            final fontOptions = <String>[..._builtInFontLabels.keys];
            if (current.customFontFamily != null &&
                current.customFontFamily!.isNotEmpty) {
              fontOptions.add(current.customFontFamily!);
            }
            final selectedFontFamily = fontOptions.contains(current.fontFamily)
                ? current.fontFamily
                : 'default';
            final sanitizedCustomFontName = sanitizeUiText(
              current.customFontName ?? '',
              fallback: '自定义字体',
            );

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '阅读外观设置',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildSlider(
                        label: '字体大小',
                        value: current.fontSize,
                        min: 14,
                        max: 30,
                        divisions: 16,
                        displayValue: current.fontSize.toStringAsFixed(0),
                        onChanged: (value) {
                          notifier.setFontSize(value);
                          setSheetState(() {});
                        },
                      ),
                      _buildSlider(
                        label: '行高',
                        value: current.lineHeight,
                        min: 1.2,
                        max: 2.2,
                        divisions: 10,
                        displayValue: current.lineHeight.toStringAsFixed(1),
                        onChanged: (value) {
                          notifier.setLineHeight(value);
                          setSheetState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      const Text('文本对齐'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('两端对齐'),
                            selected: current.textAlignMode == 'justify',
                            onSelected: (_) {
                              notifier.setTextAlignMode('justify');
                              setSheetState(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('左对齐'),
                            selected: current.textAlignMode == 'start',
                            onSelected: (_) {
                              notifier.setTextAlignMode('start');
                              setSheetState(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('居中'),
                            selected: current.textAlignMode == 'center',
                            onSelected: (_) {
                              notifier.setTextAlignMode('center');
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('段落排布'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('紧凑'),
                            selected: current.paragraphPreset == 'compact',
                            onSelected: (_) {
                              notifier.setParagraphPreset('compact');
                              setSheetState(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('均衡'),
                            selected: current.paragraphPreset == 'balanced',
                            onSelected: (_) {
                              notifier.setParagraphPreset('balanced');
                              setSheetState(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('宽松'),
                            selected: current.paragraphPreset == 'airy',
                            onSelected: (_) {
                              notifier.setParagraphPreset('airy');
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('阅读模式'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('分页'),
                            selected: current.readingMode != 'scroll',
                            onSelected: (_) {
                              notifier.setReadingMode('paged');
                              setSheetState(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('滚动'),
                            selected: current.readingMode == 'scroll',
                            onSelected: (_) {
                              notifier.setReadingMode('scroll');
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('点击区域'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('中间菜单 + 左右翻页'),
                            selected: current.tapRegionMode == 'center_menu',
                            onSelected: (_) {
                              notifier.setTapRegionMode('center_menu');
                              setSheetState(() {});
                            },
                          ),
                          ChoiceChip(
                            label: const Text('全屏菜单'),
                            selected: current.tapRegionMode == 'all_menu',
                            onSelected: (_) {
                              notifier.setTapRegionMode('all_menu');
                              setSheetState(() {});
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('音量键翻页'),
                        subtitle: Text(
                          isAndroid ? '音量减键上一页，音量加键下一页' : '仅 Android 可用',
                        ),
                        value: current.volumeKeyPagingEnabled,
                        onChanged: !isAndroid
                            ? null
                            : (value) {
                                notifier.setVolumeKeyPagingEnabled(value);
                                setSheetState(() {});
                              },
                      ),
                      if (current.readingMode != 'scroll') ...[
                        const SizedBox(height: 16),
                        const Text('翻页动画'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children:
                              [
                                    ('sheet', '仿真纸张'),
                                    ('page_curl', '仿真翻页'),
                                    ('slide', '滑动'),
                                    ('fade', '淡入'),
                                  ]
                                  .map(
                                    (item) => ChoiceChip(
                                      label: Text(item.$2),
                                      selected:
                                          current.pageAnimation == item.$1,
                                      onSelected: (_) {
                                        notifier.setPageAnimation(item.$1);
                                        setSheetState(() {});
                                      },
                                    ),
                                  )
                                  .toList(),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const Text('阅读字体'),
                      const SizedBox(height: 8),
                      DropdownButton<String>(
                        value: selectedFontFamily,
                        isExpanded: true,
                        items: [
                          ..._builtInFontLabels.entries.map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(
                                sanitizeUiText(
                                  entry.value,
                                  fallback: entry.value,
                                ),
                              ),
                            ),
                          ),
                          if (current.customFontFamily != null &&
                              current.customFontName != null)
                            DropdownMenuItem(
                              value: current.customFontFamily!,
                              child: Text('自定义字体 · $sanitizedCustomFontName'),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          notifier.setFontFamily(value);
                          setSheetState(() {});
                        },
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () async {
                                final imported = await notifier
                                    .importCustomFont();
                                if (!mounted || imported == null) {
                                  return;
                                }
                                setSheetState(() {});
                                if (!context.mounted) {
                                  return;
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '已导入字体：${imported.displayName}',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.upload_file_outlined),
                              label: const Text('导入字体'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: current.customFontFamily == null
                                  ? null
                                  : () {
                                      notifier.clearCustomFont();
                                      setSheetState(() {});
                                    },
                              child: const Text('清除自定义'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('主题预设'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(
                          ReaderSettings.backgrounds.length,
                          (index) {
                            final palette = ReaderSettings.backgrounds[index];
                            return ChoiceChip(
                              label: Text('主题 ${index + 1}'),
                              avatar: CircleAvatar(
                                backgroundColor: Color(palette.bg),
                                foregroundColor: Color(palette.fg),
                                child: const Icon(Icons.auto_awesome, size: 16),
                              ),
                              selected:
                                  current.backgroundIndex == index &&
                                  current.customBgColor == null &&
                                  current.customFgColor == null,
                              onSelected: (_) {
                                notifier.setBackground(index);
                                setSheetState(() {});
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Color(current.bgColor),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Color(
                              current.fgColor,
                            ).withValues(alpha: 0.16),
                          ),
                        ),
                        child: Text(
                          '预览区会实时展示当前字体、配色和段落排布效果。',
                          style: buildReaderTextStyle(
                            current,
                            color: Color(current.fgColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildColorEditor(
                        label: '背景色',
                        color: Color(current.bgColor),
                        onChanged: (color) {
                          notifier.setCustomColors(
                            color.toARGB32(),
                            Color(current.fgColor).toARGB32(),
                          );
                          setSheetState(() {});
                        },
                      ),
                      _buildColorEditor(
                        label: '文字色',
                        color: Color(current.fgColor),
                        onChanged: (color) {
                          notifier.setCustomColors(
                            Color(current.bgColor).toARGB32(),
                            color.toARGB32(),
                          );
                          setSheetState(() {});
                        },
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed:
                              current.customBgColor == null &&
                                  current.customFgColor == null
                              ? null
                              : () {
                                  notifier.clearCustomColors();
                                  setSheetState(() {});
                                },
                          child: const Text('恢复主题默认'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayValue,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $displayValue'),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: displayValue,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildColorEditor({
    required String label,
    required Color color,
    required ValueChanged<Color> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label),
            const SizedBox(width: 10),
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.black.withValues(alpha: 0.16)),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ColorPicker(
          pickerColor: color,
          onColorChanged: onChanged,
          enableAlpha: false,
          displayThumbColor: true,
          pickerAreaHeightPercent: 0.45,
        ),
      ],
    );
  }

  Future<void> _showTtsPanel() async {
    final ttsController = ref.read(ttsSessionProvider.notifier);
    final notifier = ref.read(readerSettingsProvider.notifier);
    var playInProgress = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Consumer(
              builder: (context, ref, _) {
                final current = ref.watch(readerSettingsProvider);
                final ttsState = ref.watch(ttsSessionProvider);
                final activeModel =
                    LocalTtsModelManager.getModelById(
                      current.activeLocalTtsId,
                    ) ??
                    LocalTtsModelManager.availableModels.first;
                final isAndroid =
                    detectLocalRuntimePlatform() ==
                    LocalRuntimePlatform.android;
                final modeSummary = current.useLocalTts
                    ? '当前朗读引擎：本地模型（${activeModel.name}）'
                    : current.useAndroidExternalTts
                    ? '当前朗读引擎：Android 外部 TTS'
                    : current.useEdgeTts
                    ? '当前朗读引擎：Edge TTS'
                    : '当前朗读引擎：系统 TTS';

                Future<void> playCurrentSegment() async {
                  if (playInProgress) {
                    return;
                  }
                  setSheetState(() => playInProgress = true);
                  final speakText = await _extractSpeakText();
                  try {
                    if (speakText.trim().isEmpty) {
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('当前章节没有可朗读内容')),
                      );
                      return;
                    }

                    if (current.useLocalTts) {
                      final availability = await _localTtsModelManager
                          .checkAvailability(current.activeLocalTtsId);
                      if (!availability.success) {
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('本地 TTS 不可用：${availability.message}'),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }
                    } else if (isAndroid && current.useAndroidExternalTts) {
                      final availability = await _androidTtsEngineService
                          .checkAvailability(
                            engine: current.androidExternalTtsEngine,
                            voice: current.androidExternalTtsVoice,
                          );
                      if (!availability.success) {
                        if (!context.mounted) {
                          return;
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Android 外部 TTS 不可用：${availability.message}',
                            ),
                            backgroundColor: Colors.redAccent,
                          ),
                        );
                        return;
                      }
                    }

                    await _runEventTracker.track<void>(
                      action: 'tts.speak',
                      timeout: AppTimeouts.ttsSpeak,
                      context: <String, Object?>{
                        'book_id': widget.book.id,
                        'engine': _currentTtsModeValue(current),
                        'text_len': speakText.length,
                      },
                      isCancelled: () => !context.mounted,
                      operation: () => ttsController.speak(
                        speakText,
                        settings: current,
                        localTtsParams: current.effectiveLocalTtsParamsFor(
                          activeModel,
                        ),
                      ),
                    );
                    if (!context.mounted) {
                      return;
                    }
                    Navigator.pop(context);
                  } finally {
                    if (context.mounted) {
                      setSheetState(() => playInProgress = false);
                    }
                  }
                }

                return SafeArea(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI 朗读',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(modeSummary),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: _currentTtsModeValue(current),
                            decoration: const InputDecoration(
                              labelText: '朗读引擎',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'system',
                                child: Text('系统 TTS'),
                              ),
                              const DropdownMenuItem(
                                value: 'edge',
                                child: Text('Edge TTS'),
                              ),
                              const DropdownMenuItem(
                                value: 'local',
                                child: Text('本地模型'),
                              ),
                              if (isAndroid)
                                const DropdownMenuItem(
                                  value: 'android_external',
                                  child: Text('Android 外部 TTS'),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              final fromMode = _currentTtsModeValue(current);
                              if (value == 'system') {
                                notifier.setEdgeTts(
                                  false,
                                  current.edgeTtsVoice,
                                );
                                notifier.setLocalTts(
                                  false,
                                  current.activeLocalTtsId,
                                );
                                notifier.setAndroidExternalTts(false);
                              } else if (value == 'edge') {
                                notifier.setEdgeTts(true, current.edgeTtsVoice);
                              } else if (value == 'local') {
                                notifier.setLocalTts(
                                  true,
                                  current.activeLocalTtsId,
                                );
                              } else if (value == 'android_external') {
                                notifier.setAndroidExternalTts(
                                  true,
                                  engine: current.androidExternalTtsEngine,
                                  voice: current.androidExternalTtsVoice,
                                );
                              }
                              if (fromMode != value) {
                                unawaited(
                                  AppRunLogService.instance.logEvent(
                                    action: 'tts.switch_engine',
                                    result: 'ok',
                                    context: <String, Object?>{
                                      'book_id': widget.book.id,
                                      'from': fromMode,
                                      'to': value,
                                    },
                                  ),
                                );
                              }
                              setSheetState(() {});
                            },
                          ),
                          if (current.useLocalTts) ...[
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: current.activeLocalTtsId,
                              decoration: const InputDecoration(
                                labelText: '本地模型',
                                border: OutlineInputBorder(),
                              ),
                              items: LocalTtsModelManager.availableModels
                                  .map(
                                    (model) => DropdownMenuItem(
                                      value: model.id,
                                      child: Text(model.name),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                notifier.setLocalTts(true, value);
                                unawaited(
                                  AppRunLogService.instance.logEvent(
                                    action: 'tts.select_local_model',
                                    result: 'ok',
                                    context: <String, Object?>{
                                      'book_id': widget.book.id,
                                      'model_id': value,
                                    },
                                  ),
                                );
                                setSheetState(() {});
                              },
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  context.push('/local-tts');
                                },
                                icon: const Icon(Icons.settings_voice_outlined),
                                label: const Text('管理本地 TTS'),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text('当前状态：${_ttsStateLabel(ttsState.state)}'),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: playInProgress
                                      ? null
                                      : playCurrentSegment,
                                  icon: playInProgress
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.play_arrow),
                                  label: Text(
                                    playInProgress ? '朗读中...' : '开始朗读',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    if (ttsState.state == TtsState.playing) {
                                      await _runEventTracker.track<void>(
                                        action: 'tts.pause',
                                        context: <String, Object?>{
                                          'book_id': widget.book.id,
                                        },
                                        isCancelled: () => !context.mounted,
                                        operation: () => ttsController.pause(),
                                      );
                                    } else if (ttsState.state ==
                                        TtsState.paused) {
                                      await _runEventTracker.track<void>(
                                        action: 'tts.resume',
                                        context: <String, Object?>{
                                          'book_id': widget.book.id,
                                        },
                                        isCancelled: () => !context.mounted,
                                        operation: () => ttsController.resume(),
                                      );
                                    }
                                    if (!context.mounted) {
                                      return;
                                    }
                                    setSheetState(() {});
                                  },
                                  icon: Icon(
                                    ttsState.state == TtsState.playing
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                  ),
                                  label: Text(
                                    ttsState.state == TtsState.playing
                                        ? '暂停'
                                        : '继续',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await _runEventTracker.track<void>(
                                      action: 'tts.stop',
                                      context: <String, Object?>{
                                        'book_id': widget.book.id,
                                      },
                                      isCancelled: () => !context.mounted,
                                      operation: () => ttsController.stop(),
                                    );
                                    if (!context.mounted) {
                                      return;
                                    }
                                    Navigator.pop(context);
                                  },
                                  icon: const Icon(Icons.stop),
                                  label: const Text('停止'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildOverlayProgressBar() {
    final openedFormat = _openedFormat ?? widget.book.format;
    final supported =
        openedFormat == BookFormat.txt ||
        openedFormat == BookFormat.epub ||
        openedFormat == BookFormat.pdf ||
        openedFormat == BookFormat.webnovel ||
        openedFormat == BookFormat.cbz ||
        openedFormat == BookFormat.cbr;
    if (!supported) {
      return const SizedBox.shrink();
    }

    final rawProgress = _currentProgressValue();
    final progress = _isProgressDragging
        ? (_progressDragValue ?? rawProgress).clamp(0.0, 1.0)
        : rawProgress;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.78),
                Colors.transparent,
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _currentSectionTitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  Text(
                    '${(progress * 100).round()}%',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
              Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (value) =>
                    _handleProgressChanged(openedFormat, value),
                onChangeEnd: _handleProgressChangeEnd,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildChapterStatusLabel(BookFormat openedFormat) {
    switch (openedFormat) {
      case BookFormat.webnovel:
        if (_webChapters.isEmpty) {
          return _currentSectionTitle();
        }
        final chapterTitle = sanitizeUiText(
          _currentSectionTitle(),
          fallback: _currentSectionTitle(),
        );
        return '第${_currentWebChapterIndex + 1}/${_webChapters.length}章 · $chapterTitle';
      case BookFormat.pdf:
        if (_pdfPageCount <= 0) {
          return _currentPdfSectionTitle();
        }
        return '第$_pdfPageNumber/$_pdfPageCount页';
      case BookFormat.cbz:
      case BookFormat.cbr:
        final page = _cbzPageController?.hasClients == true
            ? _cbzPageController!.page?.round() ?? 0
            : widget.book.lastPosition;
        if (_comicImagePaths.isEmpty) {
          return '第${page + 1}页';
        }
        return '第${page + 1}/${_comicImagePaths.length}页';
      case BookFormat.txt:
      case BookFormat.epub:
        final chapterTitle = sanitizeUiText(
          _currentSectionTitle(),
          fallback: _currentSectionTitle(),
        );
        if (_txtToc.isNotEmpty) {
          final index = _currentTextTocIndex().clamp(0, _txtToc.length - 1);
          return '第${index + 1}/${_txtToc.length}章 · $chapterTitle';
        }
        if (_textSections.length > 1) {
          return '第${_currentTextSectionIndex + 1}/${_textSections.length}章 · $chapterTitle';
        }
        return chapterTitle;
      default:
        return _currentSectionTitle();
    }
  }

  Widget _buildReaderStatusBar() {
    final openedFormat = _openedFormat ?? widget.book.format;
    final progress = _currentProgressValue().clamp(0.0, 1.0);
    final chapterLabel = _buildChapterStatusLabel(openedFormat).trim();
    final eta = _formatRemainingTime(progress);
    final parts = <String>[
      if (_batteryLevel != null) '电量 ${_batteryLevel!.clamp(0, 100)}%',
      '进度 ${(progress * 100).round()}%',
      if (eta.isNotEmpty) '剩余 $eta',
    ];
    if (chapterLabel.isEmpty && parts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.transparent,
              ],
            ),
          ),
          child: DefaultTextStyle(
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (chapterLabel.isNotEmpty)
                  Text(
                    chapterLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (parts.isNotEmpty)
                  Text(
                    parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _goToAdjacentPage(int delta) async {
    final openedFormat = _openedFormat ?? widget.book.format;
    switch (openedFormat) {
      case BookFormat.txt:
      case BookFormat.epub:
        if (_usesPagedTextView(ref.read(readerSettingsProvider))) {
          final movedWithinSection =
              await _pagedTextViewKey.currentState?.goToAdjacentPage(delta) ??
              false;
          if (movedWithinSection) {
            return true;
          }
          return _goToAdjacentTextSection(delta);
        }
        if (!_txtScrollController.hasClients) {
          return false;
        }
        final viewport = _txtScrollController.position.viewportDimension;
        final target = (_txtScrollController.offset + delta * viewport * 0.88)
            .clamp(0.0, _txtScrollController.position.maxScrollExtent);
        await _txtScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        return true;
      case BookFormat.cbz:
      case BookFormat.cbr:
        final controller = _cbzPageController;
        if (controller == null ||
            !controller.hasClients ||
            _comicImagePaths.isEmpty) {
          return false;
        }
        final currentPage = controller.page?.round() ?? 0;
        final targetPage = (currentPage + delta).clamp(
          0,
          _comicImagePaths.length - 1,
        );
        if (targetPage == currentPage) {
          return false;
        }
        await controller.animateToPage(
          targetPage,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
        return true;
      default:
        return false;
    }
  }

  bool _supportsVolumePaging(ReaderSettings settings) {
    if (detectLocalRuntimePlatform() != LocalRuntimePlatform.android) {
      return false;
    }
    if (!settings.volumeKeyPagingEnabled || settings.readingMode == 'scroll') {
      return false;
    }
    final openedFormat = _openedFormat ?? widget.book.format;
    return openedFormat == BookFormat.txt ||
        openedFormat == BookFormat.epub ||
        openedFormat == BookFormat.cbz ||
        openedFormat == BookFormat.cbr;
  }

  Future<void> _syncVolumePagingHook(ReaderSettings settings) async {
    final shouldEnable = _supportsVolumePaging(settings);
    if (shouldEnable) {
      _volumeKeyEventSubscription ??= _readerVolumeKeyService
          .volumeKeyEvents()
          .listen((event) {
            if (!_supportsVolumePaging(ref.read(readerSettingsProvider))) {
              return;
            }
            if (event == 'volume_up') {
              unawaited(_goToAdjacentPage(-1));
            } else if (event == 'volume_down') {
              unawaited(_goToAdjacentPage(1));
            }
          });
      if (!_volumePagingHookEnabled) {
        _volumePagingHookEnabled = await _readerVolumeKeyService
            .setPagingEnabled(true);
      }
      return;
    }

    await _volumeKeyEventSubscription?.cancel();
    _volumeKeyEventSubscription = null;
    if (_volumePagingHookEnabled) {
      await _readerVolumeKeyService.setPagingEnabled(false);
      _volumePagingHookEnabled = false;
    }
  }

  Future<void> _handleReaderTap(
    Offset position,
    Size viewportSize,
    ReaderSettings settings,
    double dragDistance,
  ) async {
    if (_isProgressDragging) {
      return;
    }
    if (viewportSize.width <= 0) {
      _toggleOverlay();
      return;
    }
    final canTriggerMenu = dragDistance <= _tapMenuDistance;
    final canTriggerPage = dragDistance <= _tapCancelDistance;
    if (settings.tapRegionMode == 'all_menu') {
      if (canTriggerMenu) {
        _toggleOverlay();
      }
      return;
    }

    final openedFormat = _openedFormat ?? widget.book.format;
    final supportsPageTap =
        settings.readingMode != 'scroll' &&
        (openedFormat == BookFormat.txt ||
            openedFormat == BookFormat.epub ||
            openedFormat == BookFormat.cbz ||
            openedFormat == BookFormat.cbr);
    final ratio = position.dx / viewportSize.width;
    if (ratio <= 0.33) {
      if (!supportsPageTap) {
        if (canTriggerMenu) {
          _toggleOverlay();
        }
        return;
      }
      if (!canTriggerPage) {
        return;
      }
      final moved = await _goToAdjacentPage(-1);
      if (_showOverlay && moved) {
        _toggleOverlay();
      }
      if (!moved) {
        _toggleOverlay();
      }
      return;
    }
    if (ratio >= 0.67) {
      if (!supportsPageTap) {
        if (canTriggerMenu) {
          _toggleOverlay();
        }
        return;
      }
      if (!canTriggerPage) {
        return;
      }
      final moved = await _goToAdjacentPage(1);
      if (_showOverlay && moved) {
        _toggleOverlay();
      }
      if (!moved) {
        _toggleOverlay();
      }
      return;
    }
    if (canTriggerMenu) {
      _toggleOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final background = Color(settings.bgColor);
    final openedFormat = _openedFormat ?? widget.book.format;
    final isWebNovel = openedFormat == BookFormat.webnovel;
    final canOpenOrigin =
        isWebNovel &&
        detectLocalRuntimePlatform() == LocalRuntimePlatform.android &&
        (_currentWebBookMeta?.originUrl.trim().isNotEmpty ?? false);
    final isReaderModeBook =
        isWebNovel && _currentWebBookMeta?.sourceId == 'reader_mode';

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  _tapDownPosition = event.localPosition;
                },
                onPointerUp: (event) {
                  final start = _tapDownPosition;
                  if (start == null) {
                    return;
                  }
                  final distance = (event.localPosition - start).distance;
                  _tapDownPosition = null;
                  unawaited(
                    _handleReaderTap(
                      event.localPosition,
                      constraints.biggest,
                      settings,
                      distance,
                    ),
                  );
                },
                onPointerCancel: (_) {
                  _tapDownPosition = null;
                },
                child: _buildBody(settings),
              ),
            ),
          ),
          if (_textJumping || _webChapterLoading)
            Positioned(
              top: _showOverlay ? 56 : 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: _buildNavigationBusyBanner(),
              ),
            ),
          if (_showOverlay)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.72),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          widget.book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _showNavigationSheet,
                        icon: const Icon(Icons.list_alt, color: Colors.white),
                      ),
                      IconButton(
                        onPressed: _addBookmark,
                        icon: const Icon(
                          Icons.bookmark_add_outlined,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: _showReaderAppearanceSettings,
                        icon: const Icon(Icons.tune, color: Colors.white),
                      ),
                      if (isWebNovel)
                        IconButton(
                          onPressed: _cacheRemainingWebNovelChapters,
                          icon: const Icon(
                            Icons.download_for_offline_outlined,
                            color: Colors.white,
                          ),
                        ),
                      if (isReaderModeBook)
                        IconButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已加入书架')),
                            );
                          },
                          icon: const Icon(
                            Icons.library_add_check_outlined,
                            color: Colors.white,
                          ),
                        ),
                      if (canOpenOrigin)
                        IconButton(
                          onPressed: _openOriginWebPage,
                          icon: const Icon(
                            Icons.open_in_browser,
                            color: Colors.white,
                          ),
                        ),
                      IconButton(
                        onPressed: _showTtsPanel,
                        icon: const Icon(
                          Icons.record_voice_over,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_showOverlay) _buildOverlayProgressBar(),
          if (!_showOverlay) _buildReaderStatusBar(),
        ],
      ),
    );
  }

  Widget _buildNavigationBusyBanner() {
    String text;
    if (_webChapterLoading) {
      final targetIndex = _webChapterLoadingIndex;
      if (targetIndex == null ||
          targetIndex < 0 ||
          targetIndex >= _webChapters.length) {
        text = '正在加载章节...';
      } else {
        text = '正在加载 ${_webChapters[targetIndex].title}';
      }
    } else {
      text = '正在跳转章节...';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LinearProgressIndicator(minHeight: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ReaderSettings settings) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    final openedFormat = _openedFormat ?? widget.book.format;

    if (openedFormat == BookFormat.epub || openedFormat == BookFormat.txt) {
      if (_usesPagedTextView(settings)) {
        final section = _activeTextSection();
        return ReaderPagedTextView(
          key: _pagedTextViewKey,
          text: _activeTextSectionText(),
          settings: settings,
          metaText: _metaText,
          initialProgress: _textProgress,
          baseOffset: section.startOffset,
          totalTextLength: _txtContent.length,
          onBoundaryPageRequest: _handlePagedBoundaryRequest,
          onLocationChanged: _handlePagedTextLocationChanged,
        );
      }

      if (_textChunks.isEmpty) {
        if (!_textChunksLoading) {
          unawaited(_ensureTextChunksLoaded());
        }
        return const Center(child: CircularProgressIndicator());
      }

      return _ScrollTextContentView(
        chunks: _textChunks,
        toc: _txtToc,
        settings: settings,
        metaText: _metaText,
        controller: _txtScrollController,
      );
    }
    if (_pdfFilePath != null) {
      final initialPage = _pdfInitialPageNumber
          .clamp(1, math.max(1, _pdfPageCount))
          .toInt();
      return Padding(
        padding: const EdgeInsets.only(top: 56),
        child: PdfViewer.file(
          _pdfFilePath!,
          controller: _pdfViewerController,
          params: PdfViewerParams(
            enableTextSelection: true,
            calculateInitialPageNumber: (document, controller) => initialPage,
            onViewerReady: (document, controller) {
              final pending = _pdfPendingPageNumber;
              if (pending == null) {
                return;
              }
              unawaited(_jumpToPdfPage(pending));
            },
            onPageChanged: (pageNumber) {
              final resolved = (pageNumber ?? initialPage)
                  .clamp(1, math.max(1, _pdfPageCount))
                  .toInt();
              if (resolved == _pdfPageNumber) {
                return;
              }
              _pdfPageNumber = resolved;
              final progress = _pdfPageCount <= 1
                  ? 0.0
                  : ((_pdfPageNumber - 1) / (_pdfPageCount - 1)).clamp(
                      0.0,
                      1.0,
                    );
              _updateEtaBaseline(progress);
              _pdfProgressDebounce?.cancel();
              _pdfProgressDebounce = Timer(
                const Duration(milliseconds: 140),
                () {
                  unawaited(_updateReadingProgress(_pdfPageNumber, progress));
                },
              );
              if (mounted) {
                setState(() {});
              }
            },
          ),
        ),
      );
    }
    if ((openedFormat == BookFormat.cbz || openedFormat == BookFormat.cbr) &&
        _cbzPageController != null) {
      return _CbzContentView(
        imagePaths: _comicImagePaths,
        settings: settings,
        controller: _cbzPageController!,
        onPageChanged: (index) {
          unawaited(
            _updateReadingProgress(
              index,
              _comicImagePaths.length <= 1
                  ? 1
                  : index / (_comicImagePaths.length - 1),
            ),
          );
        },
      );
    }
    if (openedFormat == BookFormat.webnovel) {
      return _WebNovelContentView(
        chapters: _webChapters,
        currentIndex: _currentWebChapterIndex,
        loadingIndex: _webChapterLoadingIndex,
        isChapterLoading: _webChapterLoading,
        content: _currentWebChapterContent,
        settings: settings,
        onSelectChapter: _openWebChapter,
      );
    }

    return const SizedBox.shrink();
  }
}

class _ScrollTextContentView extends StatelessWidget {
  const _ScrollTextContentView({
    required this.chunks,
    required this.toc,
    required this.settings,
    required this.metaText,
    required this.controller,
  });

  final List<String> chunks;
  final List<ReaderTocEntry> toc;
  final ReaderSettings settings;
  final String metaText;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final foreground = Color(settings.fgColor);
    final style = buildReaderTextStyle(settings, color: foreground);
    final paragraphSpacing = resolveReaderParagraphSpacing(settings);
    final textAlign = resolveReaderTextAlign(settings);

    final hasToc = toc.isNotEmpty;
    final chunkOffset = hasToc ? 2 : 1;

    return SelectionArea(
      child: Scrollbar(
        child: ListView.builder(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 72, 20, 32),
          itemCount: chunkOffset + chunks.length,
          itemBuilder: (context, index) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  metaText,
                  style: buildReaderTextStyle(
                    settings,
                    color: foreground.withValues(alpha: 0.6),
                    fontSize: 12,
                    lineHeight: 1.2,
                  ),
                ),
              );
            }

            if (hasToc && index == 1) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: toc
                      .take(12)
                      .map((entry) => Chip(label: Text(entry.title)))
                      .toList(),
                ),
              );
            }

            final chunk = chunks[index - chunkOffset];
            return Padding(
              padding: EdgeInsets.only(bottom: paragraphSpacing),
              child: SelectableText(chunk, style: style, textAlign: textAlign),
            );
          },
        ),
      ),
    );
  }
}

class _ReaderTextSection {
  const _ReaderTextSection({
    required this.title,
    required this.startOffset,
    required this.endOffset,
  });

  final String title;
  final int startOffset;
  final int endOffset;
}

class _CbzContentView extends StatelessWidget {
  const _CbzContentView({
    required this.imagePaths,
    required this.settings,
    required this.controller,
    required this.onPageChanged,
  });

  final List<String> imagePaths;
  final ReaderSettings settings;
  final PageController controller;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color(settings.bgColor),
      child: PageView.builder(
        controller: controller,
        itemCount: imagePaths.length,
        onPageChanged: onPageChanged,
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.file(
                File(imagePaths[index]),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.broken_image_outlined, size: 56);
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WebNovelContentView extends StatelessWidget {
  const _WebNovelContentView({
    required this.chapters,
    required this.currentIndex,
    required this.loadingIndex,
    required this.isChapterLoading,
    required this.content,
    required this.settings,
    required this.onSelectChapter,
  });

  final List<WebChapterRecord> chapters;
  final int currentIndex;
  final int? loadingIndex;
  final bool isChapterLoading;
  final String content;
  final ReaderSettings settings;
  final Future<void> Function(int index) onSelectChapter;

  String _formatParagraphLayout(String raw) {
    final normalized = raw.replaceAll(RegExp(r'\r\n?'), '\n');
    final blocks = normalized
        .split(RegExp(r'\n{2,}'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (blocks.isEmpty) {
      return normalized;
    }
    final separator = switch (settings.paragraphPreset) {
      'compact' => '\n\n',
      'airy' => '\n\n\n\n',
      _ => '\n\n\n',
    };
    return blocks.join(separator);
  }

  @override
  Widget build(BuildContext context) {
    final foreground = Color(settings.fgColor);
    final textAlign = resolveReaderTextAlign(settings);
    final formattedContent = _formatParagraphLayout(content);
    final shownIndex = isChapterLoading
        ? (loadingIndex ?? currentIndex)
        : currentIndex;
    return Column(
      children: [
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 72, 12, 0),
            itemBuilder: (context, index) => ChoiceChip(
              label: Text(chapters[index].title),
              selected: index == shownIndex,
              onSelected: (_) => onSelectChapter(index),
            ),
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemCount: chapters.length,
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isChapterLoading) ...[
                  const LinearProgressIndicator(minHeight: 2),
                  const SizedBox(height: 10),
                  Text(
                    '正在获取章节内容，请稍候…',
                    style: buildReaderTextStyle(
                      settings,
                      color: foreground.withValues(alpha: 0.72),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SelectableText(
                  formattedContent,
                  style: buildReaderTextStyle(settings, color: foreground),
                  textAlign: textAlign,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
