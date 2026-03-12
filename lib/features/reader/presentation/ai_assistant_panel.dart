import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../settings/providers/global_settings_provider.dart';
import '../../translation/translation_service.dart';

class AiAssistantDrawer extends ConsumerStatefulWidget {
  final String? initialText; // 从阅读器高亮划选进来的初始文本

  const AiAssistantDrawer({super.key, this.initialText});

  @override
  ConsumerState<AiAssistantDrawer> createState() => _AiAssistantDrawerState();
}

class _AiAssistantDrawerState extends ConsumerState<AiAssistantDrawer> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _service = TranslationService();
  
  final List<Map<String, String>> _messages = [];
  bool _isWaiting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _textCtrl.text = '请解释以下段落或名词：\n\n"${widget.initialText}"';
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    _service.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage([String? quickPrompt]) async {
    final text = quickPrompt ?? _textCtrl.text.trim();
    if (text.isEmpty || _isWaiting) return;

    _textCtrl.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _messages.add({'role': 'assistant', 'content': ''});
      _isWaiting = true;
    });
    _scrollToBottom();

    final globalState = ref.read(globalSettingsProvider);
    final configs = globalState.translationConfigs;
    final config = configs.isEmpty
        ? null
        : configs.firstWhere(
            (c) => c.id == globalState.translationConfigId,
            orElse: () => configs.first,
          );

    try {
      final stream = _service.askAiStream(
        systemPrompt: '你是强大的文文Tome阅读AI助手，你不仅会翻译，还可以帮助用户总结剧情、解释专长词汇、整理知识点。请用通俗易懂的中文回答。',
        userPrompt: text,
        config: config,
      );

      await for (final chunk in stream) {
        if (!mounted) break;
        setState(() {
          _messages.last['content'] = _messages.last['content']! + chunk;
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.last['content'] = '请求出错：$e\n请检查大模型配置或网络状态。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWaiting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    
    return Drawer(
      width: 320,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  const Text('AI 助手', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
            ),
            const Divider(height: 1),
            // Message List
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Text(
                        '有什么我可以帮忙的吗？\n例如：主角背景、名词解释等',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final isUser = msg['role'] == 'user';
                        return Align(
                          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isUser ? cs.primaryContainer : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16).copyWith(
                                bottomRight: isUser ? const Radius.circular(0) : null,
                                bottomLeft: !isUser ? const Radius.circular(0) : null,
                              ),
                            ),
                            child: SelectableText(
                              msg['content']!.isEmpty && _isWaiting && !isUser ? '思考中...' : msg['content']!,
                              style: TextStyle(
                                color: isUser ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            // Shortcut Buttons
            if (_messages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      label: const Text('总结本章'),
                      onPressed: () => _sendMessage('请为我总结一下这一章的主要情感基调与剧情进展要点。'),
                    ),
                    ActionChip(
                      label: const Text('介绍核心设定'),
                      onPressed: () => _sendMessage('在你看过的书中，能为我梳理一下网文的常见势力设定吗？'),
                    ),
                  ],
                ),
              ),
            // Input Box
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      maxLines: 3,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: '问点什么...',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: _isWaiting ? Colors.grey : cs.primary,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                      onPressed: _isWaiting ? null : _sendMessage,
                    ),
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
