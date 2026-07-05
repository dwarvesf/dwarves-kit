# Sub-goal 04: feedback loop (anomaly -> proposed backlog row)

**Merge policy:** auto
**Time budget:** 3-4 hours.
**Proof:** run-table with COVERAGE DELTA: an anomaly (unpaid-debt count over threshold / cost spike vs median / misfire-rate climbing) is DETECTED over the ledger state · it PROPOSES a backlog row via `work-intake` into the cockpit boards · threshold correctness (a value just over the cutoff fires, just under does NOT) · FALSE-POSITIVE NEGATIVE CONTROL: normal / noise-floor ledger state proposes NOTHING (does not spam the board) · a proposed row is a PROPOSAL, never an auto-file. A COVERAGE-DELTA row names covered + uncovered.
**Depends on:** 02 + 03.
Model: opus
Effort: high
**Branch:** feat/lo-04-feedback
**PR base:** feat/lo-03-render

## Outcome

Anomaly detection over the ledger state (queried via 02) that closes the feedback loop , the thing that stops the ledgers being WRITE-ONLY. It watches for defensible anomalies: unpaid-debt count over a threshold (debt ledger), a cost spike vs the rolling median (token ledger), a gate/proof misfire-rate climbing, etc. When one fires it PROPOSES an improvement backlog row via `work-intake` into the cockpit boards (`_meta/boards.txt`) , a proposal the operator accepts/rejects, NEVER an auto-file. The loop: ledgers -> lens -> anomaly -> proposed board row -> improvement.

## Quality bar

It PROPOSES, never auto-files (respects work-intake's understand-before-landing contract). The FALSE-POSITIVE control is load-bearing: noise-floor state must propose NOTHING, or the board fills with garbage and the loop is worse than nothing. Thresholds are DEFENSIBLE defaults + one flag to tune (open-fork 3: /spec pins after real data accrues). Detection reads via 02 (one data path), never a re-query.

## How to close the loop

`/spec` + `/spec-validate` first (pin the anomaly set + the default thresholds + the work-intake proposal shape; resolve open-fork 3 with defensible defaults). Then `/kit:test-plan` + `bash tests/test-feedback.sh`: an over-threshold fixture fires + proposes a row, the just-under fixture does NOT (threshold correctness), the noise-floor fixture proposes nothing (false-positive NC), and a proposed row lands as a PROPOSAL (not auto-committed). Capture the COVERAGE-DELTA row. Assumptions: ROADMAP 04 + open-fork 3.

**Done =** an over-threshold anomaly detected over the 02 state proposes a work-intake board row, threshold correctness holds (over fires / under does not), the noise-floor false-positive NC proposes nothing, rows are proposals not auto-files, the COVERAGE-DELTA row is recorded, tests green.

## Scope edges

**In:** the anomaly detectors (over 02's queryable state), the default thresholds + tune flag, the work-intake proposal path, tests + coverage-delta.
**Out:** the CLI (02); the render surfaces (03); the docs (05).
**Not:** auto-filing rows (propose only, via work-intake); a threshold so loose it spams the board (the false-positive NC guards this); a second data path (detect via 02); moving/mutating any ledger.

## Where to look

the `work-intake` skill (the propose-into-cockpit contract , propose, do not auto-file), `_meta/boards.txt` + the `board`/`board-all` cockpit, SG-02's `ledger query` (the state to detect over), the debt ledger (understanding-gate SG-02) + token ledger (kit-face SG-03) as anomaly sources, the research Addendum (anomalies -> work-intake -> board rows).

## PR body

Feedback loop (the write-only fix): anomaly detection over the ledger state (unpaid-debt / cost-spike / misfire-rate) that PROPOSES improvement backlog rows via work-intake into the cockpit boards , proposals, never auto-files. Stacked on #<03's PR>; review after it. Verify: `bash tests/test-feedback.sh` (threshold correctness + false-positive NC + proposal-not-autofile) + coverage-delta. Roadmap: ops-toolkit `_meta/megagoals/ledger-observatory/ROADMAP.md`.

## Notes

<empty>
