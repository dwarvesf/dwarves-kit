# Sub-goal 09: kit-layout

**Merge policy:** auto (the kit's full test suite is the gate; the symlink-shim makes it a ~0-breakage mechanical move)
**Time budget:** 2-3 hours
**Proof:** run-table: the FULL dwarves-kit test suite green BEFORE and AFTER the move (the non-regression proof) + a grep proving no runtime `source`/`bash lib/...` reference broke + `lib/README.md` rendered + COVERAGE-DELTA (files moved, symlinks created, refs verified)
**Design:** bearing (structural; the symlink-shim mechanism is the heart, and a broken ref bricks the kit)
**Repo:** dwarves-kit (hand-made worktree from `master`).
**Depends on:** 03K + 04 + 07 + 08 MERGED (do this LAST so it groups the FINAL `lib/`, including the board files SG-04/07/08 add; else the two collide on `lib/` paths).
Model: sonnet
**Branch:** `refactor/kit-lib-layout` (dwarves-kit)
**PR base:** master

## Outcome

The kit stops being a newcomer wall: `lib/` (32 flat files) is grouped into navigable subsystem subdirs, and a `lib/README.md` maps them. A newcomer can see "orchestration lives here, gates here, lane-classify here" at a glance. NO behavior change, NO broken reference: existing `bash lib/<x>.sh` / `source "$DIR/<x>.sh"` invocations keep working via a flat symlink layer.

## Quality bar

ZERO runtime breakage. The move is guarded by the kit's own full test suite (55 files) passing identically before and after. Every one of the ~95 runtime references (tests/commands/hooks/agents + intra-lib `source`) must still resolve. Do NOT mass-sed 324 references; use the symlink shim (the survey proved no script `realpath`-resolves its own `BASH_SOURCE`, so `lib/<x>.sh` symlinks resolve transparently).

## How to close the loop

- **Phase 0 (nav map, zero-risk):** write `lib/README.md` grouping the 32 scripts by subsystem, one-line purpose each. Groups (from the actual files): `orchestrate/` (orchestrate.sh, mega-merge, stack-merge, goal-registry, goal-drafts), `gates/` (gate-ledger, proof-ledger, proof-gate, proof-table-gen, dispatch-gate, quiz-gate), `lane/` (lane-classify, lane-telemetry, task-type-classify, role-classify, significance-classify, route-suggest, precedent), `spec/` (spec-next, spec-index, pitch, explain), `verify/` (coverage-delta, mutation-smoke, verif-counts), `backlog/` (backlog.sh + the SG-04 board/parse-board files), `learn/` (weekend-batch), `adopt/` (adopt), `core/` (kit-log-dir, the shared helper).
- **PRE-CHECK (load-bearing):** grep the tests for `find lib`/`ls lib`/`maxdepth 1` assertions that would trip on subdirs+symlinks; if any exist, adjust them or the plan (the survey flagged this as the one uncertainty).
- **Phase 1 (grouping, symlink-shim):** `git mv` each file into its subsystem subdir, then create a flat symlink `lib/<x>.sh -> <subsystem>/<x>.sh` for all 32 so every existing reference still resolves. Any NEW intra-subdir sibling `source` goes through the `lib/` symlink or `../core/`.
- **Verify:** run the FULL suite (`bash tests/...` per the kit's runner) green; grep-confirm every `source lib/`/`bash lib/` target still resolves (the symlink set covers them); render `lib/README.md`.

**Done =** the full kit test suite green after the move AND every runtime ref verified resolving AND `lib/README.md` committed. Kit-adopted: read AGENTS.md + WORKFLOW.md, lane-classify, record gate-ledger phases before push.

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. HANDOFF: next = convergence gate.
3. DECISIONS: the final subsystem grouping + the symlink-shim decision + any test that needed adjusting.
4. Report IN the records, EXIT.

## Scope edges

**In:** `lib/` subsystem subdirs + the flat symlink layer + `lib/README.md`; any test assertion that must adjust for subdirs.
**Out:** the giant root docs (WORKFLOW 88K / CHANGELOG 103K / MANUAL / architecture) , a SEPARATE newcomer problem, its own follow-up; `commands/`/`agents/`/`hooks/` reorg (out of scope).
**Not:** renaming files, changing any script's behavior, a mass-sed of references, touching non-`lib/` layout.

## Where to look

`dwarves-kit/lib/` (the 32 files to group), the survey's subsystem table, `lib/kit-log-dir.sh` (the shared helper ~9 source), `tests/` (the non-regression gate + any `find lib`/`ls lib` assertion).

## PR body

- Outcome: group `lib/` into subsystem subdirs + `lib/README.md` nav map, via a symlink shim so no reference breaks; the kit stops being a flat-32-file wall.
- Verification: full test suite green before+after + ref-resolution grep + README (inline).
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`.

## Notes
