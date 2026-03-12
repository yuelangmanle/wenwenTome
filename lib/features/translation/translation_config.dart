class TranslationConfig {
  const TranslationConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.modelName,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String modelName;

  factory TranslationConfig.create({
    required String name,
    required String baseUrl,
    required String apiKey,
    required String modelName,
  }) {
    final stamp = DateTime.now().microsecondsSinceEpoch.toString();
    return TranslationConfig(
      id: 'custom-$stamp',
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      modelName: modelName,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'modelName': modelName,
      };

  factory TranslationConfig.fromJson(Map<String, dynamic> json) {
    return TranslationConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String,
      modelName: json['modelName'] as String,
    );
  }

  TranslationConfig copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? modelName,
  }) {
    return TranslationConfig(
      id: id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      modelName: modelName ?? this.modelName,
    );
  }
}

const defaultTranslationConfigs = <TranslationConfig>[
  TranslationConfig(
    id: 'deepseek-default',
    name: 'DeepSeek（默认）',
    baseUrl: 'https://api.deepseek.com/v1',
    apiKey: '',
    modelName: 'deepseek-chat',
  ),
  TranslationConfig(
    id: 'qwen-default',
    name: '通义千问',
    baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    apiKey: '',
    modelName: 'qwen-plus',
  ),
];
