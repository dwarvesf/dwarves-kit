# Implementation notes: colocated-spec-resolution

Spec: `docs/specs/SPEC-386-colocated-spec-resolution.md`. This file holds the delta from the spec only.

## Decisions not in the brief

- Scope grew from three callers to five. `proof-ledger.sh` `_negctl_required` and `pitch.sh` `_find_spec` carry the same root-only glob (spec DEC-5).
- Gates think, design and design-critique are overrides, not runs. The operator brief fixed the problem and the done list; the draft PR exists for the operator's design review.

## Stop: two sessions in one worktree

A second session wrote an untracked `docs/specs/SPEC-388-colocated-spec-resolution.md` into this worktree mid-round. It covers the same brief with a different design (`SPEC_FIND_MAX_PREFIX`, `tests/test-spec-colocated.sh`). Both sessions share the rid `colocated-spec-resolution`, so they also write one gate ledger. Validation round 1 was closed `incomplete`; no code was written. Resolved: the other session backed out, removed its SPEC-388 file, and stopped. SPEC-386 is the canonical spec. Its ledger lines (a second START with `classified=normal`, a grill skip, three overrides, a ui-design skip) stay, because the ledger is append-only. A `START-AMEND` now pins `lane=full classified=full repo=dwarves-kit`. Its spec-next reservation for 388 lapses after 24h.

## Round 1 findings (5 of 7 reviewers returned; 5 and 6 stopped)

Critical (reviewer 3): `SPEC-*-<slug>.md` lets `*` span dashes. Branch `feat/cs` matches a co-located `SPEC-147-foo-cs.md`, so ship-gate can read an unrelated spec's `Lane:`. Fix: match the basename `SPEC-<digits>-<slug>.md` exactly for co-located files; add a decoy fixture.

Warnings to fold:

- Path form: `spec_files` must print `<root>/<rel>` with no `./`; pin it in TASK-1's AC (validate-round compares strings).
- Prune `vendor`, `target`, `dist`, `build` too, or record the ceiling; fixture and vendored specs can raise `next`.
- TASK-4's `rg` check misses the real root-only prose (`commands/start.md:19`, `commands/next.md:11`, `commands/dispatch.md:21`); name files and say active-spec lookup stays root-only.
- Declare task dependencies; add a test for ship-gate's missing-resolver fallback.
- Status must be DRAFT, VALIDATED or SHIPPED, not APPROVED.
- `spec-next check 001` now reports taken in repos with per-namespace `SPEC-001`; add an edge case.
- A nested git repo under the root gives validate-round a different `top` than ship-gate's `ROOT`.
- Hostile names: `cd --` (done in the draft), a spaced filename test, `-type f` stated in Design.
