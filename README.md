# wenwen_tome

`wenwen_tome` is a local-first reading app shell for Android and Windows.

Current direction:
- Android local-book reading is being migrated to `foliate-js`.
- Android webnovel capability is being migrated toward `Legado`-compatible integration.
- Windows remains a library, backup, sync, and packaging endpoint. It is no longer the primary reading target.
- The existing Flutter UI shell, navigation, bookshelf, settings, and sync structure stay in place.

Current version:
- `2.7.0+40`

## License

This repository is now aligned with `GPL-3.0-only`.

Rationale:
- The Android webnovel migration path intentionally adopts `Legado` as the reference implementation and integration target.
- `foliate-js` is used for local-book reading and remains MIT-licensed, which is compatible with distribution under GPL-3.0.

See:
- [LICENSE](/e:/Antigavity%20program/book/wenwen_tome/LICENSE)
- [docs/plans/2026-03-25-foliate-legado-migration.md](/e:/Antigavity%20program/book/wenwen_tome/docs/plans/2026-03-25-foliate-legado-migration.md)
- [docs/archive/legacy-reader-stack.md](/e:/Antigavity%20program/book/wenwen_tome/docs/archive/legacy-reader-stack.md)

## Current Scope

Supported app shell areas:
- Bookshelf and local import flow
- Reader shell and settings shell
- Webnovel entry and source management shell
- Sync and backup shell
- Android and Windows cloud packaging

Known migration state:
- Legacy Flutter reader internals are preserved for archive and rollback reference.
- New reading engine work should target `foliate-js` instead of expanding the legacy EPUB/TXT rendering core.
- New webnovel work should target `Legado` integration instead of extending the current custom parser as the long-term direction.

## Packaging

Cloud builds are already working through GitHub Actions:
- Android workflow: `.github/workflows/android-release.yml`
- Windows workflow: `.github/workflows/windows-release.yml`

Current workflows upload build artifacts. GitHub Releases automation is still a pending follow-up step.

## Local Notes

External upstream references are kept locally for migration work:
- `third_party/foliate-js/`
- `third_party/legado-reference/`

These directories are intentionally ignored from the app repo for now. They are working references, not committed app source.
