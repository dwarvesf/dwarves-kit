# Implementation notes: colocated-spec-resolution

Spec: `docs/specs/SPEC-386-colocated-spec-resolution.md`. This file holds the delta from the spec only.

## Decisions not in the brief

- Scope grew from three callers to five. `proof-ledger.sh` `_negctl_required` and `pitch.sh` `_find_spec` carry the same root-only glob (spec DEC-5).
- Gates think, design and design-critique are overrides, not runs. The operator brief fixed the problem and the done list; the draft PR exists for the operator's design review.

## Stop: two sessions in one worktree

A second session wrote an untracked `docs/specs/SPEC-388-colocated-spec-resolution.md` into this worktree mid-round. It covers the same brief with a different design (`SPEC_FIND_MAX_PREFIX`, `tests/test-spec-colocated.sh`). Both sessions share the rid `colocated-spec-resolution`, so they also write one gate ledger. Validation round 1 was closed `incomplete`; no code was written. Resolved: the other session backed out, removed its SPEC-388 file, and stopped. SPEC-386 is the canonical spec. Its ledger lines (a second START with `classified=normal`, a grill skip, three overrides, a ui-design skip) stay, because the ledger is append-only. A `START-AMEND` now pins `lane=full classified=full repo=dwarves-kit`. Its spec-next reservation for 388 lapses after 24h.

## Round 1 findings (5 of 7 reviewers returned; 5 and 6 stopped)

The critical folded into the spec as `### Co-located name match`, Edge Case 9 and DEC-7. Root files keep the glob on purpose: the spec's invariant says a root-only repo keeps today's pick.

### Warnings for the build

- Path form: `spec_files` prints `<root>/<rel>`, never `<root>/./<rel>`. A test pins the string, because validate-round compares paths.
- Prune `vendor`, `target`, `dist` and `build` with the dot-dirs and `node_modules`. Vendored or built specs must not raise `next`.
- TASK-4: the `rg` AC misses the real root-only prose. Check `commands/start.md`, `commands/next.md` and `commands/dispatch.md` by hand. Active-spec lookup there stays root-only (Out of Scope); say so where the prose could mislead.
- Task order: TASK-1, then TASK-2, then TASK-3, then TASK-4.
- Test ship-gate's fallback: with `spec-find.sh` unreadable, ship-gate still finds a root spec.
- Test `spec-next check 001` in a repo with a co-located `SPEC-001`: it reports taken. Accepted by design (Edge Case 8 covers `next`; `check` now sees every namespace).
- Nested git repo under the root: validate-round's `top` and ship-gate's `ROOT` both come from the outer checkout here. Note any gap the build finds.
- Hostile names: `cd --` before the walk, `-type f`, and one test with a space in a spec path.

### Rejected warning

- "Status must be DRAFT, VALIDATED or SHIPPED, not APPROVED." `commands/spec.md` step 4 sets `APPROVED` before validation; 11 specs carry it. Status stays `APPROVED` until round 2 returns.
