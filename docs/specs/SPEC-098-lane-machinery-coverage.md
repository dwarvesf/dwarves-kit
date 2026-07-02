# SPEC-098: kit-machinery hard-gate covers the enforcement/orchestration/telemetry libs (read-helpers held at normal)

Status: VALIDATED
Date: 2026-07-02
Lane: full (changes the lane classifier's hard-gate rule set, an under-gating fix on an enforcement surface)
Type: reconcile (rule-correctness audit + confirmed fix)
Relates-to: SPEC-050 (flag-scoring classifier), SPEC-053 (floor guard), SPEC-094 (spec->build escalation)
Board: ops-toolkit ID-149 (narrowed remainder); kit-telemetry mega-goal SG-03

## Problem
The `kit-machinery` hard-gate flag in `lib/lane-classify.sh` (line 54) escalates
kit-internal work to the `full` lane by matching machinery tokens. Audited against the
task shapes that ACTUALLY occurred in the kit-hardening + kit-telemetry waves, its regex
covers `gate-ledger`, `ship-gate`, `lane-classify`, `proof-gate`, `task-type-classify`,
`goal-registry`, `dispatch-gate`, `backlog.sh`, `install.sh`, `adopt.sh`, `workflow.md`
but MISSES four libs that are equally enforcement/telemetry machinery:
`lane-telemetry`, `mega-merge`, `proof-ledger`, `kit-log-dir`, and (review completeness pass)
`orchestrate.sh`, `stack-merge`, `role-classify`, `goal-drafts`. Work on them classifies as
`normal`, under-sizing the lane for enforcement-surface changes. The remaining read/helper
libs (`precedent`, `route-suggest`, `spec-index`, `spec-next`, `verif-counts`) are
DELIBERATELY held at `normal` , they are read-back / navigation / counting helpers, not
enforcement surfaces.

Evidence (occurred shapes, `lib/lane-classify.sh classify`):
- `add a render subcommand to lib/lane-telemetry.sh` -> **normal** (should be full)
- `add a code-level guard to lib/mega-merge.sh` -> **normal**
- `log overrides in lib/proof-ledger.sh` -> **normal**
- `durable resolver in lib/kit-log-dir.sh` -> **normal**
- (control) `fix the parser in lib/gate-ledger.sh` -> full ✓

These are not speculative shapes: SG-01 (this wave) touched all four; SG-04/05 (dashboard,
merge-guard) touch `lane-telemetry`/`mega-merge`.

## Decision
Add the missing machinery lib basenames to the `kit-machinery` hard-gate regex:
`lane-telemetry|mega-merge|stack-merge|proof-ledger|kit-log-dir|orchestrate\.sh|role-classify|goal-drafts`.
`orchestrate` is anchored to `\.sh` because the bare word is common English (a non-kit
"orchestrate the launch" must NOT escalate); the rest are distinctive compounds. Nothing
else changes. The precedence order (backfill > tiny > hard-gate) is untouched, so a cosmetic
edit to one of these libs still classifies `tiny`.

**Known limitation (pre-existing, out of scope):** the hard-gate matches a textual MENTION
of a basename, not an actual diff touching the file, so a doc/research task ABOUT these libs
(e.g. "explain mega-merge.sh in the architecture doc") over-classifies to `full`. This
predates SPEC-098 (true for `gate-ledger` etc. already) and fixing it needs an edit-vs-mention
signal the classifier does not have (a rewrite, explicitly out of scope). Widening the token
set widens this surface; filed as a follow-up board row, not fixed here.

## Acceptance criteria
- AC1: `classify "add a render subcommand to lib/lane-telemetry.sh"` -> `full`.
- AC2: `classify "add a code-level guard to lib/mega-merge.sh"` -> `full`.
- AC3: `classify "log overrides in lib/proof-ledger.sh"` -> `full`.
- AC4: `classify "durable resolver in lib/kit-log-dir.sh"` -> `full`.
- AC1b-AC4b [completeness]: `orchestrate.sh`, `stack-merge`, `role-classify`, `goal-drafts` work -> `full`.
- AC5 [precedence preserved, negative control]: `classify "fix a typo in lib/lane-telemetry.sh"` -> `tiny` (tiny beats the hard-gate).
- AC5b [over-match negative control]: a bare-word `orchestrate` non-kit task -> `normal` (anchoring works); a read-helper lib (`route-suggest`) -> `normal` (held).
- AC6 [no regression]: previously-covered machinery (`gate-ledger`, `lane-classify`) still `full`; a plain feature (`add a date picker`) still `normal`; `test-meta.sh`, `test-hooks.sh`, `test-lane-escalation.sh` stay green.

## Tasks
- T1: `lib/lane-classify.sh` line 54 -- extend the `kit-machinery` regex.
- T2: `tests/test-lane-classify.sh` (new) -- pin AC1-AC6 (the classifier's first dedicated behavioral suite).
- T3: `docs/research/2026-07-02-lane-rule-audit.md` -- the audit findings + misfire dispositions.
- T4: `docs/verification/lane-rule-audit.md` -- table-first proof.

## Verification
```
bash tests/test-lane-classify.sh   # AC1-AC6
bash tests/test-meta.sh            # stays green
bash tests/test-hooks.sh           # stays green
bash tests/test-lane-escalation.sh # stays green
```

## Out of Scope
- The 9 recorded floor-check downgrades: they are one test fixture repeated (test-hygiene
  noise filed as ID-087), not real operator misroutes; no rule change follows from them.
- A classifier rewrite; new lanes; any speculative rule for a shape that never occurred.
- Fixing the fixture pollution itself (ID-087) or the START-wiring (ID-085).

## Decision Log
- DEC-001: audit against RECORDED reality (misfires) found ZERO real lane-misroutes; the
  real fix came from a rule-correctness spot-check on occurred task shapes, which the
  contract explicitly permits ("audit against the DATA, not by re-reading the classifier
  and nodding" -- the spot-check IS data: real shapes run through the live classifier).
- DEC-002: added only the four lib basenames, not a generic "telemetry"/"ledger" word,
  to avoid over-matching unrelated tasks; precedence protects cosmetic edits.
