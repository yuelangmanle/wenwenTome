# 2026-03-08 Release Verification

Target release: `2.2.0+20`

## Scope

- Reader paged mode, page-turn animation, custom fonts, palette/background controls
- EPUB fallback rendering
- Webnovel JSONPath / JS-aware parsing and large-source performance
- Embedded web reader optimization
- Translation model / TTS model resumable downloads
- Windows `llama-server.zip` resumable runtime download

## Desktop Manual Checks

- Open a TXT book and confirm default mode is paged, not long-scroll
- Switch page-turn animation between `sheet`, `slide`, `fade`, and `flip`
- Drag the progress control, jump via TOC, and jump via bookmarks
- Import a custom font and verify it applies after reopening the reader
- Change foreground/background colors and verify the choice persists
- Open an EPUB with poor text extraction and verify fallback rendering is visible and readable
- Start local TTS from the reader and confirm it only reads the current page/chapter window
- Open embedded web search, verify forward/back/top/down/refresh actions work

## Android Manual Checks

- Install the release APK on a real device
- Open TXT, EPUB, PDF, CBZ, and one imported webnovel entry
- Verify reader chrome hides correctly in reading mode and back behavior is correct
- Verify page-turn animation remains smooth on a long chapter
- Import a font from device storage and reopen the app to confirm persistence
- Start translation model download, interrupt the network, then retry and confirm resume works
- Start TTS model download, interrupt the network, then retry and confirm resume works
- Verify webnovel source search remains responsive with a large imported source set
- Verify embedded web reader optimization still works on at least one normal site and one CSP-heavy site

## Windows Manual Checks

- Install the Windows setup package on a clean machine or VM
- Launch the app and confirm bundled assets are present after install
- Trigger local translation startup on Windows and confirm `llama-server.exe` is prepared successfully
- If `llama-server.zip` download is interrupted, retry and confirm resume works instead of restarting from zero
- Verify local TTS manager can download, install, and remove a downloadable voice pack

## Release Gating

- `flutter analyze --no-fatal-infos`
- `flutter test`
- `flutter build apk --release --target-platform android-arm64`
- `flutter build windows --release`
- `ISCC setup.iss`
- Copy APK, Windows installer, and release notes into `releases/2.2.0/`

## Known Follow-Up Risks

- Reader animation feel and pagination performance still need real-device confirmation on very long chapters
- Custom font compatibility depends on user-supplied font files
- Web reader optimization is still limited by site CSP / iframe / shadow DOM restrictions
- TTS `.tar.bz2` extraction peak memory on low-memory devices should still be watched
