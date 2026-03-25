# Foliate + Legado Migration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the Android local-book reading core with `foliate-js`, replace the Android webnovel core with `Legado`-oriented integration, preserve the current Flutter UI shell, and keep the legacy implementation archived but intact.

**Architecture:** Keep Flutter as the app shell for routing, bookshelf, settings, sync, and screen chrome. Route Android EPUB/TXT reading through a WebView-hosted `foliate-js` bridge and route Android webnovel parsing/fetching through a new Legado-backed integration seam. Leave Windows on the current shell path for backup and management only.

**Tech Stack:** Flutter, Riverpod, GoRouter, flutter_inappwebview, Android platform integration, foliate-js, Legado reference code, GitHub Actions.

### Task 1: Freeze the migration boundary in docs and routes

**Files:**
- Modify: `lib/app/router.dart`
- Modify: `lib/features/reader/presentation/reader_screen.dart`
- Modify: `lib/features/webnovel/presentation/webnovel_screen.dart`
- Test: `dart analyze lib/app/router.dart lib/features/reader/presentation/reader_screen.dart lib/features/webnovel/presentation/webnovel_screen.dart`

**Step 1: Add migration comments and routing notes**

- Add short comments at the Android reader and webnovel route boundaries explaining that the Flutter shell stays and the internals are being replaced.

**Step 2: Run analyzer**

Run: `dart analyze lib/app/router.dart lib/features/reader/presentation/reader_screen.dart lib/features/webnovel/presentation/webnovel_screen.dart`

Expected: no new analyzer errors.

**Step 3: Commit**

```bash
git add lib/app/router.dart lib/features/reader/presentation/reader_screen.dart lib/features/webnovel/presentation/webnovel_screen.dart
git commit -m "docs: mark reader and webnovel migration seams"
```

### Task 2: Vendor a minimal foliate host into app assets

**Files:**
- Create: `assets/reader/foliate/`
- Modify: `pubspec.yaml`
- Create: `docs/archive/foliate-host-notes.md`
- Test: `flutter pub get`

**Step 1: Copy the minimal foliate runtime**

- Copy only the minimal files needed to boot a local foliate reader host, not the full upstream repo.
- Start with a dedicated asset subtree under `assets/reader/foliate/`.

**Step 2: Register assets**

- Add the foliate asset subtree to `pubspec.yaml`.

**Step 3: Document what was copied and why**

- Record exact upstream source files and local mappings in `docs/archive/foliate-host-notes.md`.

**Step 4: Refresh Flutter assets**

Run: `flutter pub get`

Expected: asset manifest includes the new foliate subtree.

**Step 5: Commit**

```bash
git add assets/reader/foliate pubspec.yaml docs/archive/foliate-host-notes.md
git commit -m "feat: vendor minimal foliate host assets"
```

### Task 3: Build a Flutter foliate bridge screen without changing shell UI

**Files:**
- Create: `lib/features/reader/foliate/foliate_reader_screen.dart`
- Create: `lib/features/reader/foliate/foliate_reader_bridge.dart`
- Modify: `lib/features/reader/engine/reader_engine_plan.dart`
- Modify: `lib/features/reader/presentation/reader_screen.dart`
- Test: `test/reader_engine_plan_test.dart`

**Step 1: Write a failing unit test for engine planning**

- Add a test asserting Android EPUB/TXT resolve to the foliate engine target.

**Step 2: Run the test to confirm the baseline**

Run: `flutter test test/reader_engine_plan_test.dart`

Expected: fail if the target logic is incomplete.

**Step 3: Add the foliate bridge screen**

- Create a dedicated screen that hosts `flutter_inappwebview`.
- Do not alter the external app bar / shell layout.
- Keep the current `ReaderScreen` as orchestrator.

**Step 4: Add a message bridge**

- Add a small bridge for opening book payload, progress updates, TOC updates, and error reporting.

**Step 5: Route Android EPUB/TXT into the new screen**

- Only on Android and only for EPUB/TXT.
- Keep legacy Flutter reader path as fallback.

**Step 6: Run the test again**

Run: `flutter test test/reader_engine_plan_test.dart`

Expected: pass.

**Step 7: Commit**

```bash
git add lib/features/reader/foliate lib/features/reader/engine/reader_engine_plan.dart lib/features/reader/presentation/reader_screen.dart test/reader_engine_plan_test.dart
git commit -m "feat: add foliate reader bridge for android books"
```

### Task 4: Normalize TXT into a foliate-friendly local document path

**Files:**
- Create: `lib/features/reader/foliate/foliate_txt_adapter.dart`
- Modify: `lib/features/reader/book_text_loader.dart`
- Modify: `lib/features/reader/foliate/foliate_reader_bridge.dart`
- Test: `test/book_text_loader_test.dart`
- Test: `test/foliate_txt_adapter_test.dart`

**Step 1: Write a failing TXT adapter test**

- Assert a TXT book becomes a stable local document payload with decoded text and metadata.

**Step 2: Run the test**

Run: `flutter test test/foliate_txt_adapter_test.dart`

Expected: fail before implementation.

**Step 3: Implement the adapter**

- Reuse the existing TXT decode logic.
- Build a local HTML/document payload suitable for foliate-hosted reading.

**Step 4: Verify TXT regression tests**

Run: `flutter test test/book_text_loader_test.dart test/foliate_txt_adapter_test.dart`

Expected: pass.

**Step 5: Commit**

```bash
git add lib/features/reader/foliate/foliate_txt_adapter.dart lib/features/reader/book_text_loader.dart lib/features/reader/foliate/foliate_reader_bridge.dart test/book_text_loader_test.dart test/foliate_txt_adapter_test.dart
git commit -m "feat: adapt txt books for foliate reader"
```

### Task 5: Preserve reader shell state around the foliate host

**Files:**
- Modify: `lib/features/reader/presentation/reader_screen.dart`
- Modify: `lib/features/reader/providers/reader_settings_provider.dart`
- Test: `test/reader_screen_test.dart`

**Step 1: Write failing state tests**

- Progress restore
- Reading mode shell controls
- Overlay visibility

**Step 2: Run the failing tests**

Run: `flutter test test/reader_screen_test.dart`

Expected: fail for new foliate-shell expectations.

**Step 3: Preserve shell behavior**

- Keep the current Flutter overlay, controls, settings, and reading progress shell.
- Let foliate own content rendering only.

**Step 4: Run the tests**

Run: `flutter test test/reader_screen_test.dart`

Expected: pass.

**Step 5: Commit**

```bash
git add lib/features/reader/presentation/reader_screen.dart lib/features/reader/providers/reader_settings_provider.dart test/reader_screen_test.dart
git commit -m "feat: preserve reader shell around foliate host"
```

### Task 6: Carve out a Legado integration seam on Android

**Files:**
- Create: `lib/features/webnovel/legado/legado_engine_plan.dart`
- Create: `lib/features/webnovel/legado/legado_bridge.dart`
- Modify: `lib/features/webnovel/presentation/webnovel_screen.dart`
- Modify: `lib/features/webnovel/webnovel_repository.dart`
- Test: `test/webnovel_repository_test.dart`

**Step 1: Write failing seam tests**

- Add tests that assert Android webnovel path can resolve to a Legado integration target while preserving existing fallback behavior.

**Step 2: Run the tests**

Run: `flutter test test/webnovel_repository_test.dart`

Expected: fail for the new integration seam expectations.

**Step 3: Add a Legado boundary**

- Add a separate integration layer rather than spreading direct calls throughout the screen.
- Keep the current UI shell and state handling.

**Step 4: Preserve legacy fallback**

- If Legado integration is unavailable, current repository remains as fallback during migration.

**Step 5: Run the tests**

Run: `flutter test test/webnovel_repository_test.dart`

Expected: pass.

**Step 6: Commit**

```bash
git add lib/features/webnovel/legado lib/features/webnovel/presentation/webnovel_screen.dart lib/features/webnovel/webnovel_repository.dart test/webnovel_repository_test.dart
git commit -m "feat: add legado integration seam for android webnovel"
```

### Task 7: Wire Android-only platform integration for Legado

**Files:**
- Create: `android/app/src/main/kotlin/.../legado/`
- Create: `lib/features/webnovel/legado/legado_platform_channel.dart`
- Modify: `lib/features/webnovel/legado/legado_bridge.dart`
- Test: platform smoke test script or manual QA doc

**Step 1: Document the Android bridge contract**

- Define exact method names, payloads, and expected responses.

**Step 2: Implement minimal platform channel**

- Keep it narrow: search, detail, chapter list, chapter content.

**Step 3: Add a QA checklist**

- Save under `docs/qa/` with exact Android checks.

**Step 4: Verify build**

Run: `flutter analyze`

Expected: no new analyzer errors blocking build.

**Step 5: Commit**

```bash
git add android/app/src/main/kotlin lib/features/webnovel/legado docs/qa
git commit -m "feat: add android legado platform bridge"
```

### Task 8: Stop Windows from acting like a first-class reader target

**Files:**
- Modify: `lib/app/router.dart`
- Modify: `lib/features/reader/engine/reader_engine_plan.dart`
- Modify: `README.md`
- Test: `dart analyze lib/app/router.dart lib/features/reader/engine/reader_engine_plan.dart`

**Step 1: Narrow Windows scope in app behavior**

- Preserve routes and shell.
- Keep library/backup/sync.
- Reduce emphasis on Windows reading paths in docs and engine planning.

**Step 2: Verify analyzer**

Run: `dart analyze lib/app/router.dart lib/features/reader/engine/reader_engine_plan.dart`

Expected: no new analyzer errors.

**Step 3: Commit**

```bash
git add lib/app/router.dart lib/features/reader/engine/reader_engine_plan.dart README.md
git commit -m "docs: narrow windows reader scope during migration"
```

### Task 9: Add GitHub Release publishing after migration path stabilizes

**Files:**
- Modify: `.github/workflows/android-release.yml`
- Modify: `.github/workflows/windows-release.yml`
- Create or modify: `.github/workflows/release.yml`
- Test: workflow lint or dry-run documentation

**Step 1: Keep current artifact workflows working**

- Do not break current artifact uploads.

**Step 2: Add tag-triggered release publishing**

- Upload APK and Windows installer to a GitHub Release.

**Step 3: Document release flow**

- Update cloud build docs with exact tag flow.

**Step 4: Commit**

```bash
git add .github/workflows docs/github-actions-cloud-build.md
git commit -m "ci: publish apk and installer to github releases"
```

### Task 10: Verification and migration checkpoint

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/qa/2026-03-25-migration-checkpoint.md`

**Step 1: Run focused verification**

Run:
- `flutter test test/book_text_loader_test.dart`
- `flutter test test/webnovel_repository_test.dart`
- `dart analyze lib/features/reader lib/features/webnovel lib/app`

Expected: passing tests and no new blocking analyze errors.

**Step 2: Write checkpoint**

- Record what is fully migrated
- Record what is still fallback-only
- Record known risks

**Step 3: Commit**

```bash
git add CHANGELOG.md docs/qa/2026-03-25-migration-checkpoint.md
git commit -m "docs: record migration checkpoint"
```

Plan complete and saved to `docs/plans/2026-03-25-foliate-legado-implementation-plan.md`. Two execution options:

1. Subagent-Driven (this session) - I dispatch fresh subagent per task, review between tasks, fast iteration
2. Parallel Session (separate) - Open new session with executing-plans, batch execution with checkpoints

Which approach?
