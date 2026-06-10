# SPEC-061: Lane telemetry + the feedback loop

Status: SHIPPED
Date: 2026-06-10
Lane: normal
Type: spec-feature / behavioral

## Problem

The kit has many lanes and loops but no mechanism to evaluate whether they RUN effectively.
Run facts were recorded in pieces (gate-ledger per-run logs, completeness.log downgrades,
hook block logs, proof records) but nothing recorded the routing decision itself
(chosen-vs-classified lane, the work type, the repo), nothing recorded review verdicts or
outcomes in queryable form, and NOTHING aggregated any of it. The feedback loop was
open-circuit: a lane misfire died in chat instead of becoming a classifier fix + pin.
(Operator framing: "khi một công việc được đưa vào thì không có đánh giá, không tạo thành
một feedback loop để cải thiện.")

## Decision

Write side (one new verb, everything else reuses existing machinery):

1. `lib/gate-ledger.sh start <rid> <chosen-lane> <classified-lane> <type> [repo]` appends a
   `TS | START | lane=.. classified=.. type=.. repo=..` line to the run's existing ledger.
   Repo auto-detected from git. Called by `/kit:assign` right after the floor check.
2. Review verdicts reuse the EXISTING `record` verb: `/kit:review`, `/kit:review-team`,
   `/kit:devs-team` record `review ran "<verdict> findings=<K>"` after their verdict.
3. `/kit:ship`'s existing Ship record carries `pr=#<N>` as the run outcome.

Read side:

4. New `lib/lane-telemetry.sh` (pure bash/awk over the pipe-delimited ledgers; no new store,
   no daemon, no jq): `report` prints headline counts (runs, misrouted, shipped, untracked),
   a per-lane table (runs/mis/gates/skip/ovr/ships), a per-type table, and a per-run listing
   (rid, repo, lane<-classified, type, review verdict, first..last TS); `misfires` prints the
   chosen!=classified runs plus completeness.log LANE-CHECK lines, the direct feed for
   keyword fixes. A run with no START line surfaces as untracked (itself a signal).

Loop closure:

5. `/kit:retro` Step 1d (Lane telemetry sweep) with a **disposition contract**: every misfire
   leaves the retro as (a) a classifier keyword fix + truth-table pin (the SPEC-057/060
   pattern), (b) a kit BACKLOG row, or (c) a recorded "accepted noise" line. `/kit:start`
   nudges `misfires` when ledgers exist; `/kit:kit-health` probes that `report` parses.
6. WORKFLOW.md "How lanes are judged": the five signals (misclassification rate, gate
   skip/override rate, review findings curve, duration vs lane weight, untracked runs) with
   healthy/unhealthy readings. Telemetry proposes; the human at retro disposes.

## Deviations / notes

- **Median duration deferred**: BSD awk lacks `mktime`, so v1 lists first..last timestamps
  per run instead of computing durations; the WORKFLOW criterion reads off the listing. A
  portable duration calc is a follow-up if the eyeball read proves insufficient.
- README's lib listing predates several lib files (backlog, task-type-classify, gate-ledger,
  proof-*); this change adds only its own line + fixes the architecture.md lib inventory.
  The full README lib sweep is pre-existing drift, left for a doc pass.

## Acceptance criteria

- AC1: `gate-ledger.sh start` writes the START line; telemetry reads it back (round-trip).
- AC2: `report` aggregates correctly over a known fixture (counts, per-lane row, untracked).
- AC3: `misfires` names chosen-vs-classified pairs and passes through LANE-CHECK lines.
- AC4: retro carries Step 1d with the disposition contract; WORKFLOW carries the criteria;
  assign records START; ship carries pr=#N; review/review-team/devs-team record verdicts.
- AC5: no new store: everything lands in the existing `logs/` dir, pipe-delimited.

## Test plan

3 meta pins (start verb; telemetry lib + subcommands; wiring legs) + 6 fixture tests in
test-hooks.sh over a synthetic logs dir (headline counts, per-lane row, misfire pair,
LANE-CHECK passthrough, start-verb round-trip, negative control: strip the START line ->
the run goes untracked and the misroute count drops to 0).

## Verification

- `tests/test-hooks.sh`: 243/243 (237 + 6 new, incl. the in-suite negative control).
- `tests/test-meta.sh`: 419/419 (416 + 3 new pins).
- Live fixture smoke recorded in the PR body.

## Review

Date: 2026-06-10. Adversarial pass (correctness + robustness, fixture-probed not eyeballed)
on the full diff. Verdict: **SHIP 8/10**, 1 MEDIUM + 4 LOW; the MEDIUM + 3 cheap LOWs fixed
in-branch:

1. MEDIUM, architecture.md gained a double `))` and kept the stale "all three are" count.
   Fixed.
2. LOW, a review reason containing ` | ` was truncated in the report column. Fixed
   (re-join `$5..NF`).
3. LOW, a repo name with a space truncated the START KV blob. Fixed (space -> `-` at write).
4. LOW, missing blank line before retro `### Step 2`. Fixed.
5. LOW (accepted), kit-health's probe cannot distinguish fresh-install from empty-parse;
   exit-code still catches hard failures. Accepted as designed.

Cleared under adversarial fixtures: ` | ` in reasons does not break START parsing; rid
sanitization preserves dots/underscores; empty dir / empty log / CRLF logs all safe; START
lines invisible to `check`; `normalize_phase("review")` stable; the negative control is real
falsifiability. Post-fix suites: hooks 243/243, meta 419/419.
