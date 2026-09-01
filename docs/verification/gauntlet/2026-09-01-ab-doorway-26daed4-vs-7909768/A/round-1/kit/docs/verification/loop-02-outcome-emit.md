# Proof of done: OUTCOME emit sweep (SPEC-193, harness-loop sub-goal 02)

VERDICT: PASS

## Acceptance criteria (goal file `_meta/megagoals/harness-loop/goals/02-outcome-emit-sweep.md`)

1. Inventory the delta (`record ... ran` sites missing an OUTCOME bracket), recorded in the spec.
2. Wire brackets at every site; capture a fixture run's ledger slice showing paired `OUTCOME | <phase> | start/end`.
3. `uv run stats mega-durations` over the fixture root: non-empty row, plausible duration.
4. Negative control: a pre-change ledger renders honest-empty, exit 0.
5. `tests/test-outcome-emit-sweep.sh` (the standing coverage lint) green, plus the full suite.

## Inventory delta

22 `record <rid> <phase> ran ...` sites across 15 `commands/*.md` files had no paired
`| OUTCOME |` bracket. Full table (file, phase, `<rid>` form, `caught=` derivation):
`docs/specs/SPEC-193-outcome-emit-sweep.md` "## Inventory (the delta, per goal step 1)".

One additional site was discovered mid-sweep and is NOT part of the 22: `commands/ship.md`'s
own `record <rid> Ship ran ...` line was excluded from the goal's literal inventory command
(`rg -v outcome` accidentally filtered it -- the line's own prose happens to contain the word
"outcome" in an unrelated clause, "lane telemetry reads it as the run **outcome**"). It needs
no new bracket: `hooks/ship-gate.sh` already emits the `ship` phase's OUTCOME bracket
(SPEC-129's original live emit), and `gate-ledger.sh` normalizes `Ship` and `ship` to the same
key, so the hook's bracket already pairs correctly with `commands/ship.md`'s GATE row in the
real ledger. Confirmed by `tests/test-outcome-emit-sweep.sh` AC5 (the exemption is asserted
load-bearing, not decorative).

## Command run: `bash tests/test-outcome-emit-sweep.sh`

```
=== AC1: no-orphan sweep -- every 'record ... ran' site has a paired 'outcome ... end' ===
  PASS every 'record ... ran' site in commands/*.md has a paired 'outcome ... end' (0 orphans)

=== AC2: no-orphan sweep -- every 'record ... ran' site has a paired 'outcome ... start' ===
  PASS every 'record ... ran' site in commands/*.md has a paired 'outcome ... start' (0 orphans)

=== AC3: the 22-site SPEC-193 inventory is exactly covered (per-site, exact phase) ===
  [... 42 PASS lines, one start+end pair per of the 21 file:phase rows ...]
  PASS the inventory names exactly 21 file:phase rows (22 sites -- mega.md's advisor P5+P6
       share one row)

=== AC4: NEGATIVE CONTROL -- a fixture site with no paired bracket IS flagged ===
  PASS the sweep flags exactly 1 orphan in the fixture dir (the unbracketed fixture)
  PASS the flagged orphan is specifically fixture-unbracketed.md (fixture-phase)
  PASS the legit bracketed copy (think.md) is NOT flagged

=== AC5: the 'ship' exemption is load-bearing (not decorative) ===
  PASS commands/ship.md has NO outcome bracket of its own (the live emit is
       hooks/ship-gate.sh's, SPEC-129)
  PASS removing the 'ship' exemption alone makes the sweep flag >=1 new orphan (ship.md)
  PASS ...and that orphan is specifically ship.md (Ship)

=== Results ===
Passed: 51 / 51
All outcome-emit-sweep tests passed.
```

Exit: 0.

## Fixture-run proof (goal step 2-3): the ledger slice + `stats mega-durations`

`docs/verification/fixtures/loop-02-outcome-emit/runs/fixture-normal-run.log` was built by
literally EXECUTING `bash lib/gate/gate-ledger.sh` with the exact `outcome start` / `record
ran` / `outcome end` sequence each bracketed command file now instructs, in phase order
(think -> spec -> build -> review -> docs -> ship), one second apart:

```
Command: (see docs/specs/SPEC-193-outcome-emit-sweep.md "## Verification" item 4 for the
full replay script; summarized here)
2026-07-11T20:36:50Z | START | lane=normal classified=normal type=spec-feature ctype=spec-feature repo=fixrepo
2026-07-11T20:36:50Z | OUTCOME | think | start | at=1783802210
2026-07-11T20:36:51Z | GATE | think | ran | BUILD spec-feature well-scoped
2026-07-11T20:36:51Z | OUTCOME | think | end | at=1783802211 caught=false dur_s=1
2026-07-11T20:36:51Z | OUTCOME | spec | start | at=1783802211
2026-07-11T20:36:52Z | GATE | spec | ran | SPEC-193-outcome-emit-sweep approved, tasks=3
2026-07-11T20:36:52Z | OUTCOME | spec | end | at=1783802212 caught=false dur_s=1
2026-07-11T20:36:52Z | OUTCOME | build | start | at=1783802212
2026-07-11T20:36:53Z | GATE | build | ran | tasks=3/3 verified=3 tests=pass
2026-07-11T20:36:53Z | OUTCOME | build | end | at=1783802213 caught=true dur_s=1
2026-07-11T20:36:53Z | OUTCOME | review | start | at=1783802213
2026-07-11T20:36:54Z | GATE | review | ran | SHIP findings=0 rejected=0 actor=fixture
2026-07-11T20:36:54Z | OUTCOME | review | end | at=1783802214 caught=false dur_s=1
2026-07-11T20:36:54Z | OUTCOME | docs | start | at=1783802214
2026-07-11T20:36:55Z | GATE | docs | ran | files=README.md,CLAUDE.md
2026-07-11T20:36:55Z | OUTCOME | docs | end | at=1783802215 caught=false dur_s=1
2026-07-11T20:36:55Z | OUTCOME | ship | start | at=1783802215
2026-07-11T20:36:56Z | GATE | ship | ran | shipping pr=#999
2026-07-11T20:36:56Z | OUTCOME | ship | end | at=1783802216 caught=false dur_s=1
Exit: 0
```

Every phase the (simulated) lane ran has a paired `OUTCOME | <phase> | start` / `OUTCOME |
<phase> | end` bracket, exactly the shape `read_kit_gates` (SPEC-131) pairs by phase name,
FIFO, into `kit_gates.start_ts`/`end_ts`.

`uv run stats mega-durations --json` (`DWARVES_KIT_LOG_DIR` pointed at the fixture root):

```
Command: cd lib/stats && DWARVES_KIT_LOG_DIR=<repo>/docs/verification/fixtures/loop-02-outcome-emit uv run stats mega-durations --json
Exit: 0
Output:
{
  "durations": [
    {
      "rid": "fixture-normal-run",
      "first_start": 1783802210,
      "last_end": 1783802216,
      "n_gates_timed": 6,
      "wall_seconds": 6
    }
  ],
  "n_rids_with_complete_timestamps": 1,
  "n_rows_excluded": 0
}
```

Non-empty row, `n_gates_timed=6` (all 6 phases the fixture lane ran), `wall_seconds=6`
(plausible: 6 phases, 1s apart in the fixture replay), 0 rows excluded. This is the exact
mechanism `stats digest`'s time-to-done reads too (same `kit_gates` table).

## Negative control (goal step 4): a legacy (pre-sweep) ledger renders honest-empty

`docs/verification/fixtures/loop-02-outcome-emit-legacy/runs/fixture-legacy-run.log` is the
SAME 7 GATE rows with every `| OUTCOME |` line stripped (`grep -v OUTCOME`), simulating a run
recorded before this sweep landed:

```
Command: cd lib/stats && DWARVES_KIT_LOG_DIR=<repo>/docs/verification/fixtures/loop-02-outcome-emit-legacy uv run stats mega-durations --json
Exit: 0
Output:
{
  "durations": [],
  "n_rids_with_complete_timestamps": 0,
  "n_rows_excluded": 6
}
```

`"durations": []` -- no fabricated zero row, `n_rids_with_complete_timestamps: 0`, all 6
GATE rows honestly excluded, exit 0 (no crash). Matches the existing, generic
`lib/stats/tests/fixtures/mega-durations-stripped/` NC; this fixture makes the same proof
self-contained to this sub-goal.

## Full suite

All 46 CI-wired test files (`.github/workflows/test.yml`, plus the new
`tests/test-outcome-emit-sweep.sh` entry) pass locally, including the two tests this sweep
depends on staying unbroken:

```
Command: bash tests/test-gate-outcome.sh
Exit: 0 -- 22/22 passed (additive-equivalence property unchanged)

Command: bash tests/test-command-emit-sweep.sh
Exit: 0 -- 19/19 passed (pre-existing 'record ... ran' coverage sweep unaffected)

Command: bash tests/test-outcome-emit-sweep.sh
Exit: 0 -- 51/51 passed (new standing OUTCOME-bracket coverage lint)
```

Full 46-file sweep (every `run:` line in `.github/workflows/test.yml`): 46/46 pass, 0 fail.

## Rollback

Purely additive markdown-instruction + one new test file + one new lib file; no schema, no
existing-file deletion. Revert = `git revert` the commit; every existing reader (`check()`,
`override()`, `descent()`, `_rows()`, `_token_agg()`, the ship-gate) is unaffected either way
(SPEC-129's additive-equivalence property, re-verified above, not re-derived).
