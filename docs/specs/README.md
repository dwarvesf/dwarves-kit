# docs/specs

Numbered specs for every cycle of work on the kit. Drafts and shipped specs both live here. The file's `Status:` header (DRAFT / VALIDATED / SHIPPED) tells you the state.

Naming: `SPEC-NNN-<short-slug>.md`, zero-padded sequential, assigned when the file is created. The slug names the feature or change (e.g. `upstream-audit`, `orchestration-layer`), not the release it ships in. Do not put a version in the filename: the version belongs in the spec's title and `Status:` header, so a spec that slips to a later release does not need a rename. Slug target: 2-4 kebab-case words. Subsequent changes to a shipped feature get a new SPEC; do not edit a SHIPPED spec in place (use a new spec or an ADR).

Pattern source: ops-toolkit `tools/tide/docs/specs/`. dwarves-kit's prior convention (`.planning/SPEC.md` for working, migrate to `docs/specs/` at ship) was inherited from GSD and has been retired for the kit's own work; see ADR-0002.

The kit's hooks and commands still reference `.planning/SPEC.md` for downstream projects that follow the GSD-style separation. That path remains the documented convention for kit USERS. For the kit ITSELF as a project, specs live here from day one.
