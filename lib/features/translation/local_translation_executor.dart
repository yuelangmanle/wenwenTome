abstract class LocalTranslationExecutor {
  Future<LocalTranslationCheckResult> checkAvailability();

  Future<LocalTranslationCheckResult> prepare() => checkAvailability();

  Future<void> dispose() async {}

  Future<String> translate(
    String text, {
    required String sourceLang,
    required String targetLang,
  });
}

class LocalTranslationCheckResult {
  const LocalTranslationCheckResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}
