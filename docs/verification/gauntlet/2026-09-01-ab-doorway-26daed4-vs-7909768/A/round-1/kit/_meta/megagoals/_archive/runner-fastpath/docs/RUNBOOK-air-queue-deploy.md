# Air overnight queue runbook (runner-fastpath sub-goal 06)

Prerequisites, start/attach/read/stop, and failure modes for draining the cross-repo
kanban cockpit overnight by running the dwarves-kit `orchestrate.sh queue` launcher
(SPEC-146) on **the Air** (Han's daily-driver MacBook, `dev laptop`). Phase 1 only:
manual `caffeinate` + `tmux`, zero new daemons. Adapted from the shape of
`tools/hermes/deploy/macos/personal/mini.hermes-runbook.md`; the queue launcher's own
source, tests, and implementation notes live in the sibling `dwarves-kit` checkout
(`~/workspace/<owner>/dwarves-kit/lib/{queue,orchestrate,board}.sh`), not here , this repo
only owns the deploy story for running it on this host.

## What this runs

The kit's `orchestrate.sh queue` opens a REAL interactive Claude Code `/goal` session per
queued backlog item in its own tmux window, types the pointer prompt via `send-keys`,
polls for a completion marker, and moves to the next. It runs on the operator's live
logged-in Claude Code session (not a headless `claude -p` worker), and reads the personal
cross-repo backlog registry at `ops-toolkit/_meta/boards.txt`.

## Status / topology

```
  caffeinate -dims                              (holds sleep-assertions; INSIDE the pane, see Gotcha #1)
        |
   tmux pane "mega-queue" (outer, persists overnight, detached)
        |
   orchestrate.sh queue --from-boards            (bash driver; lib/queue.sh `cmd_run`)
        |
        +-- reads REPO_ROOT/_meta/boards.txt via QUEUE_BOARD_CMD (board.sh)
        |
        +-- for each queued+#queue{}-tokened row:
                 opens a window in tmux session "dk-queue" (QUEUE_MUX_SESSION)
                     -> runs `claude --dangerously-skip-permissions`
                     -> types `/goal <pointer content>` + Enter
                     -> polls capture-pane for RUNNER_DONE / RUNNER_GATED:<reason>
                 appends one row to queue-journal.tsv, kills the window, next row
```

Two tmux sessions, two different lifetimes: the OUTER session (`mega-queue`, your name)
holds the driver process and caffeinate for the whole night; the INNER session
(`dk-queue`, fixed by the kit) holds one window per mega, opened and killed as each row
runs. Attaching to the outer session shows the driver's own progress log; attaching to
the inner session shows a specific mega's live Claude Code pane.

## The three planes (do not mix)

| Plane | What | Lives in | In repo? |
|---|---|---|---|
| Config structure | `lib/{queue,orchestrate,board}.sh`, this runbook | `dwarves-kit` repo (kit source) + `ops-toolkit` (this runbook + `_meta/boards.txt` registry) | yes, split across the two repos it belongs to |
| Secrets | none needed by the launcher itself | N/A , the launched `claude` sessions inherit the operator's ALREADY-authenticated CLI session (same machine, same login); no token/key is read or written by `queue.sh` | no |
| Runtime state | `queue-journal.tsv`, tmux pane scrollback | `$DWARVES_KIT_LOG_DIR/queue-journal.tsv` (default `~/.claude/dwarves-kit/logs/queue-journal.tsv`), a real directory outside any git repo | no (not repo-tracked; nothing to gitignore since it's outside the tree) |

## Prerequisites

1. **The kit resolves with zero extra sync step.** `~/.claude/dwarves-kit/{lib,AGENTS.md,WORKFLOW.md}` are symlinks into `~/workspace/<owner>/dwarves-kit` (confirmed on this machine). No build step , it is bash.
2. **`tmux` + `caffeinate` present.** Verified on this machine: `tmux 3.7a` (`/opt/homebrew/bin/tmux`), `caffeinate` (`/usr/bin/caffeinate`, ships with macOS).
3. **`claude` already logged in, non-interactively-capable.** The launcher opens `claude --dangerously-skip-permissions` in a fresh window; it must come up already-authenticated (same OAuth/keychain session the operator already uses on this machine). No separate credential wiring.
4. **The personal cross-repo registry**: `ops-toolkit/_meta/boards.txt` (already exists, lists 13 repos' `BACKLOG.md` paths).
5. **No `board` binary on PATH by default** , see the corrected invocation below; this is a deviation from the goal file's placeholder.
6. **tmux's pane shell may not be bash.** This machine's `UserShell` (`dscl . -read "$HOME" UserShell`) is `fish`, and tmux spawns each pane using the OS user shell, not the shell you invoked `tmux` from. Fish's `2>&1` is a syntax error (POSIX-only), which silently kills the pane's command near-instantly if you assume bash semantics. **Always wrap the driven command in `bash -lc '...'` explicitly**, regardless of what `$SHELL` reports in your own session.

## Corrected kit invocation (goal file's placeholder did not match reality)

The sub-goal contract sketched `<kit>/bin/orchestrate.sh queue --from-boards`. Verified
against the actual 03K merge (`dwarves-kit` PR #178, squash `358373c`):

- **There is no `bin/orchestrate.sh`.** The real entry point is `lib/orchestrate.sh`,
  reached via `~/.claude/dwarves-kit/lib/orchestrate.sh` (the symlinked path; identical
  content, zero extra sync).
- **`orchestrate.sh queue <args>` already implies `run`** , it is a one-line alias
  (`queue) exec queue.sh run "$@"`). Do not add a literal `run` yourself.
- **`--from-boards` needs `QUEUE_BOARD_CMD` reworked.** There is no `board` binary on
  PATH (the default `QUEUE_BOARD_CMD=board` does not resolve). ops-toolkit's own
  `_meta/board` shim only knows ITS OWN repo's `BACKLOG.md` (`--backlog-file`, no
  `--registry`/cross-repo support) , it cannot serve as `QUEUE_BOARD_CMD` here. The
  correct target is the kit's `board.sh` directly: `QUEUE_BOARD_CMD="bash $HOME/.claude/dwarves-kit/lib/board.sh"`.
  Do **not** append `queue` or `--registry` inside `QUEUE_BOARD_CMD` itself , `queue.sh`
  appends the literal word `queue` as `board.sh`'s FIRST argument (`$QUEUE_BOARD_CMD
  queue`), and `board.sh`'s dispatch requires `queue` to be `argv[1]`. Point it at the
  right registry via the **`REPO_ROOT` environment variable** instead (never a fabricated
  `CONSUMER_ROOT`, no such variable exists anywhere in the kit): `board.sh cmd_queue`
  resolves its registry as `${OPT_REGISTRY:-$REPO_ROOT/_meta/boards.txt}`, so
  `REPO_ROOT=$HOME/workspace/<owner>/ops-toolkit` makes it find `ops-toolkit/_meta/boards.txt`
  with no extra flag.

## The Phase-1 one-liner (config only, no daemon)

Real night, draining the cross-repo cockpit:

```bash
KIT="$HOME/.claude/dwarves-kit/lib"
REPO_ROOT="$HOME/workspace/<owner>/ops-toolkit"
SESSION="mega-queue"                 # outer wrapper session name, pick anything != dk-queue

tmux kill-session -t "$SESSION" 2>/dev/null || true
tmux new-session -d -s "$SESSION" bash -lc "
  REPO_ROOT='$REPO_ROOT' QUEUE_BOARD_CMD='bash $KIT/board.sh' \
  caffeinate -dims bash '$KIT/orchestrate.sh' queue --from-boards
"
```

**Gotcha (verified live on this machine, not a guess): `caffeinate` must wrap the
long-running command INSIDE the tmux pane, never the `tmux` client invocation itself.**
A naive `caffeinate -dims tmux new -d -s mega-queue '...'` (caffeinate wrapping the tmux
launch) is WRONG: `tmux new-session -d` creates the detached session and its own CLIENT
process returns almost instantly, so `caffeinate` sees its child exit within about a
second and releases every sleep-assertion immediately, not for the night. Confirmed with
a throwaway test (`tmux new-session -d -s caftest "caffeinate -dims sleep 8; ..."`): the
`caffeinate` process only lives as long as the command INSIDE the pane, which is exactly
what we want , so `caffeinate` has to be the thing wrapped BY the pane's command, not the
thing wrapping the `tmux` call. The one-liner above already has it right (`caffeinate`
sits inside the `bash -lc "..."` payload, after the env-var prefix, wrapping
`orchestrate.sh queue`).

## Mandatory pre-night step: `--dry-run`

Always run this first, unattended and side-effect-free:

```bash
REPO_ROOT="$HOME/workspace/<owner>/ops-toolkit" \
QUEUE_BOARD_CMD="bash $HOME/.claude/dwarves-kit/lib/board.sh" \
bash "$HOME/.claude/dwarves-kit/lib/orchestrate.sh" queue --from-boards --dry-run
```

Read every `WOULD LAUNCH` / `WOULD SKIP` line before starting a real night. A skip reason
(dirty tree, wrong branch, missing repo) surfaces here with zero windows opened and
nothing written to the journal.

## Attach / detach / read

- **Attach the outer driver:** `tmux attach -t mega-queue` (its own `[queue] <slug>:
  launching / done / skipped / ...` progress log). Detach without killing: `Ctrl-b d`.
- **Attach a specific mega's live Claude Code pane:** `tmux attach -t dk-queue`, then
  `Ctrl-b w` to pick a window by slug name; or peek without attaching:
  `tmux capture-pane -p -t dk-queue:<slug>`.
- **Morning read (the journal is the source of truth):**
  `cat "$HOME/.claude/dwarves-kit/logs/queue-journal.tsv"` (columns: `ts <TAB> slug <TAB>
  verdict <TAB> reason`). A `done` row is the completion contract; re-running the same
  source the next night SKIPS any slug already marked `done` (idempotent nights, no
  double-work).
- Per-mega detail beyond the journal is just tmux pane scrollback (`capture-pane`);
  nothing else is written per mega unless the launched `/goal` session itself writes
  files inside ITS OWN target repo (expected and normal , that IS the work).

## Stop a night safely

- **Let the current row finish, most of the time.** The launcher already self-stops on
  two consecutive `error`/`stalled` verdicts (below); most nights need no manual stop.
- **Hard stop now:** `tmux kill-session -t mega-queue` kills the driver. Any mega
  currently in-flight inside `dk-queue` is now ORPHANED (nothing is polling it anymore) ,
  either let it finish naturally and manually append/ignore its outcome, or
  `tmux kill-session -t dk-queue` to kill it too.
- **The two 3am assumptions baked into the launcher itself** (not this runbook's
  invention , see `lib/queue.sh`'s `cmd_run`): (1) two consecutive `error` OR `stalled`
  verdicts in a row STOP THE NIGHT outright (the theory: the launch mechanism itself is
  broken , auth expired, rate limit, a hung interface , not a single mega's problem);
  later rows are left completely untouched, safe to resume tomorrow with the same
  command (idempotent). (2) completion is detected ONLY by the launched session printing
  its own line-anchored marker (`RUNNER_DONE` / `RUNNER_GATED:<reason>`), NEVER a fixed
  timer; a mega that never prints the marker sits until `QUEUE_TIMEOUT_SECS` (default
  7200s = 2h) elapses, then is marked `stalled`.

## Failure modes

| Symptom | Verdict | What happens |
|---|---|---|
| Target repo has a dirty tree | `skipped` (preflight, no window opened) | logged with reason, next row tried |
| Target repo not on its default branch | `skipped` (preflight, no window opened) | logged with reason, next row tried |
| Target repo missing / not a git repo | `skipped` (preflight, no window opened) | logged with reason, next row tried |
| `--from-boards` pointer resolves outside `_meta/megagoals/**` or `.claude/goals/**` (or via a symlink escape) | `skipped` (defense-in-depth allow-list) | logged with reason, next row tried; a hand-authored `.tsv` is exempt from this check |
| The opened `claude` window exits without ever printing a marker (auth failure, crash, rate-limit) | `error` (after one retry) | if this is the 2nd consecutive `error`/`stalled`, **the whole night stops** |
| Marker never appears within `QUEUE_TIMEOUT_SECS` | `stalled` | same 2-consecutive-stop rule as `error` |
| Session prints `RUNNER_GATED:<reason>` | `gated` | legitimate per-mega terminal state; resets the consecutive-failure counter, moves to next row |
| A slug already has a `done` row in the journal | skipped silently, no window opened | idempotent re-run behavior, not a failure |

## Later options (named, not built , out of scope for this sub-goal)

- **launchd Phase 2.** Trigger: the journal shows a STEADY, unattended nightly cadence
  for a couple of weeks with Han running the exact same manual `tmux new-session ...
  caffeinate ...` one-liner every night with no adjustment needed , only then is it worth
  promoting to a `LaunchAgent` (`StartCalendarInterval`-shaped, mirroring the
  `tools/hermes/deploy/macos/*.plist` BTM-friendly authoring rules in this repo's
  `CLAUDE.md`) so it stops needing a manual keystroke. Not built now: minimum-infra-first
  says Phase 1 (zero new components) is the right size until that friction is actually
  felt.
- **Mini migration.** If leaving the Air awake overnight proves annoying (battery, fan,
  can't close the lid, can't carry it around), the always-on Mac Mini (`ssh
  <mini-host>`) is the natural home: same steps, over `ssh <mini-host> 'tmux
  new-session -d -s mega-queue ...'` instead of running locally; the Mini already never
  sleeps (per its own substrate docs) so `caffeinate` becomes optional there (harmless to
  keep anyway). This paragraph is prose only , not an executed step in this sub-goal
  (needs its own `dwarves-kit` checkout + `~/.claude/dwarves-kit` symlink wiring + PATH on
  the Mini side, none of which is verified here).

## Proof

Live smoke run-table + exact commands + evidence:
`docs/verification/06-deploy-runbook/proof-of-done.md` (this megagoal folder).
