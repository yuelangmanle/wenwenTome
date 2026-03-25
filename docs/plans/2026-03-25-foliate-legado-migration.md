# 2026-03-25 Foliate + Legado Migration Plan

## Decision

The project is no longer continuing the previous strategy of incrementally patching the custom local reader core and the custom webnovel rule engine as the long-term solution.

Approved direction:
- Local book reading on Android moves to `foliate-js`.
- Webnovel capability on Android moves toward `Legado` integration.
- Windows is downgraded to library, backup, sync, and packaging responsibility.
- The existing Flutter UI shell remains the primary app shell.
- Legacy code is archived and preserved, not deleted.

## Why This Direction

The previous path produced partial fixes but did not close the main user problems:
- TXT and EPUB import/read experience remained unstable.
- Webnovel parsing and source behavior remained too fragile.
- Reader animation and rendering work consumed time without reaching a dependable baseline.

This migration replaces weak custom cores with mature upstream implementations.

## Upstream Targets

### Local Books

Primary target:
- `foliate-js`
- upstream path: `third_party/foliate-js/`
- upstream license: MIT

Use cases:
- EPUB rendering
- TXT rendering after wrapping TXT content into a compatible reader document flow
- unified Android reading surface inside the existing Flutter UI shell

### Webnovel

Primary target:
- `Legado`
- upstream path: `third_party/legado-reference/`
- upstream license: GPL-3.0

Use cases:
- source parsing
- catalog resolution
- chapter fetching
- source compatibility behavior

## Non-Goals

- Do not preserve the legacy custom EPUB/TXT engine as the long-term main path.
- Do not preserve the legacy custom webnovel parser as the long-term main path.
- Do not redesign the bookshelf/settings/navigation UI.
- Do not prioritize Windows reading polish.

## Migration Rules

1. Preserve legacy code in place or archive docs.
2. New work should target replacement seams, not deeper expansion of the old engines.
3. Keep Flutter UI routes and shell stable.
4. Prefer Android-first delivery.
5. Only keep Windows features that support backup, library management, sync, and packaging.

## Phases

### Phase 1

- Add GPL-3.0 repository licensing.
- Archive the legacy reader stack in docs.
- Pull in upstream references locally.
- Define integration seams for `ReaderScreen` and `WebNovelScreen`.

### Phase 2

- Add `foliate-js` Android reader host.
- Route Android EPUB/TXT reading through the new host while keeping the same Flutter shell.
- Keep the legacy Flutter reader as fallback during migration.

### Phase 3

- Introduce `Legado`-oriented Android integration.
- Move webnovel parsing and chapter fetching off the legacy custom engine.
- Keep current Flutter pages as shell and state surface.

### Phase 4

- Remove primary-path dependence on the old reader internals.
- Add GitHub Release automation for APK and Windows installer publishing.

## Current Status

Completed in this phase:
- Repository direction approved
- GPL-3.0 license adopted
- Upstream references cloned locally
- legacy preservation policy documented

Pending:
- actual `foliate-js` embedding
- actual `Legado` integration
- release automation
