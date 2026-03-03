import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 阅读器设置数据类
class ReaderSettings {
  final double fontSize;       // 12–32
  final double lineHeight;     // 1.0–2.5
  final String fontFamily;     // 'default' | 'serif' | 'sans-serif' | 'monospace'
  final int backgroundIndex;   // 0=白, 1=米黄, 2=夜黑, 3=护眼绿
  final bool nightMode;

  static const backgrounds = [
    (bg: 0xFFFFFFFF, fg: 0xFF1A1A1A),  // 白天
    (bg: 0xFFF4ECD8, fg: 0xFF3D2B1F),  // 米黄
    (bg: 0xFF1A1A2E, fg: 0xFFE0E0E0),  // 夜黑
    (bg: 0xFFD6EFC7, fg: 0xFF2D4A1E),  // 护眼绿
  ];

  const ReaderSettings({
    this.fontSize = 17,
    this.lineHeight = 1.8,
    this.fontFamily = 'default',
    this.backgroundIndex = 0,
    this.nightMode = false,
  });

  int get bgColor => backgrounds[backgroundIndex].bg;
  int get fgColor => backgrounds[backgroundIndex].fg;

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    int? backgroundIndex,
    bool? nightMode,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    lineHeight: lineHeight ?? this.lineHeight,
    fontFamily: fontFamily ?? this.fontFamily,
    backgroundIndex: backgroundIndex ?? this.backgroundIndex,
    nightMode: nightMode ?? this.nightMode,
  );

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'fontFamily': fontFamily,
    'backgroundIndex': backgroundIndex,
    'nightMode': nightMode,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> j) => ReaderSettings(
    fontSize: (j['fontSize'] as num?)?.toDouble() ?? 17,
    lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.8,
    fontFamily: j['fontFamily'] ?? 'default',
    backgroundIndex: j['backgroundIndex'] ?? 0,
    nightMode: j['nightMode'] ?? false,
  );
}

/// 阅读器设置 Notifier（持久化到本地 JSON）
class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  late File _file;

  @override
  ReaderSettings build() {
    _init();
    return const ReaderSettings();
  }

  Future<void> _init() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/wenwen_tome/reader_settings.json');
    if (await _file.exists()) {
      try {
        final s = ReaderSettings.fromJson(jsonDecode(await _file.readAsString()));
        state = s;
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(jsonEncode(state.toJson()));
  }

  void setFontSize(double v)        { state = state.copyWith(fontSize: v); _save(); }
  void setLineHeight(double v)      { state = state.copyWith(lineHeight: v); _save(); }
  void setFontFamily(String v)      { state = state.copyWith(fontFamily: v); _save(); }
  void setBackground(int idx)       { state = state.copyWith(backgroundIndex: idx); _save(); }
  void toggleNightMode()            { state = state.copyWith(nightMode: !state.nightMode); _save(); }
}

final readerSettingsProvider = NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
  ReaderSettingsNotifier.new,
);
