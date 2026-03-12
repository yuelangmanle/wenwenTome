# Android Local Runtime Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Android local TTS and Android local translation actually runnable in-app, with working model mounting, detection, and download flows.

**Architecture:** Replace the current Android placeholders with real local runtimes. TTS will use sherpa-onnx with a bundled built-in Chinese voice plus downloadable Chinese voice packs. Translation will use llama_flutter_android for in-process GGUF inference, while Windows keeps the existing local-server path.

**Tech Stack:** Flutter, Riverpod, sherpa_onnx, llama_flutter_android, archive, audioplayers.

### Task 1: Translation service routing

**Files:**
- Modify: `E:\Antigavity program\book\wenwen_tome\lib\features\translation\translation_service.dart`
- Create: `E:\Antigavity program\book\wenwen_tome\lib\features\translation\local_translation_executor.dart`
- Test: `E:\Antigavity program\book\wenwen_tome\test\translation_service_test.dart`

**Step 1: Write the failing test**
- Add a test asserting `TranslationService.translate(... useLocalModel: true)` uses a local executor instead of HTTP.

**Step 2: Run test to verify it fails**
- Run: `flutter test test/translation_service_test.dart`
- Expected: compile or assertion failure because local execution path does not exist.

**Step 3: Write minimal implementation**
- Add an injectable local executor interface.
- Route translation calls to the local executor when requested.

**Step 4: Run test to verify it passes**
- Run: `flutter test test/translation_service_test.dart`
- Expected: PASS.

### Task 2: TTS asset plan and runtime selection

**Files:**
- Modify: `E:\Antigavity program\book\wenwen_tome\lib\features\reader\local_tts_model_manager.dart`
- Create: `E:\Antigavity program\book\wenwen_tome\lib\features\reader\sherpa_tts_runtime.dart`
- Test: `E:\Antigavity program\book\wenwen_tome\test\import_and_download_policy_test.dart`

**Step 1: Write the failing test**
- Add tests asserting downloadable TTS voices expose both official and mirror Android-capable assets, and the built-in voice has a bundled asset manifest.

**Step 2: Run test to verify it fails**
- Run: `flutter test test/import_and_download_policy_test.dart`
- Expected: FAIL because current model metadata only supports desktop Piper downloads.

**Step 3: Write minimal implementation**
- Add sherpa model metadata for built-in and downloadable voices.
- Add runtime helpers to resolve/copy/extract those assets.

**Step 4: Run test to verify it passes**
- Run: `flutter test test/import_and_download_policy_test.dart`
- Expected: PASS.

### Task 3: Android local TTS synthesis

**Files:**
- Modify: `E:\Antigavity program\book\wenwen_tome\lib\features\reader\local_tts_runner.dart`
- Modify: `E:\Antigavity program\book\wenwen_tome\lib\features\reader\tts_service.dart`
- Modify: `E:\Antigavity program\book\wenwen_tome\lib\features\reader\presentation\local_tts_manager_screen.dart`
- Test: `E:\Antigavity program\book\wenwen_tome\test\local_tts_configuration_test.dart`

**Step 1: Write the failing test**
- Add a test for the new local TTS configuration path and persisted params under sherpa-based synthesis.

**Step 2: Run test to verify it fails**
- Run: `flutter test test/local_tts_configuration_test.dart`
- Expected: FAIL because the old Piper CLI assumptions no longer hold.

**Step 3: Write minimal implementation**
- Synthesize WAV with sherpa-onnx on Android and Windows.
- Remove Android fallback-to-system-TTS behavior when the local model is available.

**Step 4: Run test to verify it passes**
- Run: `flutter test test/local_tts_configuration_test.dart`
- Expected: PASS.

### Task 4: Android local translation runtime

**Files:**
- Modify: `E:\Antigavity program\book\wenwen_tome\lib\features\translation\local_model_service.dart`
- Modify: `E:\Antigavity program\book\wenwen_tome\lib\features\translation\providers\chapter_translation_provider.dart`
- Modify: `E:\Antigavity program\book\wenwen_tome\lib\features\settings\presentation\settings_screen.dart`
- Test: `E:\Antigavity program\book\wenwen_tome\test\local_model_notifier_test.dart`

**Step 1: Write the failing test**
- Add tests asserting Android local-model availability no longer reports Windows-only behavior.

**Step 2: Run test to verify it fails**
- Run: `flutter test test/local_model_notifier_test.dart`
- Expected: FAIL because current Android availability message still says Windows-only.

**Step 3: Write minimal implementation**
- Add Android model load/check helpers and connect the `useLocalTranslate` setting to actual translation jobs.

**Step 4: Run test to verify it passes**
- Run: `flutter test test/local_model_notifier_test.dart`
- Expected: PASS.

### Task 5: Packaging and verification

**Files:**
- Modify: `E:\Antigavity program\book\wenwen_tome\pubspec.yaml`
- Modify: `E:\Antigavity program\book\wenwen_tome\android\app\build.gradle.kts`
- Modify: `E:\Antigavity program\book\wenwen_tome\android\app\src\main\AndroidManifest.xml`
- Modify: `E:\Antigavity program\book\wenwen_tome\CHANGELOG.md`
- Modify: `E:\Antigavity program\book\wenwen_tome\version.json`

**Step 1: Verify all targeted tests pass**
- Run the focused test files, then full `flutter test`.

**Step 2: Verify static analysis and builds**
- Run `flutter analyze --no-fatal-infos`
- Run `flutter build apk --release --no-tree-shake-icons`
- Run `flutter build windows --release`

**Step 3: Update version and changelog**
- Bump version after runtime work is complete.

**Step 4: Produce installable artifacts**
- Copy final APK/EXE installer into `E:\Antigavity program\book\wenwen_tome\releases\<version>`.
