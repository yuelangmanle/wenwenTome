import 'package:flutter_open_chinese_convert/flutter_open_chinese_convert.dart';

/// 简繁转换本地服务封装
class ChineseConversionService {
  /// 转换文本内容
  /// [mode] 支持 'none', 't2s', 's2t', 'tw2s', 's2tw'
  static Future<String> convert(String text, String mode) async {
    if (text.isEmpty || mode == 'none') return text;

    ConverterOption option;
    switch (mode) {
      case 't2s':
        option = T2S();
        break;
      case 's2t':
        option = S2T();
        break;
      case 'tw2s':
        option = TW2S();
        break;
      case 's2tw':
        option = S2TW();
        break;
      default:
        return text;
    }

    return await ChineseConverter.convert(text, option);
  }

  /// 转换文本列表（如多章节标题）
  static Future<List<String>> convertList(List<String> texts, String mode) async {
    if (texts.isEmpty || mode == 'none') return texts;
    final futures = texts.map((t) => convert(t, mode));
    return await Future.wait(futures);
  }
}
