import 'package:flutter/material.dart';

import 'providers/reader_settings_provider.dart';

String? resolveReaderFontFamily(ReaderSettings settings) {
  return settings.fontFamily == 'default' ? null : settings.fontFamily;
}

TextAlign resolveReaderTextAlign(ReaderSettings settings) {
  switch (settings.textAlignMode) {
    case 'start':
      return TextAlign.start;
    case 'center':
      return TextAlign.center;
    case 'justify':
    default:
      return TextAlign.justify;
  }
}

double resolveReaderParagraphSpacing(ReaderSettings settings) {
  switch (settings.paragraphPreset) {
    case 'compact':
      return 10;
    case 'airy':
      return 22;
    case 'balanced':
    default:
      return 16;
  }
}

({double letterSpacing, double wordSpacing}) _paragraphSpacingMetrics(
  ReaderSettings settings,
) {
  switch (settings.paragraphPreset) {
    case 'compact':
      return (letterSpacing: 0.0, wordSpacing: 0.0);
    case 'airy':
      return (letterSpacing: 0.2, wordSpacing: 0.8);
    case 'balanced':
    default:
      return (letterSpacing: 0.1, wordSpacing: 0.35);
  }
}

TextStyle buildReaderTextStyle(
  ReaderSettings settings, {
  required Color color,
  double? fontSize,
  double? lineHeight,
  FontWeight? fontWeight,
}) {
  final spacing = _paragraphSpacingMetrics(settings);
  return TextStyle(
    fontSize: fontSize ?? settings.fontSize,
    height: lineHeight ?? settings.lineHeight,
    color: color,
    fontFamily: resolveReaderFontFamily(settings),
    fontWeight: fontWeight,
    letterSpacing: spacing.letterSpacing,
    wordSpacing: spacing.wordSpacing,
  );
}
