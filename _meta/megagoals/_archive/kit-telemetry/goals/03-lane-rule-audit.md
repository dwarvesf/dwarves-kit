# Sub-goal 03: lane-classify rule-correctness audit

**Merge policy:** auto
**Time budget:** 2-4 hours.
**Proof:** findings doc with the misfire table (`lane-telemetry.sh misfires` output captured) + one truth-table-style pin (test case) per confirmed rule fix; a clean audit (no misfires confirmed) is a valid outcome, evidenced by the empty misfire capture.
**Depends on:** 01 (reads the durable misfire data).
Model: sonnet
Effort: high
**Branch:** feat/kit-telem-03-laneaudit
**PR base:** feat/kit-telem-01-ledger (stacked on 01, sibling of 02)

## Outcome

The task-shape -> lane mapping in `lib/lane-classify.sh` is audited against RECORDED reality: every misfire in the ledger corpus (lane downgrades, MULTI-START corrections, under-sized lanes the SG-06 escalation caught) is classified as rule-gap / rule-wrong / operator-error, and each confirmed rule fix lands with a pinned test case. This is the narrowed remainder of ops-toolkit ID-149 , the verifier-coverage and under-gating halves already shipped in kit-hardening (SG-04/05/06).

## Quality bar

Audit against the DATA, not by re-reading the classifier and nodding. Every proposed rule change carries the misfire that motivated it; no speculative rules for task shapes that have never occurred (YAGNI applies to classifiers).

## How to close the loop

SDD: `/spec` + `/spec-validate` first (ops board ID-149's reconciled row is the brief). Then:

```
cd dwarves-kit && bash lib/lane-telemetry.sh misfires   # captured into the findings doc
bash tests/test-lane-classify.sh                        # existing + new pins green
```

Findings at `docs/research/2026-07-02-lane-rule-audit.md`; each fix pinned in the classifier test suite. Gate-ledger records per phase.

**Done =** the findings doc exists with the captured misfire table and a disposition per misfire, and every confirmed rule fix has a green pinned test.

## Handoff on completion

1. Flip 03's ROADMAP box, PR # + SHA. Leave a NOTES line for the ops-toolkit ID-149 flip (cross-repo, done at close).
2. HOT `HANDOFF.md`: next = 04 (dashboard); carry which misfire classes are worth rendering.
3. WARM `DECISIONS.md`: rule changes made + rules deliberately NOT changed.
4. Report IN records, EXIT.

## Scope edges

**In:** the misfire audit, confirmed rule fixes + pins, the findings doc.
**Out:** the dashboard (04); verifier/gate machinery (shipped in kit-hardening); telemetry storage (01).
**Not:** a classifier rewrite; new lanes; speculative rules with no recorded misfire.

## Where to look

`lib/lane-classify.sh` (the rules), `lib/lane-telemetry.sh` (misfires read), the durable ledger corpus (01's path), `tests/test-lane-classify.sh` (or the suite covering it), ops board ID-149's reconciled Notes.

## PR body

Lane-classify rule-correctness audit against recorded misfires; findings + pinned fixes at `docs/research/2026-07-02-lane-rule-audit.md`. Narrowed remainder of ops-toolkit ID-149. Stacked on #<01's PR>; review after it. Roadmap: ops-toolkit `_meta/megagoals/kit-telemetry/ROADMAP.md`.

## Notes

<empty>
