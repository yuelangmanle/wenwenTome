import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../logging/app_run_log_service.dart';
import '../../logging/runtime_log_actions.dart';

class RuntimeLogScreen extends StatefulWidget {
  const RuntimeLogScreen({
    super.key,
    this.service,
    this.pickExportPath,
    this.shareFile,
  });

  final AppRunLogService? service;
  final Future<String?> Function(String suggestedFileName)? pickExportPath;
  final Future<void> Function(String filePath)? shareFile;

  @override
  State<RuntimeLogScreen> createState() => _RuntimeLogScreenState();
}

class _RuntimeLogScreenState extends State<RuntimeLogScreen> {
  late final AppRunLogService _service;
  late final RuntimeLogActions _actions;
  String _content = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AppRunLogService.instance;
    _actions = RuntimeLogActions(_service);
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final content = await _service.readAll();
      if (!mounted) return;
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _content = '';
        _loading = false;
      });
    }
  }

  Future<String?> _defaultPickExportPath(String suggestedFileName) {
    return FilePicker.platform.saveFile(
      dialogTitle: '选择日志导出路径',
      fileName: suggestedFileName,
      type: FileType.custom,
      allowedExtensions: ['log', 'txt'],
    );
  }

  Future<void> _defaultShareFile(String filePath) {
    return SharePlus.instance.share(
      ShareParams(files: [XFile(filePath)], text: '文文Tome 运行日志'),
    );
  }

  Future<void> _exportToSelectedPath() async {
    try {
      final picker = widget.pickExportPath ?? _defaultPickExportPath;
      final path = await _actions.exportWithPathPicker(pickPath: picker);
      if (path == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出成功：$path')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$error')),
      );
    }
  }

  Future<void> _shareLog() async {
    try {
      final share = widget.shareFile ?? _defaultShareFile;
      await _actions.shareWith(shareFile: share);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败：$error')),
      );
    }
  }

  Future<void> _clearLog() async {
    try {
      await _actions.clear();
      await _reload();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('清空失败：$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('运行日志'),
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _exportToSelectedPath,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('导出到文件'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _shareLog,
                        icon: const Icon(Icons.ios_share),
                        label: const Text('一键分享'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _clearLog,
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('清空日志'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _content.trim().isEmpty
                      ? const Center(child: Text('暂无运行日志'))
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            _content,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12.5,
                              height: 1.5,
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
