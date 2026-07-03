# Implementation notes: quiz-gate (SPEC-125, SG-04)

The DELTA from SPEC-125. Decisions the spec did not pin down, deviations, and constraints found while
building. Not a mirror of the spec.

## 2026-07-04 12:00 Human response recorded via a NEW `debt-response` verb, not by overloading `debt`

Context: the three responses (engage/defer/wave) must land in the debt ledger. The existing
`gate-ledger.sh debt` verb REQUIRES `significance=`/`worthiness=`/`verdict=` and validates `verdict` against
`tap|wave|not-significant` , it writes the CLASSIFIER's verdict, not a human choice.
Decision: added a new additive verb `gate-ledger.sh debt-response <rid> <engage|defer|wave> [reason]` that
writes a `| DEBT | response=<r>` line, rather than overloading `debt` with a dummy classification.
Why: the `debt()` header comment already anticipated exactly this ("the human-facing ★-tap nudge
(engage/defer/wave) is a LATER, SEPARATE `| DEBT |` line appended by the conductor-side nudge (SG-04)").
A dedicated verb keeps the classifier-verdict line and the human-response line cleanly distinct and
self-documenting; overloading `debt` would have meant passing meaningless sig/wor/verdict values.
Alternatives: (a) overload `debt` with a `response=` field , rejected, forces dummy required fields;
(b) write the ledger line directly from quiz-gate.sh , rejected, the ledger's write discipline
(oneline() newline-collapse, RUNS_DIR resolution, redaction) lives in gate-ledger.sh and must stay the
single writer. Impact: one small additive verb in a heavily-tested lib; `check()/override()/descent()/
_rows()` already ignore every `| DEBT |` line, so the new line inherits the "never fakes a gate" property.

## 2026-07-04 12:05 Lane escalated normal -> full (touches lib/ + merge boundary)

Context: `lib/lane-classify.sh classify` returned `normal` for the task description.
Decision: ran the FULL lane instead, and used a multi-lens review (SPEC-069).
Why: the change adds a new `lib/` file AND an additive verb to `lib/gate-ledger.sh` AND wires the merge
boundary; the sub-goal contract instructed full-if-lib/-or-merge-boundary, and SPEC-069 requires
multi-lens review for any run touching `lib/`. Recorded the escalation in the gate ledger. Impact: extra
design-phase gate records (think/design/design-critique/validate/design-record), all satisfied by the
ADR-0031 upstream reasoning + the spec's `## Design` block + the dispatched multi-lens review.

## 2026-07-04 12:10 The tap decision is keyed on significance-classify, with a second anti-fatigue guard on PR-kind

Context: ADR-0031 says the tap fires on a `tap` verdict on a `gate`/gated-final PR.
Decision: `quiz-gate.sh tap` applies TWO guards , (1) `--pr-kind` must be `gate`/gated-final (default
`gate`), else silent; (2) `significance-classify classify` must return `tap`, else silent. The verdict is
never re-derived inside quiz-gate.sh; it delegates to the single-source classifier (SPEC-123).
Why: the spec's wiring NC only enumerated the verdict cases (tap/wave/not-significant); the PR-kind guard is
the ADR's "on a gate PR" clause made mechanical. Added a fourth wiring assertion (non-gate PR is absent even
when the verdict is `tap`) to cover it. Impact: no drift risk , quiz-gate holds zero copy of the risk-flag
regexes; it asks the classifier.

## 2026-07-04 12:15 Questions reuse lib/explain.sh (git-ref-only) for the grounding guarantee

Context: the hard constraint is questions-from-diff-not-narrative.
Decision: `questions`/`route` take a git ref ONLY and build the material from `lib/explain.sh order` +
`lib/explain.sh tests` + the raw `git diff` `+` lines. No narrative/intent argument exists on any verb.
Why: reuses SPEC-124's architectural guarantee (a lib whose only input is git cannot emit a false
narrative) instead of re-deriving it. The grounded NC (AC4) feeds a fixture whose commit body + an
untracked file lie ("multiply") over a diff that adds `subtract`; the quiz names `subtract`, never
`multiply`, because there is no channel for the lie. Impact: the guarantee is structural, not a prose
promise.

## 2026-07-04 12:20 Doc companions a new command owes for CI

Context: a new `commands/*.md` trips several test-meta parity pins.
Decision (no spec delta, recording the CI surface): added the `/kit:quiz-gate` row to
`docs/architecture.md`'s Command/agent V-phase inventory (hard parity == command+agent file count), bumped
the README `<b>Commands</b> (28 -> 29)` summary count (asserted), and added README command-list +
command-table + MANUAL entries. The minimal WHEN-it-fires wiring lines went to WORKFLOW.md (after the
Understanding-debt marker bullet) and `commands/ship.md` (Step 8); the understanding-axis NARRATIVE stays
for SG-06. Impact: `bash tests/test-meta.sh` green at 667/667.

## 2026-07-04 12:40 Multi-lens review fixes (SPEC-069): a real code gap + 4 coverage gaps

Context: the SPEC-069 multi-lens review (security + architecture + test-coverage, fresh-context) came back
security CLEAN, architecture 10/10, test-coverage 7/10 with 2 MAJOR + 3 MINOR findings.
Decision: fixed all five. One was a REAL CODE gap, not just a test gap:
- **MAJOR-2 (code fix):** `_primary_file` fell back to the first changed file (a doc) on a docs/tests-only
  change, so the `cmd_questions` "touches only docs/tests" Q3 branch was dead code and a doc got
  mis-labeled as the primary code file. Fixed `_primary_file` to print NOTHING (empty) for a
  docs/tests-only change, so the intended branch fires. Added a docs/tests-only fixture asserting it.
- **MAJOR-1 (test fix):** the AC2 "never masquerades as a GATE" check counted `| GATE |` lines in a
  DEBT-only ledger , tautological (the writer hardcodes `| DEBT |`). Replaced it with a BEHAVIORAL check:
  a DEBT-only ledger run through the real `gate-ledger.sh check full <rid>` must still report
  `MISSING-GATE`. This exercises `check()`'s reader; a regression widening its awk predicate to match DEBT
  would now fail.
- **MINOR-3/4/5:** added a range-ref (`A..B`) case, a no-recorded-proof case asserting Q4 falls back to
  `[no recorded test result]` (the honesty guarantee, on the existing narrative-NC fixture), and an
  each-of-Q1..Q5-exactly-once check (a dup+drop would still count 5).
Why: MAJOR-2 was a genuine behavioral bug the negative-space of the original fixtures hid. Impact: test grew
24 -> 29 assertions, all green; `test-meta` still 667/667; siblings unaffected. Architecture + security lenses
found nothing to fix.
