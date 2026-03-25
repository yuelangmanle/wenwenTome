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
    final isAndroid = platform == LocalRuntimePlatform.android;
    final isWindows = platform == LocalRuntimePlatform.windows;

    if (isAndroid && (format == BookFormat.epub || format == BookFormat.txt)) {
      return const ReaderEnginePlan(
        primary: ReaderEngineKind.foliateJs,
        migrationPhase: 'approved',
        notes: 'Android local-book reading is migrating to foliate-js.',
      );
    }

    if (isAndroid && format == BookFormat.webnovel) {
      return const ReaderEnginePlan(
        primary: ReaderEngineKind.legadoIntegration,
        migrationPhase: 'approved',
        notes: 'Android webnovel capability is migrating to Legado integration.',
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
