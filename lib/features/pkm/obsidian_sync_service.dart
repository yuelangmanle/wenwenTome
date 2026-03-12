import 'dart:io';
import '../annotations/annotation_service.dart';

/// Obsidian PKM 双向同步服务
/// 将书籍笔记导出为 Obsidian Markdown 格式
class ObsidianSyncService {
  final String vaultPath;    // Obsidian Vault 根目录路径
  const ObsidianSyncService({required this.vaultPath});

  /// 将书籍的所有高亮/笔记导出到 Obsidian Vault
  Future<String> exportBookNotes({
    required String bookId,
    required String bookTitle,
    required String bookAuthor,
    required List<Annotation> annotations,
    required List<Bookmark> bookmarks,
  }) async {
    final buffer = StringBuffer();

    // YAML Front Matter
    buffer.writeln('---');
    buffer.writeln('title: "$bookTitle"');
    buffer.writeln('author: "$bookAuthor"');
    buffer.writeln('type: book-notes');
    buffer.writeln('created: ${DateTime.now().toIso8601String().split('T').first}');
    buffer.writeln('source: WenwenTome');
    buffer.writeln('tags:');
    buffer.writeln('  - 读书笔记');
    buffer.writeln('  - 文文Tome');
    buffer.writeln('---');
    buffer.writeln();

    // 书籍基本信息
    buffer.writeln('# $bookTitle');
    buffer.writeln('> **作者：** $bookAuthor');
    buffer.writeln();

    // 高亮笔记
    if (annotations.isNotEmpty) {
      buffer.writeln('## 📝 高亮与笔记');
      buffer.writeln();
      for (final a in annotations) {
        // 颜色 callout
        final calloutType = _colorToCallout(a.color);
        buffer.writeln('> [!$calloutType]');
        buffer.writeln('> ${a.selectedText}');
        if (a.note != null && a.note!.isNotEmpty) {
          buffer.writeln();
          buffer.writeln('**笔记：** ${a.note}');
        }
        buffer.writeln();
      }
    }

    // 书签
    if (bookmarks.isNotEmpty) {
      buffer.writeln('## 🔖 书签');
      buffer.writeln();
      for (final bm in bookmarks) {
        buffer.writeln('- [[${bm.title}]] — 位置 ${bm.position}');
      }
      buffer.writeln();
    }

    // 写入 Vault
    final safeTitle = bookTitle.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    final notesDir = Directory('$vaultPath/WenwenTome');
    await notesDir.create(recursive: true);
    final filePath = '${notesDir.path}/$safeTitle.md';
    await File(filePath).writeAsString(buffer.toString());
    return filePath;
  }

  /// 导出所有书籍的笔记摘要索引
  Future<void> exportIndex(List<Map<String, String>> books) async {
    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.writeln('title: 文文Tome 书库索引');
    buffer.writeln('type: book-index');
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('# 📚 我的书架');
    buffer.writeln();
    for (final b in books) {
      final title = b['title'] ?? '未知';
      final safeTitle = title.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
      buffer.writeln('- [[$safeTitle]] — ${b['author'] ?? ''}');
    }
    await File('$vaultPath/WenwenTome/Index.md').writeAsString(buffer.toString());
  }

  String _colorToCallout(HighlightColor color) {
    switch (color) {
      case HighlightColor.yellow: return 'quote';
      case HighlightColor.green:  return 'tip';
      case HighlightColor.blue:   return 'info';
      case HighlightColor.pink:   return 'warning';
      case HighlightColor.purple: return 'abstract';
    }
  }
}
