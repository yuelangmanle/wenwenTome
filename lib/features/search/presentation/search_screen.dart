import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../library/data/book_model.dart';
import '../../library/providers/library_providers.dart';
import '../search_service.dart';

/// 全文搜索界面
class SearchScreen extends ConsumerStatefulWidget {
  final Book? book; // 若传入则搜索单本书，否则搜索整个书库
  const SearchScreen({super.key, this.book});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  List<SearchResult> _results = [];
  Map<String, String> _bookTitles = {};
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    try {
      List<SearchResult> results = [];
      if (widget.book != null) {
        results = await FullTextSearch.searchInBook(widget.book!, query);
        _bookTitles = {widget.book!.id: widget.book!.title};
      } else {
        final books = await ref.read(booksProvider.future);
        final titles = <String, String>{};
        for (final book in books) {
          titles[book.id] = book.title;
          final partial = await FullTextSearch.searchInBook(book, query);
          results.addAll(partial);
          if (results.length >= 200) break;
        }
        _bookTitles = titles;
      }
      setState(() => _results = results);
    } finally {
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: widget.book != null
                ? '在《${widget.book!.title}》中搜索...'
                : '在书库中搜索...',
            border: InputBorder.none,
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
          ),
          style: const TextStyle(fontSize: 16),
          onSubmitted: _search,
          onChanged: (q) {
            if (q.isEmpty) setState(() => _results = []);
          },
        ),
        actions: [
          if (_controller.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () => _search(_controller.text),
            ),
        ],
      ),
      body: _searching
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
              ? _buildHint()
              : _buildResults(),
    );
  }

  Widget _buildHint() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.search, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('输入关键词，按回车搜索', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text('找到 ${_results.length} 条结果',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: _results.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (ctx, i) => _ResultTile(
              result: _results[i],
              query: _controller.text,
              bookTitle: _bookTitles[_results[i].bookId],
            ),
          ),
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  final SearchResult result;
  final String query;
  final String? bookTitle;
  const _ResultTile({required this.result, required this.query, this.bookTitle});

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.copyWith(fontSize: 13, height: 1.5);
    final spans = _buildHighlightedSpans(result.excerpt, query, style);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: RichText(text: TextSpan(children: spans)),
      subtitle: Text(
        bookTitle == null
            ? '位置: ${result.position}'
            : '《$bookTitle》 · 位置: ${result.position}',
        style: const TextStyle(fontSize: 11),
      ),
      onTap: () => Navigator.pop(context, result),
    );
  }

  List<TextSpan> _buildHighlightedSpans(String text, String query, TextStyle base) {
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final lowerQ = query.toLowerCase();
    int idx = 0;

    while (true) {
      final found = lower.indexOf(lowerQ, idx);
      if (found == -1) {
        spans.add(TextSpan(text: text.substring(idx), style: base));
        break;
      }
      if (found > idx) spans.add(TextSpan(text: text.substring(idx, found), style: base));
      spans.add(TextSpan(
        text: text.substring(found, found + query.length),
        style: base.copyWith(
          backgroundColor: Colors.yellow.withValues(alpha: 0.6),
          fontWeight: FontWeight.bold,
        ),
      ));
      idx = found + query.length;
    }
    return spans;
  }
}
