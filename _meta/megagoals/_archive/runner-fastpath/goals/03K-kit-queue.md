# Sub-goal 03K: kit-queue (launcher)

**Merge policy:** auto
**Time budget:** 3-5 hours
**Proof:** OVER-TEST: test-plan + run-table (bats asserts with a STUB mux target) + five named negative controls (dirty-tree skip, prose-quotes-completion-no-false-done, error-twice-stops-night, journal-done-idempotence, queue-metachar argv-safe) + ONE live smoke (launch a throwaway fixture `/goal` in a real tmux window on the Air, watch it complete, journal `done`) + COVERAGE-DELTA row + the rung-4 captured `VERDICT: SECURE`
**Design:** bearing (a novel execution model: drive the REAL Claude Code interface, not headless claude -p). Spec MUST carry a `## Design` block: the launch->monitor->next state machine + the mux/Computer-Use mechanism ladder.
**Repo:** dwarves-kit (harness machinery; hand-made worktree from `master`). Mux/terminal specifics are CONSUMER config.
**Depends on:** 04 for the `--from-boards` source (also accepts a plain tsv, so it can land independently; agree the row format `slug<TAB>repo-path<TAB>pointer-path`).
Model: opus
**Branch:** `feat/orchestrate-queue` (dwarves-kit)
**PR base:** master

## Outcome

`dwarves-kit` gains an overnight queue LAUNCHER (bash). For each queued+tokened backlog mega, it opens a REAL interactive Claude Code `/goal` session and drives it via scripting-control (types `/goal ` + the pointer prompt + Enter into a fresh terminal-mux window), monitors that session to completion, then launches the next. It runs on Han's LIVE logged-in session, NOT a headless `claude -p` in the background , which sidesteps the AUTH/KILL-CLASS risk OPERATE documents (a headless worker's token expiring / being killed independently). Journal, error-stops-night, idempotent nights.

## Quality bar

Bash launcher, NOT a headless `claude -p` loop and NOT an LLM. Mechanism ladder (per the `macos-action-selection` skill): PREFER terminal-mux send-keys , `tmux new-window` + `tmux send-keys` (or the cmux equivalent) to type the `/goal` prompt , deterministic, no GUI (L0/L1); Computer Use (`mcp__computer-use__*`, L4) is the FALLBACK only when the interface is not mux-controllable. The mux/terminal choice is CONSUMER config (`TERMINAL_MUX=tmux|cmux`, a target-window convention), not hardcoded. Completion detection READS the launched session's output marker (the `/goal` loop's `RUNNER_DONE`/`RUNNER_GATED` final line, or its Stop-hook completion) , never a fixed sleep, never a guess (line-anchored; prose quoting the marker must not false-trigger). Every launch + exit lands a journal row (no silent verdicts). Error-twice (two consecutive failed/gated megas where a gate needs Han) STOPS THE WHOLE NIGHT, 30-min sleep between tries. The pointer is TYPED as a trusted, allow-listed path-backed prompt (04 confines pointers to `_meta/megagoals/**` or `.claude/goals/**` in registered repos); the queue-row PARSE is argv-safe (metachars never reach a shell).

## How to close the loop

- `orchestrate.sh queue <src> [--dry-run] [--max-megas N]` (a `queue` subcommand on orchestrate.sh, or a sibling `lib/queue.sh` per kit convention): parse the queue (tsv, or `--from-boards` via `board queue`); for each row: skip unless the repo exists + clean + on its default branch (journal `skipped` + reason); else open a fresh mux window, send-keys `/goal ` + the pointer + Enter, then POLL that window's captured output for the completion marker (with a per-mega timeout -> `stalled`); journal the verdict (done/gated/stalled/skipped/error); next.
- Journal `queue-journal.tsv`: ts, slug, verdict, reason. A row already `done` in the journal is skipped on re-run (idempotent nights).
- `--dry-run` lists which megas WOULD launch (no send-keys); the pre-night sanity command 06's runbook prescribes.
- Tests (bats): inject a STUB mux (a fake window whose "output" is a canned transcript ending in `RUNNER_DONE` or `RUNNER_GATED`); NO real UI, NO real `claude` in the suite. NCs: (1) dirty tree -> skipped, no window opened; (2) a transcript whose PROSE quotes `RUNNER_DONE` mid-line but has no anchored final marker -> not marked done (keeps waiting/times out); (3) two consecutive `error` megas -> night stops, later rows untouched; (4) journal `slug done` -> skipped (idempotence); (5) a queue row with shell metachars in slug/repo/pointer -> parsed as untouched fields, never a shell.
- Live smoke (Air, real tmux): queue ONE throwaway fixture pointer ("report HEAD, write nothing, end with RUNNER_DONE"); the launcher opens a tmux window, sends `/goal <fixture>`, the session completes, journal shows `done`. Fixture under tmp; the launcher NEVER git-commits anywhere.

**Done =** bats green with the five NCs (stub mux) AND the live tmux smoke journal row captured in proof-of-done AND `--dry-run` demonstrated AND the rung-4 `VERDICT: SECURE`. Kit-adopted: read AGENTS.md + WORKFLOW.md, lane-classify, record gate-ledger phases before push.

**Rung 4 (UNATTENDED, drives a live session):** an in-harness `kit:security-reviewer` tries to (a) make a malicious board Notes cell inject a non-allow-listed pointer or a shell command through the queue parse / send-keys, and (b) break the error-stops-night guard. Frozen diff `git diff master...HEAD`; fail-closed; cap 3 rounds; record `redteam` gate-ledger rows.

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. HANDOFF: next = 06 (Air runbook runs `orchestrate.sh queue`); first action = read the mux mechanism + the completion-marker poll (file:line).
3. DECISIONS: the mux mechanism chosen (tmux/cmux send-keys), the completion-marker contract, the CONSUMER config keys, the journal format.
4. Report IN the records, EXIT.

## Scope edges

**In:** the `queue` launcher (bash, dwarves-kit), the mux send-keys + Computer-Use-fallback mechanism, the completion monitor, journal, tests, `## Design` spec.
**Out:** the board queue EMIT (04), what the LAUNCHED `/goal` session does internally (its own run-mode), launchd, the runbook (06).
**Not:** headless `claude -p` as the primary path, a Go anything, a daemon, parallel megas, board parsing.

## Where to look

`dwarves-kit/lib/orchestrate.sh` (the per-mega driver a launched session may use internally; and its `--stream`/tmux-pane precedent), `commands/assign.md`, `lib/backlog.sh`, the `macos-action-selection` skill (the mux/Computer-Use ladder), the runner design doc + its 2026-07-05 amendment.

## PR body

- Outcome: `orchestrate.sh queue` (bash, dwarves-kit): overnight launcher that drives REAL Claude Code `/goal` sessions via terminal-mux send-keys (Computer-Use fallback), on the live session; journal, error-stops-night, idempotent.
- Verification: bats run-table (stub mux) + 5 NCs + live tmux smoke + `--dry-run` + `VERDICT: SECURE`.
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`.

## Notes
