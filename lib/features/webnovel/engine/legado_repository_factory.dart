import '../../../app/runtime_platform.dart';
import '../webnovel_repository.dart';
import 'legado_repository_bridge.dart';

WebNovelRepositoryHandle createDefaultWebNovelRepositoryHandle({
  LocalRuntimePlatform? platform,
}) {
  final resolvedPlatform = platform ?? detectLocalRuntimePlatform();
  if (resolvedPlatform == LocalRuntimePlatform.android) {
    return LegadoRepositoryBridge(platform: resolvedPlatform);
  }
  return WebNovelRepository();
}
