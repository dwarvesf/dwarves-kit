# SPEC-067: The golden run: an end-to-end harness

Status: SHIPPED
Date: 2026-06-10
Lane: normal (classified: normal)
Type: spec-feature / behavioral
Board: ID-055

## Problem

700+ unit pins prove each part in isolation; NOTHING proved the parts agree. The 3-day
machinery (board, classifiers, START, plan/progress, gates, telemetry, trace) is wired
across five lib files and consumed by three read surfaces; a column shift, a renamed
phase, or a format change one consumer missed would pass every unit pin and break the
loop silently.

## Decision

`tests/test-e2e.sh`, a third suite run by CI: build a temp world (repo with a board +
marker, isolated DWARVES_KIT_LOG_DIR), walk ONE task through the whole loop (board pull
-> classify both axes -> START with the full routing tuple -> plan announces the road ->
progress opens at step 1 -> grill/think/spec/test-plan(skip-with-reason)/build/review/
docs/ship -> check), then assert the three read surfaces tell the SAME story:

- gate-ledger: `check` green; `progress` reads complete (8/8) with mid-run pointer
  asserted at step 4.
- lane-telemetry: the run + ship counted, no misroutes, the review verdict surfaces in
  the report, `trace` renders the routing header and the ship line.
- backlog: the row walked queued -> claimed -> shipped.

Drift control built in: a deliberately misrouted second START must be SEEN by all three
(report count, misfires pair, trace flag).

## Found during build (disposition per the retro contract)

The harness's FIRST execution caught a real classifier over-match: "add a --version flag
to the demo CLI" -> data-tool (the bare `cli` anchor steals feature-work-ON-a-cli).
Filed as board ID-057; the golden run pins the clean phrase and carries the note.

## Acceptance criteria

- AC1: the golden run passes 20/20 against a fresh temp world.
- AC2: the drift control proves a misroute is visible on report + misfires + trace.
- AC3: CI runs the suite (third step in test.yml); meta pin guards both.

## Test plan

The harness IS the test. Negative control: the drift-control block is itself the
falsifier (a misrouted START that all surfaces must flag); additionally, run live during
build: the first fixture phrase legitimately failed classification (19/20), proving the
harness catches real classification drift, then the finding was dispositioned.

## Verification

- `bash tests/test-e2e.sh`: 20/20 (Golden run green).
- `tests/test-hooks.sh`: 301/301; `tests/test-meta.sh`: 424/424 (+1 pin).
- CI: third suite step added to .github/workflows/test.yml.

## Review

Date: 2026-06-10. Focused adversarial pass (isolation, swallowed failures, CI portability
probed by running). Verdict: **FIX-FIRST 6/10**, 1 HIGH + 2 MEDIUM + 2 LOW, all fixed:

1. HIGH, the proof doc itself contained a phrase banned by the SPEC-031 lint, breaking
   test-meta (and the doc claimed a green count that was false at that moment). Fixed +
   re-verified; a proof doc that breaks the suite it cites is the exact failure class
   this kit exists to catch.
2. MEDIUM, `GL start` failures were swallowed by blanket suppression, which would mint 19
   false PASSes against a malformed world. Now loud (`|| bad + exit`).
3. MEDIUM, no trap cleanup; temp worlds accumulated. `trap rm EXIT` added.
4. LOW, the deliberate `-e` omission was undocumented. Comment added.
5. LOW, BRE semantics of the expect helper undocumented. Comment added.

Cleared: isolation real (log dir + BACKLOG_FILE overrides honored), idempotent runs,
CI-portable (POSIX mktemp, no nested-repo issue), the drift-control block is a genuine
always-on falsifier. Post-fix: e2e 20/20, meta green, hooks green.
