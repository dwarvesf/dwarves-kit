# Spec: flag-scoring lane classification + auditable `explain`

Status: DRAFT
Lane: full

## Problem

`lib/classify/lane-classify.sh` is a first-match keyword grep: the first regex group that hits wins, and a
description with no high-risk keyword falls straight to `normal`. This under-classified BOTH
kit-machinery PRs on 2026-06-10 (`adopt @AGENTS.md loader`, `ship AGENTS.md into the install`) as
`normal` when they were `full`; the operator had to override by hand. The model is also opaque: it
prints a lane with no trace of WHY, so an override is a judgment call with nothing to audit.

## Solution

### Approaches considered

- **A. Add more keywords to the `full` branch.** Cheapest, but it does not fix the opacity and the
  next un-keyworded full-lane change slips through again. Treats the symptom.
- **B. Take file paths as input (touches `lib/` -> full).** Richer signal, but the classifier's
  one input is a one-line description (it runs at intake before any diff exists). A bigger interface
  change than the gap warrants.
- **C. Flag-scoring model (chosen).** Absorb repository-harness's FEATURE_INTAKE shape: named risk
  flags, hard-gate flags that force the top lane, soft flags counted with a threshold, plus an
  `explain` mode that prints which flags fired. Keeps the description-only interface, fixes the
  opacity, and adds a `kit-machinery` hard-gate flag that catches the exact 2026-06-10 miss.

### Chosen approach + why

C. The win that B and A both miss is auditability: `explain` makes a classification (and any
override) defensible. A `kit-machinery` hard-gate flag is the description-level signal that closes
the real gap (a change naming `adopt` / `gate-ledger` / `ship-gate` / `lane-classify` / `install.sh`
/ `WORKFLOW` / `proof-gate` is always `full`). Rejected B's file-path input as out of proportion;
the classifier stays a pure description->lane function.

### Extensibility & boundaries

- Load-bearing dimension: the flag set. Adding a risk signal = one `name|regex` row in the hard or
  soft table, not a control-flow edit. The decision tree (hard -> full; soft 4+ -> full; 2-3 ->
  normal-noted; else lighter rules) is fixed.
- Boundary: still `classify "<desc>" -> one of {tiny,normal,full,bug,backfill}`, exit 0. New
  `explain` and `flags` subcommands are additive. No consumer (`/kit:assign`, `/kit:dispatch`)
  contract changes; they still read the lane on stdout.

## Technical Design

### Interfaces (I/O contract)

- `classify "<desc>"` -> prints one lane, exit 0. UNCHANGED contract.
- `explain "<desc>"` -> prints the lane, then `reason:` and `flags:` lines. NEW (additive).
- `flags` -> lists the flag names. NEW (additive).
- Invariant: the 5 lane names are unchanged; the 5 currently-pinned classifications
  (`test-hooks.sh`) still hold; precedence backfill > tiny > hard-gate > bug > soft-count is
  preserved so a keyword inside a doc task (e.g. `write its AGENTS.md`) does not escalate.

### Flags

Hard-gate (any one -> `full`): `auth`, `data-model`, `audit-security`, `external-provider`,
`public-contract`, `weaken-validation`, `kit-machinery` (NEW). Soft (counted): `cross-platform`,
`existing-behavior`, `weak-proof`, `multi-domain`, `concurrency`.

## Task Breakdown

### Phase 1
- [ ] TASK-001: Refactor `lib/classify/lane-classify.sh` to the flag-scoring model with a single
  `classify_core` that sets LANE/REASON/FIRED; `classify` prints LANE, `explain` prints all three.
  Acceptance: the 5 pinned classifications hold; the kit-machinery descriptions now return `full`;
  `set -euo pipefail` clean.
- [ ] TASK-002: Tests in `test-hooks.sh`: the 5 preserved + kit-machinery -> full (the two
  2026-06-10 descriptions) + `explain` prints fired flags + a 4-soft-flag description -> full.

## After state
- [ ] `lane-classify.sh classify "rewrite lib/classify/lane-classify.sh ..."` returns `full` (Today: `normal`).
- [ ] `lane-classify.sh explain "ship AGENTS.md into the install"` shows `flags: ... kit-machinery`.
- [ ] The 5 pre-existing `test-hooks.sh` lane assertions still pass.

## Acceptance Criteria (global)
- [ ] `bash tests/test-hooks.sh` passes (old + new lane assertions).
- [ ] `bash tests/test-meta.sh` 395/395 (existence + wiring unchanged).
- [ ] No `/kit:assign` or `/kit:dispatch` change needed (lane on stdout is unchanged).

## Verification
`bash tests/test-hooks.sh && bash tests/test-meta.sh`, plus the live `classify` + `explain` runs
recorded in `docs/verification/lane-classify-flags.md`.

## Edge Cases
1. `write its AGENTS.md operating-layer docs` -> `backfill` (backfill is checked before the
   kit-machinery hard-gate, so the doc keyword does not escalate).
2. Empty description -> `normal`.
3. A typo task mentioning `auth` -> `tiny` (tiny precedence preserved over hard-gate).

## Out of Scope
- File-path input (approach B); the lane/proof taxonomy; the 5 lane names; consumer commands.

## Decision Log
- DEC-001: chose flag-scoring (C) over more-keywords (A) and file-path input (B). Auditability +
  the kit-machinery hard-gate are the real wins; description-only interface preserved.
- DEC-002: `kit-machinery` is a HARD gate (not a soft flag): a change to the gate machinery is
  always full, no count needed. This is the line that fixes the 2026-06-10 miss. `\badopt\b` is
  scoped (review): bare "adopt" (e.g. "adopt a convention") no longer escalates; only `adopt @`,
  `adopt.sh`, `kit:adopt`, or `adopt <near a kit noun>` does.
- DEC-003: the change is escalation-only for risky surfaces. `security` is retained as a hard-gate
  (audit-security). `validation` was deliberately NARROWED from the old bare keyword to
  weaken/remove/disable-validation only: ADDING validation is a normal feature, only WEAKENING it
  is high-risk. So "add input validation" -> normal is a precision fix, not a safety downgrade;
  nothing security-relevant drops a lane.
