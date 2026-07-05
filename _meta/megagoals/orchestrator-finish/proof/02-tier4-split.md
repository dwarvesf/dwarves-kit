# Proof of done: orchfin-02-tier4-split (ID-093)

## Acceptance criteria

| # | Criterion | Met | Evidence |
|---|---|---|---|
| 1 | TIER-4 close dispatches 3 independent fresh-context verifier sessions (not 1) | yes | Run detail Scenario 1: 3 distinct `dispatching verifier session N/3` lines, one `claude -p` process each |
| 2 | Verdicts are aggregated with a fail-closed rule | yes | `_aggregate_tier4_verdicts` (lib/queue/orchestrate.sh); Scenario 1 aggregate PASS only when all 3 report `TIER4-VERDICT: PASS` |
| 3 | Negative control: one dissenting verifier is NOT silently dropped, aggregate fails closed | yes | Run detail Scenario 2: verifier 2 dissents, aggregate line names it, close exits 1, gate not held |
| 4 | Scope respected: only the `TIER4_CLOSE` dispatch/aggregation changed (no 4th verifier, no per-sub-goal V-model change) | yes | Diff limited to `_build_close_prompt` → `_tier4_objective`/`_build_verifier_prompt`/`_dispatch_tier4_verifiers`/`_aggregate_tier4_verdicts` + `_tier4_close` step 2 + doc comments; still exactly 3 checks (integration-verifier / review-team+security / advisor-both-modes) |
| 5 | Existing TIER-4 close behavior (no-orphan sweep, gate-held, opt-out, whole-word match) unchanged | yes | `tests/test-tier4-close.sh` sections B/C/E/F/G unchanged in intent, all pass |

## Implementation

- `lib/queue/orchestrate.sh`:
  - `_tier4_objective` (new): factors the shared Destination/title extraction out of the old `_build_close_prompt`.
  - `_build_verifier_prompt <dir> <roadmap> <n>` (new, replaces `_build_close_prompt`): composes the n-th (1/2/3) of three independent verifier prompts, each assigned exactly one of the three original checks, ending in a structured `TIER4-VERDICT: PASS|DISSENT: <reason>` contract.
  - `_aggregate_tier4_verdicts <out1> <out2> <out3>` (new): fail-closed aggregation, prints a per-verifier line + the aggregate decision, returns 0 only if all 3 are exactly `TIER4-VERDICT: PASS`.
  - `_dispatch_tier4_verifiers <dir> <roadmap>` (new): dispatches all 3 `claude -p` sessions (never `--stream`), captures each session's stdout to its own temp file, folds a nonzero session exit into a synthetic DISSENT line, always dispatches all 3 (no short-circuit on an early dissent/error), then calls the aggregator.
  - `_tier4_close` step 2 rewritten to call `_dispatch_tier4_verifiers` instead of a single dispatch; step 1 (no-orphan sweep) and step 3 (hold-the-gate messaging) are unchanged in behavior, only re-worded to say "3 independent verifier sessions" instead of "the verifier session."
  - Header comments (SPEC-118 block, `TIER4_CLOSE` var comment, `_tier4_close` section banner, dry-run preview line) updated to describe the 3-dispatch + aggregate shape; tagged `ID-093` alongside the existing `SPEC-118` reference.
- `tests/test-tier4-close.sh`: mock (`mk_mock`) updated to recognize the per-verifier `TIER-4 MEGA-CLOSE VERIFIER n/3` banner, touch a per-index sentinel (`$CLOSE_SENTINEL.$n`), and emit a `TIER4-VERDICT: PASS` (or forced `DISSENT` via `$MOCK_DISSENT`) line. Existing sections A/D/F/G updated to assert on the 3 per-index sentinels instead of 1; new assertions for "exactly 3 dispatches" and "aggregate PASS" in section A. New section H: the dissent negative control (`MOCK_DISSENT=2`), asserting all 3 still dispatch, the close halts nonzero, the aggregator names the dissent, and the gate is not held.

## Confirmation run-table

| Run | Command | Exit | Result |
|---|---|---|---|
| Full test suite | `bash tests/test-tier4-close.sh` | 0 | `ALL PASS` (25/25, incl. new three-verifier-split + dissent-NC assertions) |
| Scenario 1 (clean) | `TIER4_CORPUS=<clean-corpus> CLAUDE_CMD=<mock> bash lib/queue/orchestrate.sh run <megagoal-dir>` | 0 | 3 verifier sessions dispatched, all `TIER4-VERDICT: PASS`, aggregate `PASS: all 3 independent verifiers agree.`, gate HELD, `NOT auto-merged` |
| Scenario 2 (negative control: verifier 2 dissents) | same, with `MOCK_DISSENT=2` | 1 | all 3 verifiers still dispatched (2/2 named a dissent), aggregate `DISSENT: at least one of the 3 verifiers did not PASS -- failing closed.`, close reports `BLOCKING: the 3-verifier aggregate DISSENTED`, gate NOT held |
| shellcheck | `shellcheck lib/queue/orchestrate.sh` | 0 | no warnings on the new functions or the touched file |
| syntax | `bash -n lib/queue/orchestrate.sh` | 0 | parses clean |

## Run detail

### Full test suite (`tests/test-tier4-close.sh`)

```
$ bash tests/test-tier4-close.sh
PASS clean close: run exits 0 (held clean)
PASS clean close: both auto boxes flipped (reached the terminal)
PASS verifiers-before-gate: verifier close sessions were DISPATCHED (not done-and-return)
PASS three-verifier split: exactly 3 independent verifier sessions dispatched
PASS aggregate: all-PASS aggregates to PASS
PASS gate-held: the close HELD for the human gate
PASS gate-held: message states NOT auto-merged (gated-final)
PASS gate-held: NO merge hook invoked by the close (recorder empty)
PASS replaces-done-and-return: bare 'done' is gone; the close ran instead
PASS no-orphan unit: clean corpus -> rc 0, no orphan printed
PASS seeded-orphan NC (unit): the orphan agent is CAUGHT (rc 1, named, BLOCKING)
PASS seeded-orphan NC (unit): the dispatched good-agent is NOT flagged
PASS seeded-orphan NC (e2e): the close HALTS nonzero on an orphan (not held clean)
PASS seeded-orphan NC (e2e): the orphan is named as BLOCKING
PASS seeded-orphan NC (e2e): fail-fast -- no verifier session dispatched after a blocking orphan
PASS seeded-orphan NC (e2e): the gate is NOT held on a blocking orphan
PASS whole-word match: 'advisor' is NOT satisfied by the word 'advisory' (grep -w works)
PASS opt-out: TIER4_CLOSE=0 restores the bare done-and-return
PASS opt-out: TIER4_CLOSE=0 dispatches NO close session
PASS no-corpus unit: _no_orphan_check returns 2 (skip signal) when there is no agents/ to sweep
PASS no-corpus e2e: rc 2 -> WARN+skip (not a halt, not mis-reported clean); all 3 sessions ran, gate held
PASS dissent NC: all 3 verifiers dispatched despite one dissenting
PASS dissent NC: the close HALTS nonzero on a single dissent (not held clean)
PASS dissent NC: the aggregator names the DISSENT (not silently dropped)
PASS dissent NC: the gate is NOT held on a dissenting verifier
----
ALL PASS
```

### Scenario 1: clean close, direct `orchestrate.sh run` (all 3 verifiers PASS)

```
[orchestrate] [close] all sub-goals checked; running the TIER-4 mega-close over the assembled wave ...
[orchestrate] [close] no-orphan sweep clean over <corpus> (every agent has a live dispatch).
[orchestrate] [close] dispatching 3 independent verifier sessions (<mock> -p x3) ...
[orchestrate] [close] dispatching verifier session 1/3 (<mock> -p) ...
TIER4-VERDICT: PASS
[orchestrate] [close] dispatching verifier session 2/3 (<mock> -p) ...
TIER4-VERDICT: PASS
[orchestrate] [close] dispatching verifier session 3/3 (<mock> -p) ...
TIER4-VERDICT: PASS
[aggregate] verifier 1: TIER4-VERDICT: PASS
[aggregate] verifier 2: TIER4-VERDICT: PASS
[aggregate] verifier 3: TIER4-VERDICT: PASS
[aggregate] PASS: all 3 independent verifiers agree.
[orchestrate] [close] TIER-4 mega-close complete: ... all PASS over the assembled wave. HELD for the
final human gate -- NOT auto-merged (gated-final). Review the held PR, then merge.
EXIT=0
```

### Scenario 2 (negative control): verifier 2 forced to dissent, direct `orchestrate.sh run`

```
[orchestrate] [close] dispatching 3 independent verifier sessions (<mock> -p x3) ...
[orchestrate] [close] dispatching verifier session 1/3 (<mock> -p) ...
TIER4-VERDICT: PASS
[orchestrate] [close] dispatching verifier session 2/3 (<mock> -p) ...
TIER4-VERDICT: DISSENT: forced test dissent from verifier 2
[orchestrate] [close] dispatching verifier session 3/3 (<mock> -p) ...
TIER4-VERDICT: PASS
[aggregate] verifier 1: TIER4-VERDICT: PASS
[aggregate] verifier 2: TIER4-VERDICT: DISSENT: forced test dissent from verifier 2
[aggregate] verifier 3: TIER4-VERDICT: PASS
[aggregate] DISSENT: at least one of the 3 verifiers did not PASS -- failing closed.
[orchestrate] [close] BLOCKING: the 3-verifier aggregate DISSENTED (at least one of the 3 independent
verifiers did not pass clean); halting for human review (not held clean).
EXIT=1
```

The negative control proves the point of the split: verifier 1 and verifier 3 both PASS clean, only
verifier 2 dissents, and the run still fails closed instead of being outvoted 2-to-1. That is the
literal fix for the failure mode named in the sub-goal ("a single verifier missing a cross-sub-goal
seam no longer green-lights the mega; a dissent from any of the three surfaces").

## Reproduce

```bash
cd dwarves-kit   # or this worktree
bash tests/test-tier4-close.sh
```

For the two standalone scenarios above, see `tests/test-tier4-close.sh` sections A (clean) and H
(dissent negative control) -- they build the same fixtures (`mk_megagoal`, `mk_corpus_clean`,
`mk_mock`) and assert the same properties captured in the run detail.
