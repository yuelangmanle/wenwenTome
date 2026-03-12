# Stability And Model Delivery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the app usable end-to-end by fixing model delivery, reader import/open flows, API configuration UX, and runtime logging, then ship installable APK and EXE builds.

**Architecture:** Replace the fake multi-engine local TTS shell with a real Piper-based matrix: one bundled Piper runtime + one bundled Chinese voice + three downloadable Piper voice packs with official and mirror sources. Route reader playback directly from persisted reader settings into the synthesis layer so model mounting and parameter tuning actually affect output. Keep translation model delivery separate with verified official/mirror downloads and explicit health checks.

**Tech Stack:** Flutter, Riverpod, Dart IO, http, archive, file_picker, path_provider, Inno Setup, Flutter Windows runner.

### Task 1: Lock regression tests for import and model policy

**Files:**
- Modify: `test/import_and_download_policy_test.dart`
- Create: `test/local_tts_configuration_test.dart`
- Create: `test/library_import_open_test.dart`

**Step 1: Write the failing tests**

- Assert local TTS exposes four models total.
- Assert bundled Piper has no download URLs.
- Assert every downloadable TTS model has both official and mirror URLs.
- Assert reader settings can persist active local model and per-model parameters.
- Assert import-copy mode persists source bytes into app storage and keeps supported suffixes.

**Step 2: Run tests to verify they fail**

Run: `flutter test test/import_and_download_policy_test.dart test/local_tts_configuration_test.dart test/library_import_open_test.dart`

Expected: FAIL because the current implementation only exposes one TTS model and does not persist per-model parameters.

**Step 3: Write minimal implementation**

- Expand TTS model metadata.
- Add per-model parameter persistence to reader settings.
- Tighten import storage behavior.

**Step 4: Run tests to verify they pass**

Run the same `flutter test ...` command.

### Task 2: Deliver real Piper model management

**Files:**
- Modify: `lib/features/reader/local_tts_model_manager.dart`
- Modify: `lib/features/reader/local_tts_runner.dart`
- Modify: `lib/features/reader/tts_service.dart`
- Modify: `lib/features/reader/providers/reader_settings_provider.dart`

**Step 1: Write the failing tests**

- Assert downloadable Piper voice packs resolve to valid official/mirror URLs.
- Assert synthesized Piper command arguments include persisted parameters for the selected model.

**Step 2: Run test to verify it fails**

Run: `flutter test test/local_tts_configuration_test.dart`

Expected: FAIL because current TTS service ignores mounted model state and custom parameters.

**Step 3: Write minimal implementation**

- Add bundled/downloadable Piper voice definitions.
- Download and install voice files into deterministic directories.
- Generate real Piper CLI arguments from persisted parameters.
- Remove duplicated engine state from TTS service and read from `ReaderSettings`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/local_tts_configuration_test.dart`

### Task 3: Fix reader import/open path

**Files:**
- Modify: `lib/features/library/data/library_service.dart`
- Modify: `lib/features/library/providers/library_providers.dart`
- Modify: `lib/features/library/presentation/library_screen.dart`
- Modify: `lib/features/reader/presentation/reader_screen.dart`
- Modify: `lib/features/library/data/book_model.dart`

**Step 1: Write the failing tests**

- Assert imported TXT content remains readable after copy mode.
- Assert volatile picker paths are copied into app-owned storage.
- Assert reader-facing helper methods report missing files instead of silently succeeding.

**Step 2: Run test to verify it fails**

Run: `flutter test test/library_import_open_test.dart`

Expected: FAIL because the current import/open path does not protect against transient picker files and the reader path handling is under-specified.

**Step 3: Write minimal implementation**

- Normalize app-copy as the safe persisted path.
- Validate source existence and imported suffix handling.
- Fix reader loaders and visible error messages.

**Step 4: Run test to verify it passes**

Run: `flutter test test/library_import_open_test.dart`

### Task 4: Rebuild settings/API/runtime log UX

**Files:**
- Modify: `lib/features/settings/presentation/settings_screen.dart`
- Modify: `lib/features/settings/presentation/translation_config_screen.dart`
- Modify: `lib/features/logging/app_run_log_service.dart`
- Modify: `lib/features/settings/presentation/runtime_log_screen.dart`
- Modify: `lib/app/router.dart`

**Step 1: Write the failing tests**

- Assert runtime logs default to the project `运行日志` directory.
- Assert API config validation handles bad responses without crashing navigation state.

**Step 2: Run test to verify it fails**

Run: `flutter test test/app_run_log_service_test.dart test/translation_service_test.dart`

Expected: FAIL if log directory naming or API validation UX contracts are still broken.

**Step 3: Write minimal implementation**

- Replace mojibake strings with correct Chinese.
- Make API config list/edit layout avoid overlapping controls.
- Keep back navigation inside settings stable.
- Add richer log records for download, install, health check, mount, synthesize, import, and reader-open flows.

**Step 4: Run test to verify it passes**

Run: `flutter test test/app_run_log_service_test.dart test/translation_service_test.dart`

### Task 5: Bundle Piper assets and ship builds

**Files:**
- Modify: `pubspec.yaml`
- Modify: `windows/runner/CMakeLists.txt`
- Modify: `setup.iss`
- Modify: `CHANGELOG.md`
- Modify: `version.json`
- Modify: `开发书.md`
- Modify: `开发进度书.md`
- Create or update: `tools/piper/...`

**Step 1: Prepare bundled assets**

- Place Piper runtime and bundled voice under `tools/piper`.
- Ensure Windows build copies bundled Piper assets into `data/piper`.

**Step 2: Verify builds locally**

Run:
- `flutter test`
- `flutter analyze`
- `flutter build apk --release`
- `flutter build windows --release`
- `ISCC setup.iss`

Expected: all commands succeed.

**Step 3: Publish artifacts**

- Copy release artifacts into `releases/<version>/`.
- Record the new version and changelog.
