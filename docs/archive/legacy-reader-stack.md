# Legacy Reader Stack Archive

This document preserves the old reader and webnovel implementation map after the project decision to migrate toward `foliate-js` and `Legado`.

## Status

Legacy code is preserved for:
- rollback
- reference
- partial reuse during transition
- regression comparison

Legacy code is no longer the strategic long-term reading core.

## Local Reader Legacy Core

Primary files:
- `lib/features/reader/presentation/reader_screen.dart`
- `lib/features/reader/presentation/paged_text_reader.dart`
- `lib/features/reader/reader_document_probe.dart`
- `lib/features/reader/book_text_loader.dart`
- `lib/features/reader/text_render_chunker.dart`
- `lib/features/reader/reader_style.dart`

What it handled:
- TXT loading and pagination
- EPUB extraction and fallback parsing
- page curl / page flip rendering
- PDF and comic routing
- reading progress and overlay logic

Why it is archived:
- EPUB correctness and performance remained inconsistent
- TXT decoding and rendering required repeated heuristics
- animation work was too expensive relative to delivery quality

## Webnovel Legacy Core

Primary files:
- `lib/features/webnovel/webnovel_repository.dart`
- `lib/features/webnovel/presentation/webnovel_screen.dart`
- `lib/features/webnovel/models.dart`
- `assets/webnovel/bundled_sources.json`

What it handled:
- source import
- search
- chapter sync
- chapter cache
- browser-assisted recognition
- reader mode detection

Why it is archived:
- long-term parser maintenance cost is too high
- source compatibility is still fragile
- repeated fixes do not beat the maturity of `Legado`

## UI Shell To Preserve

The following shell remains the preferred outer app structure:
- bookshelf
- settings
- sync
- route structure
- reader route
- webnovel route

Migration intent:
- replace internals, preserve shell

## Migration Policy

- Do not delete the legacy stack during migration.
- Do not add large new feature work to the legacy engines unless required as a short-term stopgap.
- Keep changes isolated so the replacement path can take over format by format.

## Current Primary Path

As of the current migration checkpoint:
- Android `EPUB` and `TXT` now target the `foliate-js` bridge path first.
- If the `foliate` runtime cannot be staged successfully, the reader falls back to the legacy Flutter local-reader path.
- Windows and non-Android platforms still stay on the legacy local-reader path.
- PDF, comic, and webnovel formats still remain on their existing Flutter paths until later phases replace them.
