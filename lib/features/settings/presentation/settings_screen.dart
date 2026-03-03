import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../webnovel/scraper_service.dart';

/// 应用全局设置页面
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _obsidianPathCtrl = TextEditingController();
  String _translateTo = 'zh';
  bool _useLocalTranslate = false;
  bool _autoFetchMeta = true;

  @override
  void dispose() {
    _obsidianPathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: ListView(
        children: [
          // ── 同步设置 ──
          _SectionHeader('🔄 同步'),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: const Text('Obsidian Vault 路径'),
            subtitle: Text(_obsidianPathCtrl.text.isEmpty ? '未设置' : _obsidianPathCtrl.text,
                overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickObsidianPath,
          ),
          const Divider(height: 1),

          // ── 翻译设置 ──
          _SectionHeader('🌍 全书翻译'),
          SwitchListTile(
            secondary: const Icon(Icons.dns_outlined),
            title: const Text('使用本地 LibreTranslate'),
            subtitle: const Text('需要在本地运行 LibreTranslate 服务器'),
            value: _useLocalTranslate,
            onChanged: (v) => setState(() => _useLocalTranslate = v),
          ),
          ListTile(
            leading: const Icon(Icons.translate),
            title: const Text('翻译目标语言'),
            trailing: DropdownButton<String>(
              value: _translateTo,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                DropdownMenuItem(value: 'zh-TW', child: Text('繁体中文')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'ja', child: Text('日本語')),
              ],
              onChanged: (v) => setState(() => _translateTo = v ?? 'zh'),
            ),
          ),
          const Divider(height: 1),

          // ── 元数据设置 ──
          _SectionHeader('📚 书库元数据'),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_download_outlined),
            title: const Text('导入时自动补全元数据'),
            subtitle: const Text('从豆瓣/OpenLibrary 获取书名、封面和标签'),
            value: _autoFetchMeta,
            onChanged: (v) => setState(() => _autoFetchMeta = v),
          ),
          const Divider(height: 1),

          // ── 网文抓取 ──
          _SectionHeader('📡 网文抓取'),
          ListTile(
            leading: const Icon(Icons.rss_feed),
            title: const Text('书源管理'),
            subtitle: Text('已加载 ${WebNovelScraper.builtinSources.length} 个内置书源'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showSourcesDialog(context),
          ),
          const Divider(height: 1),

          // ── 关于 ──
          _SectionHeader('ℹ️ 关于'),
          ListTile(
            leading: const Icon(Icons.info_outlined),
            title: const Text('文文Tome'),
            subtitle: const Text('版本 1.0.0-MVP · 本地优先电子书解决方案'),
          ),
          const ListTile(
            leading: Icon(Icons.favorite_outline, color: Colors.redAccent),
            title: Text('完全本地，无广告，数据归你所有'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickObsidianPath() async {
    // 简化：弹出文字输入对话框
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: _obsidianPathCtrl.text);
        return AlertDialog(
          title: const Text('Obsidian Vault 路径'),
          content: TextField(controller: c, decoration: const InputDecoration(
            hintText: 'C:\\Users\\你\\Documents\\MyVault',
          )),
          actions: [
            TextButton(child: const Text('取消'), onPressed: () => Navigator.pop(ctx)),
            TextButton(
              child: const Text('保存'),
              onPressed: () => Navigator.pop(ctx, c.text),
            ),
          ],
        );
      },
    );
    if (res != null) setState(() => _obsidianPathCtrl.text = res);
  }

  void _showSourcesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('内置书源'),
        content: SizedBox(
          width: 320,
          child: ListView(
            shrinkWrap: true,
            children: WebNovelScraper.builtinSources.map((s) => ListTile(
              leading: const Icon(Icons.rss_feed),
              title: Text(s.name),
              subtitle: Text(s.baseUrl),
            )).toList(),
          ),
        ),
        actions: [TextButton(child: const Text('关闭'), onPressed: () => Navigator.pop(ctx))],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(title, style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 13,
        color: Theme.of(context).colorScheme.primary,
      )),
    );
  }
}
