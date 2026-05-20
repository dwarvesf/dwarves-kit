# docs/specs

Numbered specs for every cycle of work on the kit. Drafts and shipped specs both live here. The file's `Status:` header (DRAFT / VALIDATED / SHIPPED) tells you the state.

Naming: `SPEC-NNN-<short-slug>.md`, zero-padded sequential, assigned when the file is created. The slug names the feature or change (e.g. `upstream-audit`, `orchestration-layer`), not the release it ships in. Do not put a version in the filename: the version belongs in the spec's title and `Status:` header, so a spec that slips to a later release does not need a rename. Slug target: 2-4 kebab-case words. Subsequent changes to a shipped feature get a new SPEC; do not edit a SHIPPED spec in place (use a new spec or an ADR).

Pattern source: ops-toolkit `tools/tide/docs/specs/`. dwarves-kit's prior convention (`.planning/SPEC.md` for working, migrate to `docs/specs/` at ship) was inherited from GSD and has been retired. **ADR-0010 unified the convention onto `docs/specs/SPEC-NNN-<slug>.md` for both the kit and downstream projects, superseding ADR-0002.**

The kit's hooks keep a bounded `.planning/SPEC.md` fallback (with a deprecation warning) for one minor version, to ease migration of existing downstream projects; it is removed after that window. New projects, kit and downstream alike, put specs in `docs/specs/` from day one. Migrating an existing project is a one-liner: `mv .planning/SPEC.md docs/specs/SPEC-001-<slug>.md`. See ADR-0010.
