String sanitizeUiText(String raw, {String fallback = ''}) {
  if (raw.isEmpty) {
    return fallback;
  }
  final cleaned = raw
      .replaceAll('\uFFFD', '')
      .replaceAll(RegExp(r'[\u0000-\u001F]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned.isEmpty ? fallback : cleaned;
}
