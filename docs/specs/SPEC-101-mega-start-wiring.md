# SPEC-101: emit gate-ledger START in the automated mega dispatch

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

`commands/assign.md` (the hand-run intake) records each run's routing facts with
`lib/gate-ledger.sh start <rid> <lane> <classified> <type> <ctype>`, so hand-run
work is measurable by `lib/lane-telemetry.sh report`. The **automated** mega-goal
dispatch does NOT: `lib/orchestrate.sh cmd_run` (the non-LLM driver that
`commands/mega.md` Step 5 hands off to via `lib/orchestrate.sh run <dir>`) spawns one
`claude -p` session per sub-goal and emits only its own `_emit_event ... executing`
event, never a `gate-ledger start`. The spawned session runs the goal loop, not
`assign.md`, so no START is emitted anywhere.

Result: every mega-dispatched run is untracked (`?` lane/type) in lane telemetry.
This is the root cause of the SPEC-073 effectiveness eval filing lane/type/skip/escape
rates NULL (~60-90% of runs had no START). ID-085, `#kit-telem-followup`.

## Root cause (spec delta)

The sub-goal brief names `commands/mega.md` as the fix site. `commands/mega.md` is
PROSE; the executable automated dispatch it delegates to is `lib/orchestrate.sh
cmd_run`. The START must be emitted by the driver, because:

- The spawned `claude -p` session does not run `assign.md`'s "record routing facts"
  step, so it emits no START itself.
- The START is deterministic and testable in the driver (the driver has the goal
  file + ROADMAP title in hand); in prose it would be an un-pinnable instruction.

So the fix lands in `lib/orchestrate.sh`; `commands/mega.md` gets a one-line pointer
noting the driver now emits the START.

## rid at dispatch time (the key mechanism)

The canonical rid is the work branch with its `type/` prefix stripped, `runid`-normalized
(`lib/gate-ledger.sh rid`). At dispatch the branch does not exist yet (the session creates
it). But every goal file declares its branch in a `**Branch:** <type>/<slug>` header, and
`gate-ledger.sh start` does not require the branch to exist (it writes to
`RUNS_DIR/<runid(rid)>.log`, keyed by the rid string). So the driver derives the rid from
the goal file's `**Branch:**` header (`${branch#*/}`), emits the START, and when the session
later creates that branch and calls `gate-ledger.sh rid`, it resolves to the SAME
`runid(slug)` and its `record` calls append to the same ledger file. `runid` is idempotent,
so the raw slug and the normalized form converge on one filename.

## Solution

Add `_emit_start <dir> <id>` to `lib/orchestrate.sh`, called once per sub-goal inside
`cmd_run`'s run loop (after `_emit_event ... executing`, before the session spawns). It:

1. Resolves the goal file (`_goalfile`); if none, WARN + return 0 (advisory, non-fatal,
   matching the existing `[guardrail] WARN` style; no goal file already warns loudly).
2. Parses `**Branch:** <type>/<slug>` from the goal file; if absent, WARN + return 0 (a
   coarse rid that does not match the session's real branch would only orphan the START).
3. Classifies the lane (`lane-classify.sh classify`) and type (`task-type-classify.sh
   classify`) from the sub-goal title (`_sg_title`). Because the automated path has no human
   override, `chosen == classified` for both axes (an honest record: the automated dispatch
   took the classifier's suggestion verbatim; it never reads as a misroute).
4. Emits `gate-ledger.sh start "$slug" "$lane" "$lane" "$type" "$type"` (repo auto-detected
   by gate-ledger). The slug is normalized to the ledger filename by `ledger_file`.

Excluded from `--dry-run` for free: `cmd_run`'s dry-run branch returns before the run loop.

Idempotence / no double-START: the spawned session does not emit its own START today, so the
driver's START is the only one. A future session that needs to correct it uses the sanctioned
`start --amend` (SPEC-077), not a second plain START.

## Verification

```bash
cd dwarves-kit
grep -n 'gate-ledger.sh start\|_emit_start' lib/orchestrate.sh   # AFTER: present
bash tests/test-orchestrate.sh                                    # START pins + negative control green
bash tests/test-meta.sh                                           # doc-impact + integrity green
```

Pinned in `tests/test-orchestrate.sh`:
- **START emitted**: a mock-claude `run` over a fixture whose goal file carries `**Branch:**`
  writes a `START` line (with `lane=` and `type=`, not `?`) to the runs ledger, keyed to the
  rid derived from that branch.
- **negative control (no branch)**: a fixture goal file with NO `**Branch:**` emits NO START
  (the pre-fix behavior a run is left with), proving the START is what makes it tracked.
- **dry-run stays side-effect-free**: `run --dry-run` emits no START.

## After state

- `lib/orchestrate.sh` emits a `gate-ledger start` per dispatched sub-goal; mega-dispatched
  runs carry a START line and count under their real lane in `lane-telemetry.sh report`, not `?`.
- `commands/mega.md` notes the driver emits the START.
- `README.md` orchestrate.sh entry notes the START emission.
- `docs/verification/mega-start-wiring.md` carries the proof run-table + negative control.

## Open questions

None.
