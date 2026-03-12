import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_storage_paths.dart';
import '../custom_font_manager.dart';
import '../local_tts_model_manager.dart';

const Object _readerSettingsUnset = Object();

class ReaderSettings {
  const ReaderSettings({
    this.fontSize = 17,
    this.lineHeight = 1.8,
    this.fontFamily = 'default',
    this.customFontFamily,
    this.customFontPath,
    this.customFontName,
    this.backgroundIndex = 0,
    this.nightMode = false,
    this.dualPage = false,
    this.chineseConversion = 'none',
    this.translationMode = 'original',
    this.readingMode = 'paged',
    this.pageAnimation = 'sheet',
    this.tapRegionMode = 'center_menu',
    this.volumeKeyPagingEnabled = false,
    this.textAlignMode = 'justify',
    this.paragraphPreset = 'balanced',
    this.customBgColor,
    this.customFgColor,
    this.useEdgeTts = false,
    this.edgeTtsVoice = 'zh-CN-XiaoxiaoNeural',
    this.useLocalTts = false,
    this.useAndroidExternalTts = false,
    this.androidExternalTtsEngine = '',
    this.androidExternalTtsVoice = const {},
    this.activeLocalTtsId = LocalTtsModelManager.piperModelId,
    this.ttsRate = 1.0,
    this.ttsPitch = 1.0,
    this.localTtsParamsByModel = const {},
  });

  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final String? customFontFamily;
  final String? customFontPath;
  final String? customFontName;
  final int backgroundIndex;
  final bool nightMode;
  final bool dualPage;
  final String chineseConversion;
  final String translationMode;
  final String readingMode;
  final String pageAnimation;
  final String tapRegionMode;
  final bool volumeKeyPagingEnabled;
  final String textAlignMode;
  final String paragraphPreset;
  final int? customBgColor;
  final int? customFgColor;
  final bool useEdgeTts;
  final String edgeTtsVoice;
  final bool useLocalTts;
  final bool useAndroidExternalTts;
  final String androidExternalTtsEngine;
  final Map<String, String> androidExternalTtsVoice;
  final String activeLocalTtsId;
  final double ttsRate;
  final double ttsPitch;
  final Map<String, Map<String, double>> localTtsParamsByModel;

  static const backgrounds = [
    (bg: 0xFFFFFFFF, fg: 0xFF1A1A1A),
    (bg: 0xFFF4ECD8, fg: 0xFF3D2B1F),
    (bg: 0xFF1A1A2E, fg: 0xFFE0E0E0),
    (bg: 0xFFD6EFC7, fg: 0xFF2D4A1E),
  ];

  int get bgColor =>
      customBgColor ??
      backgrounds[backgroundIndex.clamp(0, backgrounds.length - 1)].bg;

  int get fgColor =>
      customFgColor ??
      backgrounds[backgroundIndex.clamp(0, backgrounds.length - 1)].fg;

  Map<String, double> effectiveLocalTtsParamsFor(TtsModelConfig model) {
    final defaults = <String, double>{};
    for (final def in model.paramDefs) {
      defaults[def.key] = def.defaultValue;
    }

    final stored = localTtsParamsByModel[model.id] ?? const <String, double>{};
    return {...defaults, ...stored};
  }

  ReaderSettings copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    Object? customFontFamily = _readerSettingsUnset,
    Object? customFontPath = _readerSettingsUnset,
    Object? customFontName = _readerSettingsUnset,
    int? backgroundIndex,
    bool? nightMode,
    bool? dualPage,
    String? chineseConversion,
    String? translationMode,
    String? readingMode,
    String? pageAnimation,
    String? tapRegionMode,
    bool? volumeKeyPagingEnabled,
    String? textAlignMode,
    String? paragraphPreset,
    Object? customBgColor = _readerSettingsUnset,
    Object? customFgColor = _readerSettingsUnset,
    bool? useEdgeTts,
    String? edgeTtsVoice,
    bool? useLocalTts,
    bool? useAndroidExternalTts,
    String? androidExternalTtsEngine,
    Map<String, String>? androidExternalTtsVoice,
    String? activeLocalTtsId,
    double? ttsRate,
    double? ttsPitch,
    Map<String, Map<String, double>>? localTtsParamsByModel,
  }) {
    return ReaderSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      customFontFamily: identical(customFontFamily, _readerSettingsUnset)
          ? this.customFontFamily
          : customFontFamily as String?,
      customFontPath: identical(customFontPath, _readerSettingsUnset)
          ? this.customFontPath
          : customFontPath as String?,
      customFontName: identical(customFontName, _readerSettingsUnset)
          ? this.customFontName
          : customFontName as String?,
      backgroundIndex: backgroundIndex ?? this.backgroundIndex,
      nightMode: nightMode ?? this.nightMode,
      dualPage: dualPage ?? this.dualPage,
      chineseConversion: chineseConversion ?? this.chineseConversion,
      translationMode: translationMode ?? this.translationMode,
      readingMode: readingMode ?? this.readingMode,
      pageAnimation: pageAnimation ?? this.pageAnimation,
      tapRegionMode: tapRegionMode ?? this.tapRegionMode,
      volumeKeyPagingEnabled:
          volumeKeyPagingEnabled ?? this.volumeKeyPagingEnabled,
      textAlignMode: textAlignMode ?? this.textAlignMode,
      paragraphPreset: paragraphPreset ?? this.paragraphPreset,
      customBgColor: identical(customBgColor, _readerSettingsUnset)
          ? this.customBgColor
          : customBgColor as int?,
      customFgColor: identical(customFgColor, _readerSettingsUnset)
          ? this.customFgColor
          : customFgColor as int?,
      useEdgeTts: useEdgeTts ?? this.useEdgeTts,
      edgeTtsVoice: edgeTtsVoice ?? this.edgeTtsVoice,
      useLocalTts: useLocalTts ?? this.useLocalTts,
      useAndroidExternalTts:
          useAndroidExternalTts ?? this.useAndroidExternalTts,
      androidExternalTtsEngine:
          androidExternalTtsEngine ?? this.androidExternalTtsEngine,
      androidExternalTtsVoice:
          androidExternalTtsVoice ?? this.androidExternalTtsVoice,
      activeLocalTtsId: activeLocalTtsId ?? this.activeLocalTtsId,
      ttsRate: ttsRate ?? this.ttsRate,
      ttsPitch: ttsPitch ?? this.ttsPitch,
      localTtsParamsByModel:
          localTtsParamsByModel ?? this.localTtsParamsByModel,
    );
  }

  Map<String, dynamic> toJson() => {
    'fontSize': fontSize,
    'lineHeight': lineHeight,
    'fontFamily': fontFamily,
    'customFontFamily': customFontFamily,
    'customFontPath': customFontPath,
    'customFontName': customFontName,
    'backgroundIndex': backgroundIndex,
    'nightMode': nightMode,
    'dualPage': dualPage,
    'chineseConversion': chineseConversion,
    'translationMode': translationMode,
    'readingMode': readingMode,
    'pageAnimation': pageAnimation,
    'tapRegionMode': tapRegionMode,
    'volumeKeyPagingEnabled': volumeKeyPagingEnabled,
    'textAlignMode': textAlignMode,
    'paragraphPreset': paragraphPreset,
    'customBgColor': customBgColor,
    'customFgColor': customFgColor,
    'useEdgeTts': useEdgeTts,
    'edgeTtsVoice': edgeTtsVoice,
    'useLocalTts': useLocalTts,
    'useAndroidExternalTts': useAndroidExternalTts,
    'androidExternalTtsEngine': androidExternalTtsEngine,
    'androidExternalTtsVoice': androidExternalTtsVoice,
    'activeLocalTtsId': activeLocalTtsId,
    'ttsRate': ttsRate,
    'ttsPitch': ttsPitch,
    'localTtsParamsByModel': localTtsParamsByModel.map(
      (modelId, params) => MapEntry(modelId, params),
    ),
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) {
    var pageAnimation = json['pageAnimation'] as String? ?? 'sheet';
    if (pageAnimation == 'flip') {
      pageAnimation = 'sheet';
    } else if (pageAnimation == 'turn2') {
      pageAnimation = 'page_curl';
    }
    final rawParams =
        json['localTtsParamsByModel'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final params = <String, Map<String, double>>{};
    for (final entry in rawParams.entries) {
      final value = entry.value;
      if (value is Map) {
        params[entry.key] = value.map(
          (key, item) => MapEntry(key.toString(), (item as num).toDouble()),
        );
      }
    }

    final rawAndroidVoice =
        json['androidExternalTtsVoice'] as Map<String, dynamic>? ??
        const <String, dynamic>{};
    final androidVoice = <String, String>{
      for (final entry in rawAndroidVoice.entries)
        entry.key: entry.value.toString(),
    };

    return ReaderSettings(
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 17,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.8,
      fontFamily: json['fontFamily'] as String? ?? 'default',
      customFontFamily: json['customFontFamily'] as String?,
      customFontPath: json['customFontPath'] as String?,
      customFontName: json['customFontName'] as String?,
      backgroundIndex: json['backgroundIndex'] as int? ?? 0,
      nightMode: json['nightMode'] as bool? ?? false,
      dualPage: json['dualPage'] as bool? ?? false,
      chineseConversion: json['chineseConversion'] as String? ?? 'none',
      translationMode: json['translationMode'] as String? ?? 'original',
      readingMode: json['readingMode'] as String? ?? 'paged',
      pageAnimation: pageAnimation,
      tapRegionMode: json['tapRegionMode'] as String? ?? 'center_menu',
      volumeKeyPagingEnabled: json['volumeKeyPagingEnabled'] as bool? ?? false,
      textAlignMode: json['textAlignMode'] as String? ?? 'justify',
      paragraphPreset: json['paragraphPreset'] as String? ?? 'balanced',
      customBgColor: json['customBgColor'] as int?,
      customFgColor: json['customFgColor'] as int?,
      useEdgeTts: json['useEdgeTts'] as bool? ?? false,
      edgeTtsVoice: json['edgeTtsVoice'] as String? ?? 'zh-CN-XiaoxiaoNeural',
      useLocalTts: json['useLocalTts'] as bool? ?? false,
      useAndroidExternalTts: json['useAndroidExternalTts'] as bool? ?? false,
      androidExternalTtsEngine:
          json['androidExternalTtsEngine'] as String? ?? '',
      androidExternalTtsVoice: androidVoice,
      activeLocalTtsId:
          json['activeLocalTtsId'] as String? ??
          LocalTtsModelManager.piperModelId,
      ttsRate: (json['ttsRate'] as num?)?.toDouble() ?? 1.0,
      ttsPitch: (json['ttsPitch'] as num?)?.toDouble() ?? 1.0,
      localTtsParamsByModel: params,
    );
  }
}

class ReaderSettingsNotifier extends Notifier<ReaderSettings> {
  File? _file;

  @override
  ReaderSettings build() {
    _init();
    return const ReaderSettings();
  }

  Future<void> _init() async {
    final dir = await getSafeApplicationDocumentsDirectory();
    _file = File('${dir.path}/wenwen_tome/reader_settings.json');
    if (await _file!.exists()) {
      try {
        final json =
            jsonDecode(await _file!.readAsString()) as Map<String, dynamic>;
        final loaded = ReaderSettings.fromJson(json);
        state = loaded;
        await _restoreCustomFont(loaded);
      } catch (_) {
        state = const ReaderSettings();
      }
    }
  }

  Future<void> _restoreCustomFont(ReaderSettings settings) async {
    final customFontPath = settings.customFontPath;
    final customFontFamily = settings.customFontFamily;
    if (customFontPath == null ||
        customFontPath.trim().isEmpty ||
        customFontFamily == null ||
        customFontFamily.trim().isEmpty) {
      return;
    }

    final loaded = await ReaderCustomFontManager.ensureFontLoaded(
      path: customFontPath,
      family: customFontFamily,
    );
    if (!loaded) {
      state = state.copyWith(
        fontFamily: 'default',
        customFontFamily: null,
        customFontPath: null,
        customFontName: null,
      );
      await _save();
    }
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(state.toJson()));
  }

  void setFontSize(double value) {
    state = state.copyWith(fontSize: value);
    _save();
  }

  void setLineHeight(double value) {
    state = state.copyWith(lineHeight: value);
    _save();
  }

  void setFontFamily(String value) {
    state = state.copyWith(fontFamily: value);
    _save();
  }

  void setBackground(int index) {
    state = state.copyWith(
      backgroundIndex: index,
      customBgColor: null,
      customFgColor: null,
    );
    _save();
  }

  void toggleNightMode() {
    state = state.copyWith(nightMode: !state.nightMode);
    _save();
  }

  void toggleDualPage() {
    state = state.copyWith(dualPage: !state.dualPage);
    _save();
  }

  void setChineseConversion(String value) {
    state = state.copyWith(chineseConversion: value);
    _save();
  }

  void setTranslationMode(String value) {
    state = state.copyWith(translationMode: value);
    _save();
  }

  void setReadingMode(String value) {
    state = state.copyWith(readingMode: value);
    _save();
  }

  void setPageAnimation(String value) {
    final mapped = value == 'flip'
        ? 'sheet'
        : value == 'turn2'
        ? 'page_curl'
        : value;
    state = state.copyWith(pageAnimation: mapped);
    _save();
  }

  void setTapRegionMode(String value) {
    state = state.copyWith(tapRegionMode: value);
    _save();
  }

  void setVolumeKeyPagingEnabled(bool enabled) {
    state = state.copyWith(volumeKeyPagingEnabled: enabled);
    _save();
  }

  void setTextAlignMode(String value) {
    state = state.copyWith(textAlignMode: value);
    _save();
  }

  void setParagraphPreset(String value) {
    state = state.copyWith(paragraphPreset: value);
    _save();
  }

  void setCustomColors(int bg, int fg) {
    state = state.copyWith(
      customBgColor: bg,
      customFgColor: fg,
      backgroundIndex: 0,
    );
    _save();
  }

  void clearCustomColors() {
    state = state.copyWith(customBgColor: null, customFgColor: null);
    _save();
  }

  Future<ImportedReaderFont?> importCustomFont() async {
    final imported = await ReaderCustomFontManager.pickAndImportFont();
    if (imported == null) {
      return null;
    }
    state = state.copyWith(
      fontFamily: imported.family,
      customFontFamily: imported.family,
      customFontPath: imported.path,
      customFontName: imported.displayName,
    );
    await _save();
    return imported;
  }

  void clearCustomFont() {
    state = state.copyWith(
      fontFamily: 'default',
      customFontFamily: null,
      customFontPath: null,
      customFontName: null,
    );
    _save();
  }

  void setEdgeTts(bool use, String voice) {
    state = state.copyWith(
      useEdgeTts: use,
      edgeTtsVoice: voice,
      useLocalTts: false,
      useAndroidExternalTts: false,
    );
    _save();
  }

  void setLocalTts(bool use, String modelId) {
    state = state.copyWith(
      useLocalTts: use,
      activeLocalTtsId: modelId,
      useEdgeTts: false,
      useAndroidExternalTts: false,
    );
    _save();
  }

  void setAndroidExternalTts(
    bool use, {
    String? engine,
    Map<String, String>? voice,
  }) {
    state = state.copyWith(
      useAndroidExternalTts: use,
      androidExternalTtsEngine: engine ?? state.androidExternalTtsEngine,
      androidExternalTtsVoice: voice ?? state.androidExternalTtsVoice,
      useLocalTts: false,
      useEdgeTts: false,
    );
    _save();
  }

  void setAndroidExternalTtsEngine(String engine) {
    state = state.copyWith(
      androidExternalTtsEngine: engine,
      androidExternalTtsVoice: const <String, String>{},
    );
    _save();
  }

  void setAndroidExternalTtsVoice(Map<String, String> voice) {
    state = state.copyWith(androidExternalTtsVoice: voice);
    _save();
  }

  void setTtsRate(double value) {
    state = state.copyWith(ttsRate: value);
    _save();
  }

  void setTtsPitch(double value) {
    state = state.copyWith(ttsPitch: value);
    _save();
  }

  void setLocalTtsParam(String modelId, String key, double value) {
    final next = <String, Map<String, double>>{
      for (final entry in state.localTtsParamsByModel.entries)
        entry.key: Map<String, double>.from(entry.value),
    };
    final params = next.putIfAbsent(modelId, () => <String, double>{});
    params[key] = value;
    state = state.copyWith(localTtsParamsByModel: next);
    _save();
  }
}

final readerSettingsProvider =
    NotifierProvider<ReaderSettingsNotifier, ReaderSettings>(
      ReaderSettingsNotifier.new,
    );
