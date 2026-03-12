# 2026-03-09 Release Verification

Target release: `2.3.0+21`

## Scope

- Desktop scope reduction to bookshelf, sync, source-file management, runtime logs, and changelog
- Mobile webnovel flow stabilization with bundled source pack
- Large-source import deduplication and broad Legado compatibility
- Mobile "all sources" search throttling and bulk fallback behavior

## Desktop Manual Checks

- Launch Windows build and confirm bottom navigation only shows bookshelf, sync, and settings
- Open settings and confirm update log entry still opens `CHANGELOG.md`
- Open the desktop source-file page and verify import, export, copy JSON, enable/disable, and test-source actions still work
- Open an existing book from the desktop bookshelf and confirm the book still opens normally

## Android Manual Checks

- Install the release APK on a real device
- Open the webnovel page without manually importing any source pack and confirm search is immediately available
- Run one search in "全部书源" mode and confirm the page remains responsive
- Add one search result to the bookshelf and confirm the book can be opened from the shelf
- Verify translation and TTS pages still open and their basic checks/buttons respond

## Release Gating

- `flutter analyze lib/features/webnovel/webnovel_repository.dart lib/features/webnovel/presentation/webnovel_screen.dart test/webnovel_source_pack_compat_test.dart test/webnovel_repository_test.dart test/webnovel_screen_test.dart`
- `flutter test`
- `powershell -ExecutionPolicy Bypass -File scripts/build_android.ps1`
- `powershell -ExecutionPolicy Bypass -File scripts/build_win.ps1`
- Confirm APK, Windows installer, and `release_notes.md` are present in `releases/2.3.0/`

## Known Follow-Up Risks

- The bundled source pack itself contains a small number of duplicate definitions; current verification accepts low double-digit duplication after dedup
- A portion of imported Legado rules still rely on preserved-but-not-fully-executed advanced fields such as more complex JS hooks
- Real-device network quality still affects cross-site search hit rate more than parser compatibility now does
