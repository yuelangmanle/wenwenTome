# 2026-03-08 Reader And Webnovel Recovery

## User-Reported Issues

1. Mobile translation local-model preheat can crash.
2. EPUB books may fail to open on mobile.
3. Local TTS check can spin forever, and in-reader read-aloud often has no output.
4. Reader is missing page-turn mode, animation, progress bar, TOC flow, bookmarks, reading-time stats, custom font import, and palette/background controls promised in the original plan.
5. Imported webnovel sources cannot search reliably, and 3000+ sources make search/source-management freeze.
6. Embedded web search has poor scrolling/reader optimization.
7. Reader still shows the main bottom navigation bar and back behavior is wrong.
8. Online metadata completion is ineffective.

## Root Causes Confirmed

- Reader was opened with `Navigator.push(MaterialPageRoute(...))` from inside the shell route, so the bottom navigation stayed visible in reading mode.
- In-reader TTS passed the entire TXT/EPUB body into local synthesis, which is too heavy for mobile devices.
- Local TTS manager checked models sequentially with no timeout, so one slow check blocked the whole screen.
- Webnovel search iterated all enabled sources serially.
- Source management rendered the whole source list eagerly.
- Legado import compatibility was weak for dirty `bookSourceUrl` values and request descriptors with multiple option objects.
- Metadata enrichment relied on fragile sources only.
- Design documents and changelog promised richer reading features than the current reader UI actually wires up.

## Design Gap Audit

Compared against `CHANGELOG.md`, `README.md`, `开发书.md`, `开发进度书.md`, `移交说明书.md`, and `../brainstorm_ebook.md.resolved`, the following items are still not truly delivered end-to-end:

- Horizontal page-turn reading for text books.
- Realistic page-turn animation selection.
- Full TOC navigation flow for all formats.
- Persistent in-reader bookmark management UI.
- Reading-time dashboards driven by real reader sessions.
- Custom font import pipeline.
- Palette/color-picker based theme customization.
- Better web-page reader-mode conversion and scroll polish.
- Robust Legado compatibility for JSONPath and JS-heavy sources.

## Changes In This Pass

- Route reader outside the bottom-navigation shell.
- Limit TTS read-aloud to the current visible text window/current chapter instead of the whole book.
- Add timeouts and parallel checks to local TTS model verification.
- Reduce Android local-translation preload pressure by lowering context size and thread count.
- Improve online metadata enrichment with a more resilient provider chain.
- Make webnovel source search concurrency-limited instead of serial.
- Add source filtering and lazy list rendering for mobile source management.
- Normalize imported source base URLs and accept more complex Legado request descriptors.
- Add basic reader navigation affordances: TOC/bookmark entry points, progress slider, and reading-time persistence.

## Remaining Work

- Replace plain long-scroll TXT/EPUB reading with a true paged renderer.
- Add animated page-turn transitions that match the original design target.
- Implement custom font import and palette editing UI.
- Improve EPUB fallback rendering when text extraction is poor.
- Add JSONPath-aware and JS-aware webnovel parsing for a larger share of imported Legado sources.
- Rework embedded web search scrolling/reader optimization against the reference video flow.
