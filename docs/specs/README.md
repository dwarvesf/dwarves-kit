# docs/specs

Numbered specs for every cycle of work on the kit. Drafts and shipped specs both live here. The file's `Status:` header (DRAFT / VALIDATED / SHIPPED) tells you the state.

Naming: `SPEC-NNN-<short-slug>.md`, zero-padded sequential, assigned at commit time (see "Concurrent numbering" below). The slug names the feature or change (e.g. `upstream-audit`, `orchestration-layer`), not the release it ships in. Do not put a version in the filename: the version belongs in the spec's title and `Status:` header, so a spec that slips to a later release does not need a rename. Slug target: 2-4 kebab-case words. Subsequent changes to a shipped feature get a new SPEC; do not edit a SHIPPED spec in place (use a new spec or an ADR).

Pattern source: ops-toolkit `tools/tide/docs/specs/`. dwarves-kit's prior convention (`.planning/SPEC.md` for working, migrate to `docs/specs/` at ship) was inherited from GSD and has been retired. **ADR-0010 unified the convention onto `docs/specs/SPEC-NNN-<slug>.md` for both the kit and downstream projects, superseding ADR-0002.**

The kit's hooks keep a bounded `.planning/SPEC.md` fallback (with a deprecation warning) for one minor version, to ease migration of existing downstream projects; it is removed after that window. New projects, kit and downstream alike, put specs in `docs/specs/` from day one. Migrating an existing project is a one-liner: `mv .planning/SPEC.md docs/specs/SPEC-001-<slug>.md`. See ADR-0010.

## Concurrent numbering (shared branch or tree)

The number is claimed **at commit time**, as `max+1` of the numbers already committed to `docs/specs/` (ADRs in `docs/decisions/` follow the same rule). Drafting before you commit holds no claim, so two sessions drafting in parallel cannot pre-reserve the same number. The previous "assigned when the file is created" rule was the source of repeated collisions when two sessions worked one tree.

If two branches still land on the same number, the **later committer renumbers** before merging: rename the file, fix the title line, and update internal `SPEC-NNN` / `ADR-NNNN` references. `tests/test-meta.sh` fails on any duplicate SPEC or ADR number, so a collision cannot ship silently. The number is load-bearing (the active-spec selector in `context-readiness.sh` parses `SPEC-NNN`), so it is fixed in allocation, not removed.
