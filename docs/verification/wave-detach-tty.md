# Verification -- wave-detach-tty

A wave sub-goal no longer runs on the operator's controlling terminal. The wave subshell runs claude through `lib/queue/detach-run`, which gives it its own session and forwards TERM/INT/HUP, so a zshrc `stty` cannot stop it with SIGTTOU and `_wave_abort`'s group kill still reaches the whole tree. The serial path is untouched.

## Green run

The new suite builds a real wave (real git worktrees, mock claude) under a real pty from python3, so the shell has a controlling terminal, the condition the bug needs. The mock runs `stty -ixon </dev/tty` like the user's zshrc.

```
Command: bash tests/test-wave-detach-tty.sh
Exit: 0
Output:
  PASS detach-run passes the child's exit status through (7)
  PASS detach-run does not leak KIT_DETACH_CMD to the command
  PASS group kill of the detach-run job leaves no orphan (child, grandchild gone; rc 143)
  PASS fixed: wave session finishes under a real pty, runs with no controlling terminal (tty='??'), box flipped
  PASS NEGATIVE CONTROL (pre-fix spawn): the session sits on the terminal (tty='ttys003') and its stty stops it (state T): T 41047 bash
  PASS wave abort (SIGTERM to the orchestrator) leaves no orphaned session or grandchild
  ---
  all passed
Verdict: PASS
```

Regression run over every suite the diff touches:

```
Command: bash tests/run-all.sh --changed origin/master
Exit: 0
Output:
  run-all: all 37 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

Two controls. The suite's own: `NC_SKIP_WAVE_DETACH=1` restores the old spawn, the mock sits on the pty (`ttys003`) and its stty stops it (state `T`) until the deadline kills it; the case asserts exactly that. And a source mutation, run after the code was committed (`a1315e13`), swapping `detach_cmd` back to `$CLAUDE_CMD` in `lib/queue/orchestrate.sh`, then restored with `git checkout`:

```
Command: bash tests/test-wave-detach-tty.sh   (orchestrate.sh mutated: detach_cmd="$CLAUDE_CMD")
Exit: 1 (RED expected)
Output:
  PASS detach-run passes the child's exit status through (7)
  PASS detach-run does not leak KIT_DETACH_CMD to the command
  PASS group kill of the detach-run job leaves no orphan (child, grandchild gone; rc 143)
  FAIL fixed: rc='1' deadline=hit tty='ttys003' roadmap: - [ ] SG-01 alpha , auto , PR #__
  PASS NEGATIVE CONTROL (pre-fix spawn): the session sits on the terminal (tty='ttys003') and its stty stops it (state T): T 60770 bash
  PASS wave abort (SIGTERM to the orchestrator) leaves no orphaned session or grandchild
  ---
  1 failed
Verdict: RED under mutation, GREEN restored (run above)
```

The group-kill claim is pinned twice: `set -m` + `kill -- -$!` on a bare detach-run job, and a real `_wave_run` aborted with SIGTERM; both assert the child and its grandchild are gone.
