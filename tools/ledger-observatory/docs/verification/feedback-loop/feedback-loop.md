# Verification: feedback-loop (SG-04)

Per-feature proof detail for the `feedback-loop` feature. The canonical index is
[`../../proof-of-done.md`](../../proof-of-done.md); this file holds the run detail + the
COVERAGE-DELTA. Spec: [`../../specs/SPEC-129-feedback-loop.md`](../../specs/SPEC-129-feedback-loop.md).

## What it proves

Anomaly detection over the SG-02 lens (one data path) that PROPOSES backlog rows via the existing
cc-backlog staging buffer and NEVER auto-files a board. The load-bearing safety property is the
false-positive negative control: a noise-floor lens state proposes NOTHING.

## Acceptance criteria

| # | Criterion (measurable) | Status | Evidence (case) |
|---|---|---|---|
| AC1 | an over-threshold fixture FIRES + `--propose` stages a `## [staged]` block | PASS | F-debt-over, F-cost-spike, F-misfire-over |
| AC2 | threshold correctness BOTH sides for all 3 detectors (at-boundary + floor-minus-one do not fire) | PASS | F-debt-under, F-cost-nospike, F-cost-boundary, F-cost-floor, F-misfire-boundary, F-misfire-floor |
| AC3 | FALSE-POSITIVE NC: a noise-floor state proposes NOTHING (0 staged blocks) | PASS | F-nc-noise (+ FB-1 falsifiability) |
| AC4 | PROPOSAL-NOT-AUTOFILE: board byte-identical after `--propose`, staged block consumable by `add-backlog` | PASS | F-proposal-not-autofile (+ FB-2 falsifiability) |
| AC5 | dedup/idempotency: `--propose` twice stages once | PASS | F-dedup |
| AC6 | the one `--threshold` tune flag works (suppress / make-fire), bad key/value exits non-zero | PASS | F-threshold-flag |
| AC7 | read-only over the ledgers: every source ledger byte-identical after detect+propose | PASS | F-readonly-nc |
| AC8 | detection reads via SG-02 only (imports `materialize`, no `duckdb`/adapters/raw-reader) | PASS | F-one-path (static) |
| AC9 | COVERAGE-DELTA recorded | PASS | this file |
| AC10 | SG-04 indexed in the multi-feature proof without overwriting 01/02/03 | PASS | proof-of-done.md index row |

## Confirmation (recorded runs)

| Run | When (UTC) | Command | Exit | Verdict |
|---|---|---|---|---|
| feedback suite | 2026-07-03T20:54Z | `bash tests/test-feedback.sh` | 0 | PASS (39/39) |
| FB-1 falsifiability (NC not vacuous) | 2026-07-03T20:55Z | noise fixture, default vs `--threshold debt_max=3` | n/a | staged 0 -> 1 (NC load-bearing) |
| FB-2 falsifiability (auto-file bug) | 2026-07-03T20:56Z | injected board-append into `stage_proposals`, ran `--propose` | n/a | board sha CHANGED (RED-as-expected); restored -> 39/39 |
| regression schema (SG-01) | 2026-07-03T20:56Z | `bash tests/test-schema-conform.sh` | 0 | PASS (11/11) |
| regression etl-cli (SG-02) | 2026-07-03T20:56Z | `bash tests/test-ledger-cli.sh` | 0 | PASS (26/26) |
| regression render (SG-03) | 2026-07-03T20:56Z | `bash tests/test-render-skill.sh` | 0 | PASS (30/30) |
| live smoke (real lens) | 2026-07-03T20:39Z | `uv run ledger anomalies --json` (no --propose) | 0 | debt fired (gates_ovr_sum=40), report-only, nothing staged |

### Negative controls (load-bearing, not vacuous)

- **FALSE-POSITIVE NC (F-nc-noise):** a NON-EMPTY near-boundary noise-floor lens (gate overrides
  sum 4 <= 5; 0 misroutes over 4 runs; costs flat, latest 1.1x median) proposes NOTHING (0 staged
  blocks). **FB-1** proves it is not vacuous: the SAME noise state with a deliberately-loose
  `--threshold debt_max=3` stages 1 (the assertion would go RED on a too-loose threshold).
- **PROPOSE-NOT-AUTOFILE NC (F-proposal-not-autofile):** the board `BACKLOG.md` is sha256
  byte-identical before/after `--propose`, and the staged proposal is listed by the real
  `add-backlog list`. **FB-2** proves it is not vacuous: injecting a board-append into
  `stage_proposals` flips the board sha256 (RED-as-expected); restore returns 39/39.
- **READ-ONLY NC (F-readonly-nc):** every source ledger (kit pipe-logs + tide sqlite) is sha256
  byte-identical after detect+propose. The tool's only write is the gitignored staging buffer.

## COVERAGE-DELTA

**Covered:** threshold correctness on BOTH sides for all three detectors (over fires; at-boundary
equality, no-spike, and both min-sample floor-minus-one cases do not fire); the false-positive
noise-floor NC (proposes nothing, proven load-bearing via FB-1); propose-not-autofile (board
byte-identical + the staged proposal consumable by the real `add-backlog` human gate, proven
load-bearing via FB-2); dedup idempotency (re-run stages nothing new); the single `--threshold`
tune flag (suppress + make-fire + bad-input rejection); the read-only-over-ledgers NC; and the
static one-data-path check (imports `materialize` only).

**Uncovered:** TRUE trend detection for misfire "climbing" (rate-vs-prior-window needs a
rate-history store that does not exist yet; scaffolded as rate-over-threshold with a min-sample
floor, per SPEC-129 Open questions); the dedicated understanding-DEBT and kit TOKEN ledgers as
their OWN lens tables (future kit sub-goals; the `debt` detector reads `kit_runs.gates_ovr`
overrides as the debt signal present in the lens today, DEC-004); the live `add-backlog`
PROMOTE->board write (the human gate, out of this tool's scope; exercised only via `add-backlog
list` here); real-data threshold TIGHTENING (open-fork 3: defaults are scaffolds, tuned after data
accrues); a rejected proposal never re-proposing even if the metric later worsens (known tradeoff,
SPEC-129 Open questions).

## Reproduce

```bash
cd ~/workspace/tieubao/ops-toolkit/tools/ledger-observatory && uv sync
bash tests/test-feedback.sh
```

## Rollback

Additive-only: a new `src/ledger_observatory/anomalies.py` module + one new `ledger anomalies` CLI
subcommand + tests + docs. `show`/`query`/`rebuild`/`render` are unchanged. The tool writes only
the gitignored cc-backlog staging buffer; no board, no ledger, no existing runtime is touched.
Rollback = `git revert` the branch or delete `anomalies.py` + the `anomalies` command; SG-01/02/03
are unaffected.
