import '../../../app/runtime_platform.dart';
import '../../library/data/book_model.dart';

enum ReaderEngineKind {
  legacyFlutter,
  foliateJs,
  legadoIntegration,
}

class ReaderEnginePlan {
  const ReaderEnginePlan({
    required this.primary,
    required this.migrationPhase,
    required this.notes,
  });

  final ReaderEngineKind primary;
  final String migrationPhase;
  final String notes;

  static ReaderEnginePlan forBook({
    required BookFormat format,
    required LocalRuntimePlatform platform,
  }) {
    final isWindows = platform == LocalRuntimePlatform.windows;

    if (platform == LocalRuntimePlatform.android &&
        (format == BookFormat.epub || format == BookFormat.txt)) {
      return const ReaderEnginePlan(
        primary: ReaderEngineKind.foliateJs,
        migrationPhase: 'embedded_host',
        notes:
            'Android local-book reading uses the embedded foliate-js host served from localhost.',
      );
    }

    if (platform == LocalRuntimePlatform.android &&
        format == BookFormat.webnovel) {
      return const ReaderEnginePlan(
        primary: ReaderEngineKind.legacyFlutter,
        migrationPhase: 'paused',
        notes:
            'Android webnovel stays on the in-app repository until Legado integration no longer depends on an external app/service.',
      );
    }

    if (isWindows) {
      return const ReaderEnginePlan(
        primary: ReaderEngineKind.legacyFlutter,
        migrationPhase: 'shell_only',
        notes: 'Windows stays as backup and management shell during migration.',
      );
    }

    return const ReaderEnginePlan(
      primary: ReaderEngineKind.legacyFlutter,
      migrationPhase: 'fallback',
      notes: 'Legacy Flutter reader remains the current fallback path.',
    );
  }
}
