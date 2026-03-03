import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:epub_view/epub_view.dart';
import 'package:pdfx/pdfx.dart';
import '../../library/data/book_model.dart';
import '../../annotations/annotation_service.dart';
import '../../annotations/presentation/annotations_screen.dart';
import '../../search/presentation/search_screen.dart';
import '../providers/reader_settings_provider.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});
  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with SingleTickerProviderStateMixin {
  EpubController? _epubController;
  PdfControllerPinch? _pdfController;
  bool _isLoading = true;
  String? _error;
  bool _showUI = true;
  late AnimationController _uiAnimCtrl;
  late Animation<double> _uiAnim;

  @override
  void initState() {
    super.initState();
    _uiAnimCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _uiAnim = CurvedAnimation(parent: _uiAnimCtrl, curve: Curves.easeInOut);
    _uiAnimCtrl.value = 1;
    _initReader();
  }

  Future<void> _initReader() async {
    try {
      switch (widget.book.format) {
        case BookFormat.epub:
          _epubController = EpubController(
            document: EpubDocument.openFile(File(widget.book.filePath)),
          );
          break;
        case BookFormat.pdf:
          _pdfController = PdfControllerPinch(
            document: PdfDocument.openFile(widget.book.filePath),
          );
          break;
        default:
          setState(() => _error = '暂不支持此格式的直接渲染');
          return;
      }
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() { _error = '无法打开文件：$e'; _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _epubController?.dispose();
    _pdfController?.dispose();
    _uiAnimCtrl.dispose();
    super.dispose();
  }

  void _toggleUI() {
    setState(() => _showUI = !_showUI);
    if (_showUI) {
      _uiAnimCtrl.forward();
    } else {
      _uiAnimCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(readerSettingsProvider);
    final bgColor = Color(settings.bgColor);

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        onTap: _toggleUI,
        child: Stack(
          children: [
            _buildContent(settings),
            FadeTransition(opacity: _uiAnim, child: _buildTopBar(context)),
            FadeTransition(opacity: _uiAnim, child: _buildBottomBar(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ReaderSettings settings) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.orange),
          const SizedBox(height: 16),
          Text(_error!, textAlign: TextAlign.center),
        ]),
      ));
    }
    if (_epubController != null) {
      return EpubView(controller: _epubController!);
    }
    if (_pdfController != null) {
      return PdfViewPinch(controller: _pdfController!);
    }
    return const SizedBox();
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withValues(alpha: 0.65), Colors.transparent],
            ),
          ),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context)),
              Expanded(child: Text(widget.book.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
              // 书内搜索
              IconButton(
                icon: const Icon(Icons.search, color: Colors.white),
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => SearchScreen(book: widget.book))),
              ),
              // 添加书签
              IconButton(
                icon: const Icon(Icons.bookmark_outline, color: Colors.white),
                onPressed: () async {
                  await AnnotationService().addBookmark(
                    bookId: widget.book.id,
                    title: '书签 · ${widget.book.title}',
                    position: 0,
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('书签已添加 🔖'),
                          duration: Duration(seconds: 1)));
                  }
                },
              ),
              // 查看笔记
              IconButton(
                icon: const Icon(Icons.sticky_note_2_outlined, color: Colors.white),
                onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => AnnotationsScreen(
                    bookId: widget.book.id, bookTitle: widget.book.title))),
              ),
              // 阅读设置
              IconButton(
                icon: const Icon(Icons.text_fields, color: Colors.white),
                onPressed: _showFontSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    // 阅读进度条（仅 EPUB 显示）
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: SafeArea(
        child: Container(
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [Colors.black.withValues(alpha: 0.5), Colors.transparent],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: LinearProgressIndicator(
              value: widget.book.readingProgress,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary.withValues(alpha: 0.9)),
              minHeight: 2,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }

  void _showFontSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ReaderSettingsSheet(bookId: widget.book.id),
    );
  }
}

// ── 阅读设置面板 ──
class _ReaderSettingsSheet extends ConsumerWidget {
  final String bookId;
  const _ReaderSettingsSheet({required this.bookId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(readerSettingsProvider);
    final notifier = ref.read(readerSettingsProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          const Text('阅读设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          // 字号
          Row(children: [
            const SizedBox(width: 4),
            const Icon(Icons.format_size, size: 18),
            const SizedBox(width: 8),
            Text('字号  ${settings.fontSize.round()}', style: const TextStyle(fontSize: 13)),
            Expanded(child: Slider(
              value: settings.fontSize, min: 12, max: 32, divisions: 10,
              onChanged: notifier.setFontSize,
            )),
          ]),

          // 行距
          Row(children: [
            const SizedBox(width: 4),
            const Icon(Icons.format_line_spacing, size: 18),
            const SizedBox(width: 8),
            Text('行距  ${settings.lineHeight.toStringAsFixed(1)}', style: const TextStyle(fontSize: 13)),
            Expanded(child: Slider(
              value: settings.lineHeight, min: 1.0, max: 2.5, divisions: 6,
              onChanged: notifier.setLineHeight,
            )),
          ]),

          // 背景色
          const SizedBox(height: 8),
          const Text('背景色', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(children: [
            for (int i = 0; i < ReaderSettings.backgrounds.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => notifier.setBackground(i),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Color(ReaderSettings.backgrounds[i].bg),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: settings.backgroundIndex == i
                            ? cs.primary : cs.outlineVariant,
                        width: settings.backgroundIndex == i ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            // 夜间模式开关
            Row(children: [
              const Icon(Icons.dark_mode_outlined, size: 18),
              const SizedBox(width: 4),
              Switch(
                value: settings.nightMode,
                onChanged: (_) => notifier.toggleNightMode(),
              ),
            ]),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
