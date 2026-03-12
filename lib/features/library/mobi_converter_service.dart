import 'dart:io';

class MobiConvertResult {
  const MobiConvertResult({
    required this.outputPath,
    required this.usedExistingOutput,
  });

  final String outputPath;
  final bool usedExistingOutput;
}

class MobiConvertFailure implements Exception {
  const MobiConvertFailure(
    this.message, {
    this.code = 'unknown',
    this.details = '',
  });

  final String code;
  final String message;
  final String details;

  @override
  String toString() {
    if (details.trim().isEmpty) {
      return message;
    }
    return '$message\n$details';
  }
}

class MobiConverterService {
  static const _toolName = 'ebook-convert';

  /// 调用本机 Calibre CLI (ebook-convert) 将 MOBI/AZW3 转换为 EPUB。
  ///
  /// 约定：
  /// - 输出文件名：`*_converted.epub`（与既有实现保持兼容）
  /// - 如已存在同名输出且大小>0，则直接复用
  /// - 失败会抛出 [MobiConvertFailure]，包含可解释原因与建议
  static Future<MobiConvertResult?> convertToEpub(String inputPath) async {
    final lower = inputPath.toLowerCase();
    if (!lower.endsWith('.mobi') && !lower.endsWith('.azw3')) {
      return null;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      throw const MobiConvertFailure(
        '当前平台不支持自动转换 MOBI/AZW3（需要 Calibre）',
        code: 'unsupported_platform',
        details: '建议：在电脑上用 Calibre 转成 EPUB/TXT 后再导入。',
      );
    }

    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      throw const MobiConvertFailure('源文件不存在或不可读取', code: 'input_missing');
    }

    final outPathSeg = inputPath.split('.');
    outPathSeg.removeLast();
    final outPath = '${outPathSeg.join('.')}_converted.epub';
    final outFile = File(outPath);

    if (outFile.existsSync()) {
      try {
        final stat = outFile.statSync();
        if (stat.size > 0) {
          return MobiConvertResult(outputPath: outPath, usedExistingOutput: true);
        }
      } catch (_) {}
    }

    Future<ProcessResult> runConvert() {
      return Process.run(_toolName, <String>[inputPath, outPath]);
    }

    ProcessResult res;
    try {
      res = await runConvert();
    } on ProcessException catch (e) {
      throw MobiConvertFailure(
        '未找到转换工具：$_toolName（需要安装 Calibre）',
        code: 'tool_not_found',
        details:
            '系统错误：${e.message}\n'
            '建议：安装 Calibre 后重试；或先在电脑上把 MOBI/AZW3 转成 EPUB/TXT 再导入。',
      );
    } catch (e) {
      throw MobiConvertFailure(
        '调用转换工具失败',
        code: 'tool_invoke_failed',
        details: e.toString(),
      );
    }

    final stdoutText = (res.stdout ?? '').toString().trim();
    final stderrText = (res.stderr ?? '').toString().trim();

    if (res.exitCode == 0 && outFile.existsSync()) {
      try {
        if (outFile.statSync().size > 0) {
          return MobiConvertResult(outputPath: outPath, usedExistingOutput: false);
        }
      } catch (_) {}
    }

    final combined = <String>[
      if (stdoutText.isNotEmpty) 'stdout:\n$stdoutText',
      if (stderrText.isNotEmpty) 'stderr:\n$stderrText',
      'exitCode: ${res.exitCode}',
    ].join('\n');

    final lowerCombined = combined.toLowerCase();
    if (lowerCombined.contains('drm') ||
        lowerCombined.contains('kfx') ||
        lowerCombined.contains('encrypted')) {
      throw MobiConvertFailure(
        '该文件可能受 DRM/加密保护，无法自动转换',
        code: 'drm_or_encrypted',
        details:
            '$combined\n'
            '建议：确认文件未加密；或在 Calibre 中先完成解密/转换（若你有合法权限）。',
      );
    }

    throw MobiConvertFailure(
      'MOBI/AZW3 自动转换失败',
      code: 'convert_failed',
      details:
          '$combined\n'
          '建议：打开 Calibre 查看更详细日志；或先转换为 EPUB/TXT 再导入。',
    );
  }
}
