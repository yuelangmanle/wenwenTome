import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../translation/translation_config.dart';

final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

class GlobalSettings {
  const GlobalSettings({
    this.obsidianPath = '',
    this.translateTo = 'zh',
    this.autoFetchMeta = true,
    this.translationConfigs = const [],
    this.translationConfigId = '',
    this.enableWebFallbackInBookSearch = false,
    this.autoDetectReaderMode = true,
    this.enableAiSearchBoost = false,
    this.aiSourceRepairMode = 'off',
    this.searchConcurrency = 6,
  });

  final String obsidianPath;
  final String translateTo;
  final bool autoFetchMeta;
  final List<TranslationConfig> translationConfigs;
  final String translationConfigId;
  final bool enableWebFallbackInBookSearch;
  final bool autoDetectReaderMode;
  final bool enableAiSearchBoost;
  final String aiSourceRepairMode;
  final int searchConcurrency;

  GlobalSettings copyWith({
    String? obsidianPath,
    String? translateTo,
    bool? autoFetchMeta,
    List<TranslationConfig>? translationConfigs,
    String? translationConfigId,
    bool? enableWebFallbackInBookSearch,
    bool? autoDetectReaderMode,
    bool? enableAiSearchBoost,
    String? aiSourceRepairMode,
    int? searchConcurrency,
  }) {
    return GlobalSettings(
      obsidianPath: obsidianPath ?? this.obsidianPath,
      translateTo: translateTo ?? this.translateTo,
      autoFetchMeta: autoFetchMeta ?? this.autoFetchMeta,
      translationConfigs: translationConfigs ?? this.translationConfigs,
      translationConfigId: translationConfigId ?? this.translationConfigId,
      enableWebFallbackInBookSearch:
          enableWebFallbackInBookSearch ?? this.enableWebFallbackInBookSearch,
      autoDetectReaderMode: autoDetectReaderMode ?? this.autoDetectReaderMode,
      enableAiSearchBoost: enableAiSearchBoost ?? this.enableAiSearchBoost,
      aiSourceRepairMode: aiSourceRepairMode ?? this.aiSourceRepairMode,
      searchConcurrency: searchConcurrency ?? this.searchConcurrency,
    );
  }
}

class GlobalSettingsNotifier extends Notifier<GlobalSettings> {
  SharedPreferences? _prefs;

  @override
  GlobalSettings build() {
    _prefs = ref.watch(sharedPreferencesProvider);

    final prefs = _prefs;
    final configsStr = prefs?.getString('translationConfigs');
    var configs = <TranslationConfig>[];
    if (configsStr != null && configsStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(configsStr) as List<dynamic>;
        configs = decoded
            .map(
              (item) =>
                  TranslationConfig.fromJson(item as Map<String, dynamic>),
            )
            .toList();
      } catch (_) {
        configs = <TranslationConfig>[];
      }
    }
    if (configs.isEmpty) {
      configs = List<TranslationConfig>.from(defaultTranslationConfigs);
    }

    // Migration: local translation entry is deprecated and no longer provided by default.
    // Keep user configs intact, but if the selected id points to the legacy default, fall back.
    final legacyLocalTranslate = prefs?.getBool('useLocalTranslate') ?? false;
    if (legacyLocalTranslate) {
      prefs?.setBool('useLocalTranslate', false);
    }

    var currentConfigId = prefs?.getString('translationConfigId') ?? '';
    var migratedConfigId = false;
    if (currentConfigId.isEmpty ||
        !configs.any((config) => config.id == currentConfigId)) {
      currentConfigId = configs.first.id;
      migratedConfigId = true;
    }
    if (migratedConfigId) {
      prefs?.setString('translationConfigId', currentConfigId);
    }

    return GlobalSettings(
      obsidianPath: prefs?.getString('obsidianPath') ?? '',
      translateTo: prefs?.getString('translateTo') ?? 'zh',
      autoFetchMeta: prefs?.getBool('autoFetchMeta') ?? true,
      translationConfigs: configs,
      translationConfigId: currentConfigId,
      enableWebFallbackInBookSearch:
          prefs?.getBool('enableWebFallbackInBookSearch') ?? false,
      autoDetectReaderMode:
          prefs?.getBool('autoDetectReaderMode') ?? true,
      enableAiSearchBoost: prefs?.getBool('enableAiSearchBoost') ?? false,
      aiSourceRepairMode: prefs?.getString('aiSourceRepairMode') ?? 'off',
      searchConcurrency: prefs?.getInt('searchConcurrency') ?? 6,
    );
  }

  void setObsidianPath(String path) {
    _prefs?.setString('obsidianPath', path);
    state = state.copyWith(obsidianPath: path);
  }

  void setTranslateTo(String value) {
    _prefs?.setString('translateTo', value);
    state = state.copyWith(translateTo: value);
  }

  void setAutoFetchMeta(bool value) {
    _prefs?.setBool('autoFetchMeta', value);
    state = state.copyWith(autoFetchMeta: value);
  }

  void setTranslationConfigs(List<TranslationConfig> configs) {
    final encoded = jsonEncode(configs.map((item) => item.toJson()).toList());
    _prefs?.setString('translationConfigs', encoded);
    state = state.copyWith(translationConfigs: configs);
  }

  void setTranslationConfigId(String id) {
    _prefs?.setString('translationConfigId', id);
    state = state.copyWith(translationConfigId: id);
  }

  void setEnableWebFallbackInBookSearch(bool value) {
    _prefs?.setBool('enableWebFallbackInBookSearch', value);
    state = state.copyWith(enableWebFallbackInBookSearch: value);
  }

  void setAutoDetectReaderMode(bool value) {
    _prefs?.setBool('autoDetectReaderMode', value);
    state = state.copyWith(autoDetectReaderMode: value);
  }

  void setEnableAiSearchBoost(bool value) {
    _prefs?.setBool('enableAiSearchBoost', value);
    state = state.copyWith(enableAiSearchBoost: value);
  }

  void setAiSourceRepairMode(String value) {
    _prefs?.setString('aiSourceRepairMode', value);
    state = state.copyWith(aiSourceRepairMode: value);
  }

  void setSearchConcurrency(int value) {
    final normalized = value.clamp(1, 24);
    _prefs?.setInt('searchConcurrency', normalized);
    state = state.copyWith(searchConcurrency: normalized);
  }
}

final globalSettingsProvider =
    NotifierProvider<GlobalSettingsNotifier, GlobalSettings>(
      GlobalSettingsNotifier.new,
    );
