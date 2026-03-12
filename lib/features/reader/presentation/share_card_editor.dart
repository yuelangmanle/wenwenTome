import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/storage/app_storage_paths.dart';
import '../../library/data/book_model.dart';

class ShareCardEditor extends StatefulWidget {
  const ShareCardEditor({
    super.key,
    required this.book,
    required this.selectedText,
  });

  final Book book;
  final String selectedText;

  @override
  State<ShareCardEditor> createState() => _ShareCardEditorState();
}

class _ShareCardEditorState extends State<ShareCardEditor> {
  final GlobalKey _globalKey = GlobalKey();
  Color _bgColor = Colors.blueGrey.shade900;
  final Color _fgColor = Colors.white;
  bool _isRendering = false;

  Future<void> _shareImage() async {
    setState(() => _isRendering = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final boundary =
          _globalKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final tempDir = await getSafeTemporaryDirectory();
      final file = File('${tempDir.path}/share_quote.png');
      await file.writeAsBytes(pngBytes, flush: true);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: '来自《${widget.book.title}》的金句分享',
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('分享失败: $error')));
    } finally {
      if (mounted) {
        setState(() => _isRendering = false);
      }
    }
  }

  void _pickBgColor() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('选择背景色'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: _bgColor,
            availableColors: const <Color>[
              Colors.red,
              Colors.pink,
              Colors.purple,
              Colors.deepPurple,
              Colors.indigo,
              Colors.blue,
              Colors.lightBlue,
              Colors.cyan,
              Colors.teal,
              Colors.green,
              Colors.lightGreen,
              Colors.orange,
              Colors.deepOrange,
              Colors.brown,
              Colors.grey,
              Colors.blueGrey,
            ],
            onColorChanged: (color) => setState(() => _bgColor = color),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '金句卡片分享',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RepaintBoundary(
                key: _globalKey,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: _bgColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.format_quote,
                        color: Colors.white54,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        widget.selectedText,
                        style: TextStyle(
                          fontSize: 20,
                          color: _fgColor,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '《${widget.book.title}》',
                                style: TextStyle(
                                  color: _fgColor.withValues(alpha: 0.8),
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.book.author,
                                style: TextStyle(
                                  color: _fgColor.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickBgColor,
                  icon: const Icon(Icons.color_lens),
                  label: const Text('更换背景'),
                ),
                FilledButton.icon(
                  onPressed: _isRendering ? null : _shareImage,
                  icon: _isRendering
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.share),
                  label: const Text('分享卡片'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
