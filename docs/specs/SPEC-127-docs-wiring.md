# SPEC-127: understanding-axis docs + no-orphan wiring check

Status: VALIDATED
Lane: normal
Type: spec-feature
Relates-to: ADR-0031 (the understanding gate: design record + explainer/quiz), SPEC-122
(design-record), SPEC-123 (significance-classify), SPEC-124 (explain-command), SPEC-125
(quiz-gate), SPEC-126 (weekend-batch), `docs/decisions/0032-megagoal-execution-hygiene.md`
(the "every new artifact must prove a live invocation path" lesson this sub-goal enforces
mechanically), the ops-toolkit `understanding-gate` mega-goal (SG-06, the FINAL, docs-last
sub-goal)

## Problem

SG-01..05 shipped the understanding-gate machinery (design record, significance-classify,
`/kit:explain`, `/kit:quiz-gate`, weekend-batch) directly to master. Each PR already touched
`WORKFLOW.md` / `README.md` / `docs/architecture.md` piecemeal as it landed, so the contract
docs are NOT silent on the axis -- but they are scattered (a depth-matrix row here, a
gate-ledger bullet there, a README table row somewhere else) and, per a live repo sweep,
**one of the five shipped artifacts over-claims its own wiring**: `WORKFLOW.md`'s
"Understanding-debt marker" bullet reads "at Ship, run `bash lib/significance-classify.sh
record <rid> ...`" as if this is a live step of `/kit:ship`, but `commands/ship.md` (the
actual operative file `/kit:ship` executes) never calls `significance-classify.sh record` --
confirmed by `docs/implementation-notes/significance-classify.md`'s own 2026-07-03 entry
("no command ... actually invokes `significance-classify.sh record` yet"). This is exactly the
c6fbd99 bug class this mega-goal's own kill-resilience lesson names: a doc claim with no
dispatch path behind it.

This sub-goal is the FINAL, docs-last pass: consolidate the scattered declarations into one
coherent "understanding axis" story, correct the one over-claim found, add the one missing
declaration (`AGENTS.md` currently has zero mention of ADR-0031), and ship a mechanical sweep
that catches this bug class going forward instead of relying on a human noticing it.

## Solution

### Approaches considered

1. **Leave the scattered declarations as-is, just patch the one over-claim.** Rejected: the
   contract asks for the axis declared coherently (BEFORE beat + AFTER beat + the debt-budget
   model in one place), and three scattered `| DEBT |`/nudge bullets under an ADR-0024 section
   ("Gate ledger and ship enforcement") is the wrong home for an ADR-0031 concept; drift risk
   is why the audit trail exists.
2. **A dedicated `## The understanding axis (ADR-0031)` section in `WORKFLOW.md`**, replacing
   the two scattered gate-ledger bullets with a pointer, adding the weekend-batch mention that
   is currently entirely absent, and stating the wiring gap honestly instead of silently. Chosen:
   single source of truth for the axis, no duplication, matches the doc-compaction discipline
   already used elsewhere in this file (e.g. "Design record" cross-references rather than
   restating).

### Chosen approach + why

Chosen approach 2. It is the minimum edit that makes the axis legible as ONE story instead of
three uncoordinated bullets, and it is the only option that lets the sweep test assert something
meaningful (a single section to check for the axis's presence, rather than grepping for
scattered fragments).

## Design

<!-- ADR-0031 §1 collapse-to-obvious: this spec is docs-wiring + a mechanical test script, not
     design-bearing. No new component/module (WORKFLOW.md/AGENTS.md prose edits + one new
     tests/test-understanding-wiring.sh in the existing tests/ pattern), no schema/data-model
     change, no external integration, no irreversible choice, and exactly one viable approach
     for the sweep script (grep-based static assertions over the shipped artifacts' known call
     chains, the same shape as every other tests/test-*.sh in this repo). -->
obvious: docs-only prose declarations + one grep-based static test script in the repo's existing
`tests/test-*.sh` shape; no new component, schema, integration, or irreversible choice.

## Technical Design

### Interfaces (I/O contract)

- Inputs: the repo's own shipped files (`WORKFLOW.md`, `AGENTS.md`, `README.md`,
  `commands/*.md`, `lib/*.sh`) -- the sweep reads them as static text via `grep`, never executes
  the kit commands themselves.
- Outputs: `tests/test-understanding-wiring.sh` (pass/fail per artifact + the negative control),
  runnable standalone or via `tests/test-meta.sh`'s discovery.
- Invariants: the sweep must FAIL (not silently pass) when a WORKFLOW.md claim's referenced
  command/lib file no longer contains the call it claims; the negative-control fixture must
  independently prove the sweep is capable of catching an over-claim, not just proving nothing UN-tested.

## Task Breakdown

- [ ] TASK-001: Consolidate the understanding-axis declarations into one `## The understanding
      axis (ADR-0031)` section in `WORKFLOW.md` (BEFORE beat, AFTER beat, debt-budget model,
      weekend-batch, the honest wiring-gap note); replace the two scattered gate-ledger bullets
      with a pointer to it.
- [ ] TASK-002: Add a short, orthogonal mention of the axis to `AGENTS.md` (advisory, does not
      change "Done means").
- [ ] TASK-003: Verify `README.md`'s existing `/kit:explain` + `/kit:quiz-gate` entries are
      accurate against the live wiring found (no edit needed if they already are; this task is a
      verification, not necessarily a diff).
- [ ] TASK-004: Write `tests/test-understanding-wiring.sh`: assert WORKFLOW.md + AGENTS.md
      declare the axis, README notes `/kit:explain`; sweep all 5 artifacts for a live dispatch
      path; a negative-control fixture proves the sweep catches an injected over-claim.

## Verification

```
bash tests/test-understanding-wiring.sh
bash tests/test-meta.sh
```
Both must exit 0. The negative-control assertion inside `test-understanding-wiring.sh` must
itself be green (i.e. the sweep correctly FLAGS the injected fake over-claim; the test suite
asserts the flag was raised, not the absence of one).

## Test plan

| Category | Case | Expected |
|---|---|---|
| Declaration | WORKFLOW.md has a `## The understanding axis` section mentioning ADR-0031, design record, explainer, quiz-gate, weekend-batch | present |
| Declaration | AGENTS.md mentions the understanding axis / ADR-0031 as advisory | present |
| Declaration | README.md commands table/ASCII block lists `/kit:explain` | present (already shipped by SG-03) |
| No-orphan (positive) | Design record: `commands/spec-validate.md` contains the Reviewer 6 blocking enforcement | live dispatch path found |
| No-orphan (positive) | significance-classify: `lib/quiz-gate.sh` calls `significance-classify.sh classify` | live dispatch path found (classify verb) |
| No-orphan (honest gap) | significance-classify: no `commands/*.md` calls `significance-classify.sh record` | absence CONFIRMED and documented, not papered over |
| No-orphan (positive) | `/kit:explain`: `commands/explain.md` exists (auto-registered plugin command) | live dispatch path found |
| No-orphan (positive) | quiz-gate: `commands/ship.md` Step 8 calls `lib/quiz-gate.sh tap` | live dispatch path found |
| No-orphan (positive) | weekend-batch: the ops-toolkit `weekend-debt-paydown` skill invokes `lib/weekend-batch.sh collect` | live dispatch path found (cross-repo, documented) |
| Negative control (over-claim) | fixture WORKFLOW.md line claims a fake lib call with no matching invocation anywhere in the repo | sweep FLAGS it (non-zero / explicit FAIL) |

**Coverage delta:** 0 -> 1 test file (`tests/test-understanding-wiring.sh`), 0 -> ~10 assertions
(5 artifacts x positive-or-honest-gap + 3 declaration checks + 1 negative control), 0 -> 1
mechanical guard against the c6fbd99 over-claim bug class for the understanding-gate mega-goal's
own docs.

## After state

- `WORKFLOW.md` has one coherent `## The understanding axis (ADR-0031)` section; the two
  scattered gate-ledger bullets are replaced by a pointer (no duplicated source of truth).
- `AGENTS.md` mentions the axis as advisory/orthogonal.
- `README.md` is verified accurate (edited only if a gap is found).
- `tests/test-understanding-wiring.sh` exists, is green, and is picked up by `tests/test-meta.sh`
  or the CI suite's `test-*.sh` discovery.
- `docs/implementation-notes/docs-wiring.md` records the DELTA, especially the significance-
  classify `record` wiring gap found and how it was documented (not silently fixed -- fixing
  `commands/ship.md` is SG-02/04 machinery, out of scope for this docs-last sub-goal).

## Scope edges

In: `WORKFLOW.md`, `AGENTS.md`, `README.md` (verify/adjust only), `tests/test-understanding-
wiring.sh`, this spec, its impl-notes, its proof-of-done.
Out: `commands/ship.md` or any other machinery file (01-05 are done); the ADR (0031, already
written); a fourth doc surface.

## Open questions

- Should `significance-classify.sh record` gain a live caller in `commands/ship.md`? Out of
  scope here (machinery); flagged in impl-notes + the final report for the conductor to decide
  whether it is a follow-up sub-goal or accepted as a permanent manual/opt-in step.
