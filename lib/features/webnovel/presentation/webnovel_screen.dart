import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/webnovel/scraper_service.dart';

/// 网文抓取界面 - 搜索 + 章节浏览
class WebNovelScreen extends ConsumerStatefulWidget {
  const WebNovelScreen({super.key});

  @override
  ConsumerState<WebNovelScreen> createState() => _WebNovelScreenState();
}

class _WebNovelScreenState extends ConsumerState<WebNovelScreen> {
  final _queryCtrl = TextEditingController();
  final _scraper = WebNovelScraper();
  List<Map<String, String>> _searchResults = [];
  List<WebChapter> _chapters = [];
  bool _searching = false;
  String? _selectedSource;
  String? _selectedBook;

  @override
  void initState() {
    super.initState();
    _selectedSource = WebNovelScraper.builtinSources.first.name;
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _scraper.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_queryCtrl.text.trim().isEmpty) return;
    setState(() { _searching = true; _searchResults = []; _chapters = []; });
    final results = await _scraper.search(_selectedSource!, _queryCtrl.text);
    setState(() { _searchResults = results; _searching = false; });
  }

  Future<void> _loadChapters(Map<String, String> book) async {
    setState(() { _selectedBook = book['title']; _chapters = []; _searching = true; });
    final chapters = await _scraper.fetchChapterList(_selectedSource!, book['url']!);
    setState(() { _chapters = chapters; _searching = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网文抓取', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(children: [
              // 书源选择
              DropdownButton<String>(
                value: _selectedSource,
                underline: const SizedBox(),
                items: WebNovelScraper.builtinSources.map((s) =>
                    DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
                onChanged: (v) => setState(() => _selectedSource = v),
              ),
              const SizedBox(width: 8),
              // 搜索框
              Expanded(child: TextField(
                controller: _queryCtrl,
                decoration: InputDecoration(
                  hintText: '搜索书名...',
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onSubmitted: (_) => _search(),
              )),
              const SizedBox(width: 8),
              IconButton(icon: const Icon(Icons.search), onPressed: _search),
            ]),
          ),
        ),
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _chapters.isNotEmpty
              ? _buildChapterList()
              : _buildSearchResults(),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Center(child: Text('搜索网文，点击书名查看章节列表 →',
          style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) {
        final book = _searchResults[i];
        return ListTile(
          leading: const Icon(Icons.menu_book),
          title: Text(book['title'] ?? ''),
          onTap: () => _loadChapters(book),
        );
      },
    );
  }

  Widget _buildChapterList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: () =>
                setState(() { _chapters = []; _selectedBook = null; })),
            Text(_selectedBook ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('共 ${_chapters.length} 章', style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _chapters.length,
            itemBuilder: (ctx, i) {
              final ch = _chapters[i];
              return ListTile(
                dense: true,
                title: Text(ch.title),
                trailing: const Icon(Icons.arrow_forward_ios, size: 12),
                onTap: () => _openChapter(ch),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openChapter(WebChapter chapter) async {
    final content = await _scraper.fetchChapterContent(_selectedSource!, chapter.url);
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _ChapterReader(title: chapter.title, content: content),
    ));
  }
}

class _ChapterReader extends StatelessWidget {
  final String title;
  final String content;
  const _ChapterReader({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
      body: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 60),
          child: SelectableText(
            content,
            style: const TextStyle(fontSize: 17, height: 1.8),
          ),
        ),
      ),
    );
  }
}
