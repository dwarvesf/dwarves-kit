# Verification -- wave-rolling

`lib/queue/orchestrate.sh` gains rolling wave admission behind `WAVE_ROLLING` (env, `[mega].wave_rolling`, default off). Off, a wave stays a barrier. On, a member that lands is converged at once and its slot is refilled from the recomputed ready set, admitting only sub-goals dispatch-gate proves disjoint from every member still running, up to `WAVE_CAP`.

## What it did before

`cmd_run` admitted up to `WAVE_CAP` ready, disjoint sub-goals; `_wave_run` spawned them and blocked until the whole wave drained; `cmd_run` then converged the landed set and only then recomputed. On a live 17-sub-goal run (1 to 3 h per sub-goal), a finished slot sat idle until the slowest sibling ended, often 30 to 90 minutes per cycle.

## What it does now

| Event (switch on) | Behavior |
|---|---|
| A member lands (rc 0, box flipped in the shared ROADMAP) | Converged at once (`_wave_converge <id> --peers ...`), then `_wave_gate <running ids>` picks newly ready candidates disjoint from every running member; they spawn through `_wave_spawn`, the same path as the initial wave. |
| Same-file guard | The landed member's branch is compared with every landed member whose run overlapped its own (spawn/reap ticks). Peers are never compared with each other: a parent and its dependent ran one after the other and may share a file. |
| Merge order | Completion order, one at a time under the flip lock. A dependent is admitted only after its parent's merge step. |
| Dependency hold | A box flip is not completion proof (a session flips before it exits, and may still exit nonzero). A candidate whose `depends` names a wave member that has not converged is deferred. A dep outside the wave was complete before it started. |
| Abort | `_WAVE_ABORTED` blocks convergence and admission, fails the wave even when every member looked fine (an abort during the last converge), and `_wave_spawn` refuses to start a session after it (or kills one whose pid was recorded after the handler ran). |
| Member exits nonzero or lands unflipped, a spawn is refused, convergence fails, abort, or a `gate!` is ready | Admission stops for the rest of the wave; running members drain (abort kills them); a member landing after a failure is not converged; `cmd_run` halts as today. |
| Last running member lands | No admission; control returns to `cmd_run`, whose next cycle recomputes from scratch (wave if 2+ admit, else the serial body with its no-claim retry). |
| `WAVE_CAP=1` | Unreachable, as before: `cmd_run` never enters the wave block. |
| Switch off | The barrier path, with one safety change for both modes: a reaped pid is blanked in `_WAVE_PIDS`, so an abort never signals a recycled pid's group. |

Kept: no self-claim (the driver never flips a box), the flip lock, per-member worktrees, detach-run for wave sessions, the abort group kill (every admitted pid lands in `_WAVE_PIDS`; `_WAVE_ABORTED` blocks convergence and admission once the handler fires), the no-claim retry stays serial-only.

## Green run

```
Command: bash tests/test-wave-rolling.sh
Exit: 0
Output:
  PASS (a) the slot SG-01 freed admitted its dependent SG-03 before the slow SG-02 ended (all 3 boxes, rc 0)
  PASS (a) the driver says SG-03 was admitted while SG-02 was still running
  PASS (a) the late-admitted member got the wave prompt (shared-ROADMAP flip contract), same spawn path
  PASS (a) SG-03 ran in its own worktree
  PASS (a-NC) NEGATIVE CONTROL: switch off, the barrier holds; SG-03 starts only after SG-02 ends (the (a) assertion fails here)
  PASS (b) SG-03 overlaps the running SG-02 (lib/b/**): not admitted into the free slot, ran after SG-02 ended
  PASS (c) SG-01 exited unflipped: no admission into its slot (SG-03 never ran), no wave retry, SG-02 drained, run halted nonzero
  PASS (d) TERM mid rolling wave: SG-02 and the late-admitted SG-03 (sessions + grandchildren) are gone, nothing new admitted, rc 1
  PASS (e) WAVE_CAP=1: stdout, prompts, events and session order identical with the switch on and off; serial, no worktrees
  PASS (f) WAVE_ROLLING defaults off, [mega].wave_rolling = true turns it on, the env var wins
  PASS (g1) SG-01 merged before its dependent took the slot; each PR merged exactly once; a dependent editing its parent's file is not flagged
  PASS (g2) two members that ran together both edited same.txt: SG-02 is refused (not merged); SG-03 landing after it is not converged and its slot is not refilled; the run halts
  PASS (h1) SG-01 flipped but was still running: its dependent SG-03 started only after SG-01 exited and merged
  PASS (h2) SG-02 flipped then exited 1: SG-03 never ran on the failed, unconverged parent; the run halted
  PASS (i1) TERM during the last member's converge: the run halts (rc 1), the next cycle never starts SG-03
  PASS (i2) TERM mid refill spawn: SG-03 was never started, SG-02 killed with its grandchild, the driver exited rc 1
  PASS (j1) refill spawn refused (bad Model:): nothing else admitted, SG-02 drained, the run halted
  PASS (j2) gate! became ready mid-wave: SG-04 not admitted into the free slot, SG-02 drained, the loop stopped for the human
  PASS (j3) WAVE_CAP=3: one landing refilled two slots in one pass, SG-05 waited for a free slot, peak 3 sessions
  ---
  all passed
Verdict: PASS
```

The suite drives the real `orchestrate.sh run` against a throwaway git repo (real worktrees, detach-run, flip lock) with a mock claude whose timeline file records `start`/`end`/`merge` in append order. Timing is made deterministic by having the slow member wait for an event (another member starting or ending) instead of a fixed sleep.

Regression run over every suite the diff touches:

```
Command: bash tests/run-all.sh --changed origin/master --time
Exit: 0
Output:
  test-multiplexer                               ok (8s)
  test-orchestrate-gate-dispatch                 ok (21s)
  test-orchestrate-hardening                     ok (11s)
  test-orchestrate-orca                          ok (114s)
  test-orchestrate                               ok (69s)
  test-wave-converge                             ok (1s)
  test-wave-detach-tty                           ok (30s)
  test-wave-rid-check                            ok (36s)
  test-wave-rolling                              ok (82s)
  test-wave-token-capture                        ok (32s)
  run-all: 58 suites run; one red: test-meta-docs-registry (FEATURES.md stale after the new test text)
  -> regenerated docs/reference/FEATURES.md; bash tests/run-all.sh --only test-meta-docs-registry: all 1 suites passed
Verdict: PASS
```

An earlier `--changed` run was red on (g1) under parallel load: when the dependent landed before the slow sibling, the sibling's convergence compared its two peers with each other and flagged the parent/dependent shared file, a false halt. Fixed (peers compared with the landed member only) and (g1) now forces that ordering.

## Review fixes

Two independent reviews of the first push found three bugs, each reproduced against the real driver before the fix (scratch repro scripts R1 to R3 and an early-flip repro), each now a suite case:

| Finding | Repro on the first push | Fix | Case |
|---|---|---|---|
| Dependent admitted on a flipped-but-running parent | R1: SG-03 started before SG-01's merge; early-flip: SG-03 ran on a parent that then exited 1 | dependency hold (`_WAVE_GATE_HOLD`) | h1, h2 |
| Abort during the last member's converge swallowed | R2: rc 0 and SG-03 ran in the next cycle (switch off: rc 143) | `[ "$_WAVE_ABORTED" = 1 ] && wave_failed=1` before both returns | i1 |
| Abort during a refill spawn left a new session running | R3: driver alive 8s after TERM, SG-03 alive | `_wave_spawn` refuses after an abort (before `_pane_spawn` and `set -m`), kills a late-recorded pid; initial loop breaks | i2 |

Also added: a refused refill spawn (j1), a `gate!` becoming ready mid-wave (j2), `WAVE_CAP=3` refilling two slots in one pass with a peak of 3 sessions (j3). Nits: `${WAVE_ROLLING:-0}` reads; the design block notes the peer guard goes vacuous once a peer's merge is in the local base.

Per-fix negative controls (`negctl.sh --parallel 3` on commit `dfba521f`; failing cases named by re-running each mutation):

```
Command: bash lib/gate/negctl.sh --parallel 3 "$PWD" "bash tests/test-wave-rolling.sh" <mutation>...
Exit: 0 (every control RED under its mutation, GREEN after restore)
Output:
  Mutation: sed -i '' 's/_WAVE_GATE_HOLD="$hold" _wave_gate/_wave_gate/' lib/queue/orchestrate.sh
  Exit: 1 (under mutation, RED expected)
    FAIL (h1) rc=0 boxes=3 timeline: start SG-01 flipped SG-01 start SG-02 end SG-02 merge PR 12 start SG-03 end SG-01
    FAIL (h2) rc=1 timeline: start SG-01 end SG-01 start SG-02 flipped SG-02 start SG-03 end SG-02 end SG-03
    2 failed
  Restore: git checkout HEAD -- lib/queue/orchestrate.sh
  Exit: 0 (green after restore)
  Verdict: PASS

  Mutation: sed -i '' '/^  \[ "$_WAVE_ABORTED" = 1 \] \&\& wave_failed=1$/d' lib/queue/orchestrate.sh
  Exit: 1 (under mutation, RED expected)
    FAIL (i1) rc=0 timeline: start SG-01 end SG-01 start SG-02 merge PR 11 end SG-02 merge PR 12 start SG-03 end SG-03
    1 failed
  Restore: git checkout HEAD -- lib/queue/orchestrate.sh
  Exit: 0 (green after restore)
  Verdict: PASS

  Mutation: delete both pre-spawn abort guards in _wave_spawn and the post-record kill (if false)
  Exit: 1 (under mutation, RED expected)
    FAIL (i2) the driver is still alive 20s after the abort (waiting on a session spawned after it?) timeline: start SG-01 end SG-01 start SG-02 start SG-03
    1 failed
  Restore: git checkout HEAD -- lib/queue/orchestrate.sh
  Exit: 0 (green after restore)
  Verdict: PASS
Verdict: PASS
```

## Negative control

First push, three mutations, each in a throwaway worktree copy, via `lib/gate/negctl.sh --parallel 3` on commit `a4346beb`:

```
Command: bash lib/gate/negctl.sh --parallel 3 "$PWD" "bash tests/test-wave-rolling.sh" <mutation>...
Exit: 0 (every control RED under its mutation, GREEN after restore)
Output:
  Mutation: git show origin/master:lib/queue/orchestrate.sh >| lib/queue/orchestrate.sh
  Exit: 1 (under mutation, RED expected)
    8 failed
  Restore: git checkout HEAD -- lib/queue/orchestrate.sh
  Exit: 0 (green after restore)
  Verdict: PASS

  Mutation: sed -i '' 's/\[ "$WAVE_ROLLING" = 1 \] || continue/continue/' lib/queue/orchestrate.sh
  Exit: 1 (under mutation, RED expected)
    [orchestrate] [wave] SG-03 complete (box checked).
    [orchestrate] all sub-goals checked; done.
    7 failed
  Restore: git checkout HEAD -- lib/queue/orchestrate.sh
  Exit: 0 (green after restore)
  Verdict: PASS

  Mutation: sed -i '' 's/&& peers+=("${_WAVE_IDS\[$j\]}")/\&\& :/' lib/queue/orchestrate.sh
  Exit: 1 (under mutation, RED expected)
    [orchestrate] [wave] [rolling] SG-04 admitted into a freed slot (still running: SG-03)
    [orchestrate] [converge] SG-04 merged (PR #24).
    1 failed
  Restore: git checkout HEAD -- lib/queue/orchestrate.sh
  Exit: 0 (green after restore)
  Verdict: PASS
Verdict: PASS
```

The in-suite control (a-NC) runs the (a) fixture with the switch off and asserts the opposite order: SG-03 starts only after the slow SG-02 ends.

## Not proven

- Real merges. Every case uses a mock `WAVE_MERGE_CMD` and a mock `gh`; per-member convergence against `mega-merge.sh merge --execute` and a real PR is not exercised. This is why the default stays off.
- The multiplexer path (`MULTIPLEXER=1`) under rolling admission: `_wave_spawn` keeps the mux branch unchanged, but no case runs rolling admission with tmux panes.
- A live mega-goal run. The 30 to 90 minute idle figure is from the operator's run, not re-measured here.

## Rollback

Leave `WAVE_ROLLING` unset (the default) or set `[mega].wave_rolling = false`. Revert the commit to drop the code; the driver writes no new state.
