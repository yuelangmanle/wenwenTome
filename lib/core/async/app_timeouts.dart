class AppTimeouts {
  static const Duration readerOpenBook = Duration(seconds: 60);
  static const Duration readerOpenWebChapter = Duration(seconds: 30);
  static const Duration readerSeekProgress = Duration(seconds: 20);

  static const Duration ttsSpeak = Duration(seconds: 45);

  static const Duration webnovelRequestPage = Duration(seconds: 20);
  static const Duration webnovelCacheForegroundWait = Duration(seconds: 45);
}

