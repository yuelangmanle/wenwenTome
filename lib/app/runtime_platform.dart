import 'dart:io';

enum LocalRuntimePlatform {
  windows,
  android,
  other,
}

LocalRuntimePlatform detectLocalRuntimePlatform() {
  if (Platform.isWindows) {
    return LocalRuntimePlatform.windows;
  }
  if (Platform.isAndroid) {
    return LocalRuntimePlatform.android;
  }
  return LocalRuntimePlatform.other;
}
