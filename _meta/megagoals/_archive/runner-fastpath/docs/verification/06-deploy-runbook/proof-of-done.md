# Proof of done: Air deploy runbook (runner-fastpath sub-goal 06)

Sub-goal: `_meta/megagoals/runner-fastpath/goals/06-deploy-runbook.md` · Depends on: 03K
MERGED (`dwarves-kit` PR #178, squash `358373c`) · Runbook:
`_meta/megagoals/runner-fastpath/docs/RUNBOOK-air-queue-deploy.md`

**Rollback:** this sub-goal ships no code, only a runbook + this proof. Nothing to roll
back beyond `git revert` of the branch's commits , no daemon installed, no schema, no
service, no state that outlives the smoke run below (the fixture repo/pointer live under
`mktemp`, never committed).

## Acceptance criteria

| # | Criterion | Met by | Status |
|---|---|---|---|
| A1 | Runbook covers prerequisites | `RUNBOOK-air-queue-deploy.md` "Prerequisites" | PASS |
| A2 | Runbook covers start/attach/read/stop | same doc, respective sections | PASS |
| A3 | Runbook covers the three planes (config/secrets/runtime state) | same doc, "The three planes" table | PASS |
| A4 | Runbook names the Phase-1 `caffeinate`+`tmux` one-liner, corrected against the ACTUAL kit entry point/flags (not the goal file's placeholder) | same doc, "Corrected kit invocation" + "The Phase-1 one-liner" | PASS |
| A5 | `--dry-run` documented as the mandatory pre-night step | same doc, "Mandatory pre-night step" | PASS |
| A6 | The two later options (launchd Phase 2, Mini migration) are named with a trigger condition, NOT built | same doc, "Later options" | PASS |
| A7 | A LIVE smoke actually ran on this machine (the Air), via the real queue launcher, real tmux, real Claude Code session | this proof, "Live smoke" below | PASS |
| A8 | The smoke never touched a real repo checkout (ops-toolkit or dwarves-kit) | verified below (`git status --porcelain` on both, empty) | PASS |
| A9 | PR opened and HELD, not merged | see sub-goal contract; PR left open for operator review | PASS (by the worker's own commitment, not auto-verifiable from this file) |

## Implementation

No source code. One runbook (`RUNBOOK-air-queue-deploy.md`) + this proof. The runbook
corrects two things the sub-goal's placeholder got wrong, found by reading
`dwarves-kit/lib/{orchestrate,queue,board}.sh` directly (not guessed):

1. There is no `bin/orchestrate.sh`; the entry point is `lib/orchestrate.sh`
   (`~/.claude/dwarves-kit/lib/orchestrate.sh` via the pre-existing symlink).
2. `--from-boards` needs `QUEUE_BOARD_CMD="bash $HOME/.claude/dwarves-kit/lib/board.sh"`
   (no `board` binary on PATH) plus `REPO_ROOT=$HOME/workspace/<owner>/ops-toolkit` (not a
   fabricated `CONSUMER_ROOT`) for `board.sh queue` to find the right `boards.txt`.

Plus one live-verified deployment gotcha not in the sub-goal contract at all: `caffeinate`
must wrap the long-running command INSIDE the tmux pane, not the `tmux new-session`
CLIENT invocation (the client returns almost instantly once the detached session exists,
which would release caffeinate's sleep-assertions within about a second). See "Run
detail" below for the experiment that proved this.

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| Kit invocation verified against source | read `lib/orchestrate.sh` lines 1768-1780, `lib/board.sh` `cmd_queue`/`_resolve_repo_root` | confirms `queue) exec queue.sh run "$@"`, `REPO_ROOT` env precedence |
| `bin/orchestrate.sh` does not exist (goal placeholder wrong) | `ls dwarves-kit/bin` | `bin/` directory does not exist |
| `board` binary not on PATH (goal placeholder assumption wrong) | `command -v board` | not found |
| `~/.claude/dwarves-kit` resolves via symlink, zero sync step | `ls -la ~/.claude/dwarves-kit` | `lib -> .../dwarves-kit/lib` (symlink) |
| tmux + caffeinate present on this machine | `which tmux caffeinate; tmux -V` | `/opt/homebrew/bin/tmux` (3.7a), `/usr/bin/caffeinate` |
| caffeinate-wraps-tmux-client is WRONG (experiment) | `tmux new-session -d -s caftest "caffeinate -dims sleep 8; ..."` | caffeinate process lived exactly as long as the pane's `sleep 8`, confirming caffeinate belongs INSIDE the pane, not wrapping the tmux client |
| tmux pane shell is fish, not bash (found the hard way) | first smoke attempt using bare `2>&1` in the pane command | pane died instantly, no log written; `dscl . -read "$HOME" UserShell` = `/opt/homebrew/bin/fish`; fixed by wrapping in `bash -lc` |
| `--dry-run` sanity check against the fixture | `orchestrate.sh queue <fixture.tsv> --dry-run` | `[dry-run] sg06-air-smoke: WOULD LAUNCH (...)` |
| LIVE smoke (real tmux + real claude, via caffeinate+tmux exactly as the runbook prescribes) | see below | journal `done`, fixture repo untouched |
| ops-toolkit worktree untouched by the smoke | `git status --porcelain` (this worktree) | empty |
| dwarves-kit repo untouched by the smoke | `git status --porcelain` (`~/workspace/<owner>/dwarves-kit`) | empty |
| Fixture repo untouched (no writes/commits from the launched session) | `git -C <fixture>/repo status --porcelain` / `log --oneline` | only untracked `.claude/` (the launched session's own local settings, harmless); still 1 commit (`chore: fixture init`) |

## Run detail

### Experiment: caffeinate must be INSIDE the tmux pane

```
$ tmux new-session -d -s caftest "caffeinate -dims sleep 8; echo DONE >> $SCRATCH/caftest.log"
$ ps aux | grep caffeinate
tieubao  44469  caffeinate -dims sleep 8      # lives exactly as long as the pane command
$ tmux ls
caftest: 1 windows (created ...)
... (wait 9s) ...
$ cat $SCRATCH/caftest.log
DONE
$ tmux ls
no server running                             # pane command finished, session (only window) closed
```

This confirms the assertion lasts exactly as long as the wrapped command's lifetime , so
`caffeinate` must wrap the LONG process (`orchestrate.sh queue ...`), not the short-lived
`tmux new-session` client call. A prior naive attempt to wrap the OUTER `tmux new-session
-d` call in `caffeinate` would have released the assertion within about a second, since
`tmux new-session -d` returns almost immediately once the detached session exists.

### Fixture setup (throwaway, under `mktemp -d`, never a real repo)

```bash
FX=$(mktemp -d "$SCRATCH/runner-smoke.XXXXXX")
git -C "$FX/repo" init -q -b main
git -C "$FX/repo" config user.email t@t.dev
git -C "$FX/repo" config user.name smoke-tester
echo "throwaway fixture, never a real repo" > "$FX/repo/f.txt"
git -C "$FX/repo" add f.txt && git -C "$FX/repo" commit -qm "chore: fixture init"
# HEAD = 2c30457
```

Pointer file (`$FX/pointer.txt`), the exact content typed into the launched session:

```
Report the current git HEAD short SHA in this repo (git rev-parse --short HEAD), write nothing to
any file, make no commits, and end your final message with the exact line
RUNNER_DONE
```

Queue row (`$FX/queue.tsv`, hand-authored , allow-list-exempt by design, per `lib/queue.sh`):

```
sg06-air-smoke<TAB><FX>/repo<TAB><FX>/pointer.txt
```

### `--dry-run` pre-night sanity check

```
$ bash ~/.claude/dwarves-kit/lib/orchestrate.sh queue "$FX/queue.tsv" --dry-run
[dry-run] sg06-air-smoke: WOULD LAUNCH (repo=<FX>/repo pointer=<FX>/pointer.txt)
```

### LIVE smoke: exact caffeinate+tmux invocation used (matches the runbook's Phase-1 shape)

```bash
SESSION="sg06-smoke-v2-1783199865"          # the outer wrapper session (this run's name)
JOURNAL="$FX/queue-journal.tsv"
LOG="$FX/outer.log"

tmux new-session -d -s "$SESSION" bash -lc \
  "caffeinate -dims bash '$HOME/.claude/dwarves-kit/lib/orchestrate.sh' queue '$FX/queue.tsv' --journal '$JOURNAL' > '$LOG' 2>&1; echo QUEUE_EXIT=\$? >> '$LOG'"
```

(This smoke used a hand-authored tsv rather than `--from-boards`, since the fixture is a
throwaway repo with no `boards.txt` entry , the launcher mechanism exercised end-to-end
[tmux window open -> `/goal` send-keys -> marker poll -> journal -> window kill] is
IDENTICAL regardless of row source; `--from-boards` only changes how rows are fed in.)

Live process tree confirmed the full real chain (`ps aux`, abbreviated):

```
caffeinate -dims bash .../orchestrate.sh queue <fixture.tsv> --journal <fixture-journal>
  -> bash .../queue.sh run <fixture.tsv> --journal <fixture-journal>   # orchestrate.sh's exec alias
```

Launched pane (`tmux capture-pane -p -t dk-queue:sg06-air-smoke`), captured mid-run,
showing the REAL Claude Code `/goal` loop:

```
❯ /goal Report the current git HEAD short SHA in this repo (git rev-parse
--short HEAD), write nothing to any file, make no commits, and end your final
message with the exact line RUNNER_DONE
  ⎿  Goal set: Report the current git HEAD short SHA in this repo (git rev-parse
     --short HEAD), write nothing to any file, make no commits, and end your
     final message with the exact line RUNNER_DONE

⏺ Bash(git rev-parse --short HEAD)
  ⎿  2c30457

· Meandering… (4s · thinking with high effort)
```

### Outcome

```
# $FX/outer.log
[queue] sg06-air-smoke: launching /goal in a tmux window (repo=<FX>/repo).
[queue] sg06-air-smoke: done.
QUEUE_EXIT=0

# $FX/queue-journal.tsv
2026-07-04T21:18:10Z	sg06-air-smoke	done	
```

Post-run cleanup checks:

```
$ git -C <FX>/repo status --porcelain
?? .claude/                          # the launched session's own local settings, harmless
$ git -C <FX>/repo log --oneline
2c30457 chore: fixture init          # unchanged, no new commit

$ cd <ops-toolkit worktree> && git status --porcelain
(empty)

$ cd ~/workspace/<owner>/dwarves-kit && git status --porcelain
(empty)

$ tmux ls    # after the outer session's single command finished
dk-queue: 1 windows                  # leftover kit-owned session (the "_init" placeholder window);
                                      # killed as part of this smoke's own cleanup, harmless either way
```

Environment for the record: macOS 26.5.1 (25F80), tmux 3.7a, Claude Code 2.1.201,
`dwarves-kit` at `358373c` (PR #178, the 03K merge commit).

## Reproduce

```bash
SCRATCH=$(mktemp -d)
git -C "$SCRATCH" init -q -b main 2>/dev/null || true   # not required; FX below is the real fixture
FX=$(mktemp -d "$SCRATCH/runner-smoke.XXXXXX" 2>/dev/null || mktemp -d)
mkdir -p "$FX/repo"
git -C "$FX/repo" init -q -b main
git -C "$FX/repo" config user.email t@t.dev
git -C "$FX/repo" config user.name smoke-tester
echo x > "$FX/repo/f.txt" && git -C "$FX/repo" add f.txt && git -C "$FX/repo" commit -qm init

cat > "$FX/pointer.txt" <<'EOF'
Report the current git HEAD short SHA in this repo (git rev-parse --short HEAD), write nothing to
any file, make no commits, and end your final message with the exact line
RUNNER_DONE
EOF
printf 'smoke-repro\t%s\t%s\n' "$FX/repo" "$FX/pointer.txt" > "$FX/queue.tsv"

bash ~/.claude/dwarves-kit/lib/orchestrate.sh queue "$FX/queue.tsv" --dry-run   # sanity first

tmux new-session -d -s smoke-repro-outer bash -lc \
  "caffeinate -dims bash '$HOME/.claude/dwarves-kit/lib/orchestrate.sh' queue '$FX/queue.tsv' --journal '$FX/queue-journal.tsv' > '$FX/outer.log' 2>&1"

# poll: cat "$FX/queue-journal.tsv" (expect a `done` row within ~30-60s for this trivial pointer)
```
