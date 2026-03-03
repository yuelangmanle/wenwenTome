import 'dart:io';
import 'package:flutter/material.dart';
import 'package:epub_view/epub_view.dart';
import 'package:pdfx/pdfx.dart';
import '../../library/data/book_model.dart';

class ReaderScreen extends StatefulWidget {
  final Book book;
  const ReaderScreen({super.key, required this.book});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  // EPUB 控制器
  EpubController? _epubController;
  // PDF 控制器
  PdfControllerPinch? _pdfController;

  bool _isLoading = true;
  String? _error;
  bool _showUI = true; // 沉浸模式开关

  @override
  void initState() {
    super.initState();
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
          setState(() => _error = '暂不支持此格式的直接渲染，即将支持...');
          return;
      }
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = '无法打开文件：$e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _epubController?.dispose();
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        child: Stack(
          children: [
            _buildContent(),
            if (_showUI) _buildTopBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.orange),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
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
              colors: [
                Colors.black.withValues(alpha: 0.6),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  widget.book.title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
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

  void _showFontSettings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => const _FontSettingsSheet(),
    );
  }
}

class _FontSettingsSheet extends StatelessWidget {
  const _FontSettingsSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('阅读设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          const Text('字号', style: TextStyle(color: Colors.grey)),
          Slider(value: 18, min: 12, max: 32, divisions: 10,
              label: '18', onChanged: (_) {}),
          const SizedBox(height: 8),
          const Text('行距', style: TextStyle(color: Colors.grey)),
          Slider(value: 1.5, min: 1.0, max: 2.5, divisions: 6,
              label: '1.5', onChanged: (_) {}),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
