# Third-Party Migration References

This repository now keeps local upstream references for the approved migration path.

## Local Reference Directories

- `third_party/foliate-js/`
- `third_party/legado-reference/`

These directories are intentionally ignored from git for now. They are working references during migration, not yet committed product source.

## Upstream Summary

### foliate-js

- role: Android local-book reading core
- upstream: `https://github.com/johnfactotum/foliate-js`
- local path: `third_party/foliate-js/`
- license: MIT

### Legado

- role: Android webnovel core reference and integration target
- upstream: `https://github.com/gedoor/legado`
- local path: `third_party/legado-reference/`
- license: GPL-3.0

## Repository License Impact

Because the approved direction includes direct `Legado` integration, this repository now adopts `GPL-3.0-only`.
