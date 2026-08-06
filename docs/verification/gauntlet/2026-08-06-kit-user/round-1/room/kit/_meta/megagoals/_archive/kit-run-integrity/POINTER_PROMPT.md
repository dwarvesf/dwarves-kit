# POINTER_PROMPT , kit-run-integrity

RUN CONTRACT: `_meta/megagoals/OPERATE.md` is BINDING (run-mode, strips, visible close, checkpoint discipline). This run's cwd is `dwarves-kit`; reference OPERATE.md by its absolute path `~/workspace/tieubao/ops-toolkit/_meta/megagoals/OPERATE.md`.

Objective: make dwarves-kit's autonomous run layer MEASURABLE + COLLISION-SAFE + HONESTLY-PROVEN. 6 sub-goals (2026-07-02/03 benchmark kit-side follow-ups): 01 gate-outcome emit (`caught=` + `START`/`END`), 02 wavefront SPEC-number race fix, 03 coverage-delta gate (advisory), 04 mutation smoke (advisory), 05 generated proof-table, 06 docs-wiring. Scaffold in ops-toolkit `_meta/megagoals/kit-run-integrity/`; BUILD in dwarves-kit.

Run mode SUBAGENT-DELEGATE (thin conductor). Ready-set from `Depends on:`. 02 FIRST (fixes the race a parallel wave hits), merge it, then {01,03,04,05} PARALLEL over master-with-02, then TIER-4, then 06 LAST (HELD for Han). Each subagent: isolation:worktree, model from `Model:`, prompt = the goal file's contract; `bash lib/lane-classify.sh classify`, run that lane; `/spec` + `/spec-validate` BEFORE code (02/03/04 design-bearing -> `## Design`); `/kit:execute`; OVER-TEST 03+04 via `/kit:test-plan` (coverage-delta row + false-positive NC); commit at phase boundaries (kill-resilience); record gates via `bash lib/gate-ledger.sh record` per-gate. Branch `feat/kri-NN-<slug>`. ROADMAP line -> `PR #N` on open; `[x] ... merged <sha>` on merge.

HARD CONSTRAINTS: additive marker (01 reuses `gate-ledger.sh`); reuse `spec-next.sh` (02 moves WHO/WHEN, not a rewrite); GENERATE the proof table (05, never hand-author); 03/04 advisory-not-block (a block needs Han's bless). Belt-and-suspenders: the conductor PRE-ASSIGNS the wave's SPEC block by hand (dispatch is via the Agent tool, not orchestrate.sh).

TIER-4 (after 01-05 merge, before 06): integration-verifier against the objective + NO-ORPHAN CHECK over every new gate/emit (defined-but-never-dispatched = blocking); `/kit:review-team` security lens; advisor BOTH modes (incl. the advisory->block question) -> NOTES `## Proposed additions`. Then the visible close (RUN_REPORT.md + chat timeline).

STOP: success = 01-06 merged (06 held as final), TIER-4 clean. Else stop on a genuine blocker (unchanged prerequisite) or token out. PR audits target `dwarvesf/dwarves-kit`.
