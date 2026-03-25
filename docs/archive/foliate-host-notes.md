# Foliate Host Notes

This repository now vendors a minimal `foliate-js` runtime slice under `assets/reader/foliate/` so Android can later switch the local-book reader over without changing the Flutter shell layout.

## What Is Included

- `assets/reader/foliate/view.js`
- `assets/reader/foliate/epub.js`
- `assets/reader/foliate/epubcfi.js`
- `assets/reader/foliate/progress.js`
- `assets/reader/foliate/overlayer.js`
- `assets/reader/foliate/paginator.js`
- `assets/reader/foliate/fixed-layout.js`
- `assets/reader/foliate/text-walker.js`
- `assets/reader/foliate/search.js`
- `assets/reader/foliate/tts.js`
- `assets/reader/foliate/ui/menu.js`
- `assets/reader/foliate/ui/tree.js`
- `assets/reader/foliate/vendor/zip.js`
- `assets/reader/foliate/reader.html`
- `assets/reader/foliate/reader.js`
- `assets/reader/foliate/wenwen-foliate-host.js`

## Why These Files

- `view.js` and `epub.js` are the core EPUB runtime.
- `paginator.js` and `fixed-layout.js` cover paginated and fixed-layout rendering paths.
- `ui/menu.js` and `ui/tree.js` support the transitional in-WebView shell.
- `vendor/zip.js` satisfies EPUB archive loading.
- `reader.html` and `reader.js` preserve the upstream standalone shell for manual testing.
- `wenwen-foliate-host.js` provides the app-specific host surface for later Flutter bridging and TXT handling.

## Out Of Scope For This Step

- No Flutter bridge wiring.
- No Android platform-channel integration.
- No Legado integration yet.
- No PDF, MOBI, or comic runtime vendoring.

## Notes

- The legacy reader stack remains preserved in the archive documents.
- The host surface is intentionally isolated so Flutter can adopt it later without reworking the app shell.
