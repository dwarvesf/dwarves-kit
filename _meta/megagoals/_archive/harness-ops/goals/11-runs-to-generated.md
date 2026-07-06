# Sub-goal 11: runs-to-generated

**Merge policy:** auto
**Time budget:** 1-2 hours
**Proof:** run-table showing `proof-table-gen` writing to the new `docs/verification/generated/` path + the generator's realpath jail accepting it. Rung 2 (a negative control: a write outside the jail is still refused).
**Design:** obvious
**Depends on:** none (Track B)
Model: sonnet
**Branch:** fix/harness-ops-11-runs-gen
**PR base:** main

## Outcome

The name collision between `docs/runs/` (generated proof-tables) and `docs/verification/<slug>/runs/` (immutable execution records) is gone: the generated tables move to `docs/verification/generated/`, and the `proof-table-gen.py`/`.sh` realpath jail is repointed so the generator confines output there. Two unrelated things are no longer both called "runs".

## How to close the loop

- Move `docs/runs/*` → `docs/verification/generated/`.
- Repoint the realpath jail in `lib/gate/proof-table-gen.py` (:12,:285) and `.sh` (:13,:18) to the new dir.
- Test: run `proof-table-gen` and assert it writes to `docs/verification/generated/`; the negative control (attempt a write outside the jail) is still refused. Capture the run-table.

**Done =** the generated proof-tables live at `docs/verification/generated/`, the generator's realpath jail accepts that path and still refuses out-of-jail writes (captured run-table incl. the NC).

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → normal).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; HANDOFF.md → next; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** `docs/runs/` contents, the realpath jail in proof-table-gen.py/.sh.
**Out:** the `verification/<slug>/runs/` execution records (different thing, untouched), the table format.
**Not:** deleting the generated tables, changing the generator's logic, touching verification/.

## PR body

Moves generated proof-tables `docs/runs/` → `docs/verification/generated/` and repoints the proof-table-gen realpath jail, killing the `runs/` name collision. Verify: the generator-writes-to-new-path run-table + the out-of-jail NC. Part of `harness-ops` (Track B), see ROADMAP.md.

## Notes
