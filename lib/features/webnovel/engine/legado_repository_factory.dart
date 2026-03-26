import '../../../app/runtime_platform.dart';
import '../webnovel_repository.dart';

WebNovelRepositoryHandle createDefaultWebNovelRepositoryHandle({
  LocalRuntimePlatform? platform,
}) {
  final _ = platform;
  return WebNovelRepository();
}
