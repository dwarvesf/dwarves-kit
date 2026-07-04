# Spec: Overnight queue launcher (runner-fastpath sub-goal 03K)

Generated: 2026-07-05
Status: VALIDATED
Lane: full (classified `full` by `lib/lane-classify.sh`; drives a live
`--dangerously-skip-permissions` Claude Code session unattended overnight, so it is
security-bearing and full-lane by the AGENTS.md trigger list even though it adds a new
sibling lib rather than touching an existing enforcement surface)
Design: bearing (a novel execution model, see `## Design` below): the launcher drives the
REAL interactive Claude Code `/goal` interface via terminal-mux send-keys, not a headless
`claude -p`. Two+ viable mechanisms (tmux send-keys vs Computer-Use), a new state machine,
and a new completion-marker contract, so the design record is non-empty by construction.
Depends on: runner-fastpath sub-goal 04 (`board queue` emit) for the `--from-boards` source;
NOT blocked on it (a hand-authored tsv is a first-class source; 04's rows are consumed on the
SAME `slug<TAB>repo-path<TAB>pointer-path` contract, stubbed in tests).

## Problem

A drafted mega-goal takes ~2-3h wall and Han can supervise one at a time, so the queue of
drafted megas drains one per sitting. The fix (runner-fastpath design, `## 2. Mega-runner`)
is a dumb sequential scheduler that runs the queue overnight.

The naive scheduler is a headless `claude -p` loop. That path has a field-proven
AUTH/KILL-CLASS risk (documented in ops-toolkit `_meta/megagoals/OPERATE.md`): a headless
worker's token expiring or the process being killed independently has bitten twice. The
counter-move (Han's explicit call): drive the operator's LIVE, already-authed interactive
Claude Code session instead. The launcher types `/goal <pointer>` into a fresh terminal-mux
window and watches that window's output for a completion marker, so it rides the operator's
real login and never manages a headless token.

## Solution

A bash launcher, `lib/queue.sh`, exposed both standalone (`queue.sh run <src>`) and as an
`orchestrate.sh queue <src>` alias (a one-line dispatch arm; the logic lives in `queue.sh`,
so orchestrate.sh's existing suite is untouched). It is NOT an LLM and NOT a headless
`claude -p` loop.

### Approaches considered

1. **Terminal-mux send-keys into a REAL interactive `/goal` session (CHOSEN).** `tmux
   new-window` + `tmux send-keys -l` types `/goal <pointer>` + Enter into a fresh window
   running interactive `claude`; the launcher polls `tmux capture-pane` for the completion
   marker. Deterministic (L0/L1 on the `macos-action-selection` ladder), no GUI, no pixel
   vision, rides the operator's live auth. This is the primary mechanism.
2. **Computer-Use / peekaboo (L4) vision loop.** Screenshot + click + type via
   `mcp__computer-use__*`. REJECTED as primary (slow, brittle, non-deterministic, needs a
   foreground GUI) but retained as the DOCUMENTED fallback for a mux-uncontrollable
   interface (the mechanism ladder in `## Design`).
3. **Headless `claude -p` (the design doc's first cut).** REJECTED per the AUTH/KILL-CLASS
   risk above; it is the exact thing this sub-goal exists to sidestep.

### CONSUMER config (keys + defaults)

Nothing personal is hardcoded; every host-specific value is read at runtime.

| Key | Default | Meaning |
|---|---|---|
| `TERMINAL_MUX` | `tmux` | which mux to drive. `tmux` is the ONLY supported value (cmux was dropped, see the AMENDMENT below) |
| `MUX_CMD` | `$TERMINAL_MUX` | the mux binary (the mock seam; tests point it at a fake) |
| `QUEUE_CLAUDE_CMD` | `claude` | the interactive Claude Code binary launched in the window |
| `QUEUE_CLAUDE_FLAGS` | `--dangerously-skip-permissions` | flags for the launched session (full-auto overnight) |
| `QUEUE_JOURNAL` | `${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}/queue-journal.tsv` | the append-only journal |
| `QUEUE_POLL_SECS` | `15` | capture-pane poll interval |
| `QUEUE_TIMEOUT_SECS` | `7200` | per-mega stall ceiling (2h) -> `stalled` |
| `QUEUE_RETRY_SLEEP_SECS` | `1800` | sleep before the single launch-failure retry (30m) |
| `QUEUE_STARTUP_SECS` | `20` | best-effort wait for the TUI to become input-ready before typing (AMENDMENT) |
| `QUEUE_SUBMIT_SETTLE_SECS` | `2` | settle time between submit-verify retries (AMENDMENT) |
| `QUEUE_BOARD_CMD` | `board` | the `--from-boards` source command (sub-goal 04) |
| `QUEUE_MUX_SESSION` | `dk-queue` | the tmux session the windows live in |
| `QUEUE_ALLOWED_POINTER_GLOB` | `_meta/megagoals/* .claude/goals/*` | defense-in-depth pointer confinement for `--from-boards` rows (AMENDMENT) |

### Journal (`queue-journal.tsv`)

Append-only TSV, four columns: `ts<TAB>slug<TAB>verdict<TAB>reason`. `ts` is UTC ISO-8601.
Verdicts: `done` / `gated` / `stalled` / `skipped` / `error`. A slug that already has a
`done` row is skipped on re-run (idempotent nights): the journal is the state.

### Queue row contract (fixed, shared with sub-goal 04)

`slug<TAB>repo-path<TAB>pointer-path`, one row per mega. Parsed argv-safe with
`while IFS=$'\t' read -r slug repo pointer` -- never `eval`, never an unquoted expansion, so
shell metachars in any field stay literal and never reach a shell. `#`-comment and blank
lines are skipped. A hand-authored tsv is allow-list-exempt by design; `--from-boards` rows
have already passed sub-goal 04's `_meta/megagoals/**` / `.claude/goals/**` allow-list, so
the launcher does not re-implement it.

## Design

> This is the `bearing`-design block required by the sub-goal: the launch->monitor->next state
> machine + the mux/Computer-Use mechanism ladder.

### The launch -> monitor -> next state machine

```
for each queue row (slug, repo, pointer), in order:

  ├─ journal already has "slug done" ──────────► skip (idempotent), next row
  │
  ├─ PREFLIGHT (all before any window opens):
  │     repo missing / not a git repo ─────────► journal skipped "repo missing", next row
  │     tree dirty (status --porcelain != "") ──► journal skipped "dirty tree", next row
  │     not on default branch ──────────────────► journal skipped "not on <branch>", next row
  │
  └─ LAUNCH:
        open a fresh mux window in <repo>, running interactive `claude`
        send-keys  '/goal ' + <pointer-content> + Enter        (literal, argv-safe)
        │
        └─ MONITOR (poll capture-pane every POLL_SECS, ceiling TIMEOUT_SECS):
              line matches ^RUNNER_DONE$        ─► journal done,    kill window, err=0, next
              line matches ^RUNNER_GATED:       ─► journal gated,   kill window, err=0, next
              window/pane died (claude exited)  ─► LAUNCH-FAIL
              TIMEOUT_SECS elapsed, no marker   ─► journal stalled, kill window, err=0, next

LAUNCH-FAIL:
   sleep RETRY_SLEEP_SECS (30m); retry the launch ONCE
   still failing ─► journal error; err++;  err >= 2 ─► STOP THE NIGHT (later rows untouched)
```

**Completion contract (the only clever part).** The launcher reads the launched session's
OUTPUT MARKER, never a fixed sleep and never a guess. The pointer prompt is authored to end
its final message with exactly one of:

- `RUNNER_DONE` -- the pointer's terminal state is reached.
- `RUNNER_GATED: <reason>` -- a genuine STOP per the pointer (a held human gate, a failing
  launch guard, a budget stop). Checkpoint bookkeeping happens inside the session BEFORE the
  marker; the launcher just records it and moves on.

Markers are matched **LINE-ANCHORED** (`grep -E '^RUNNER_DONE$'` / `'^RUNNER_GATED:'`), so a
session (or the typed `/goal` command echo) quoting the marker text mid-prose cannot
false-trigger: `end your final message with the exact line RUNNER_DONE` is one line, not a
line that IS `RUNNER_DONE`.

**error-twice-stops-night.** A launch that fails twice (nonzero claude exit / dead window,
after the single 30-min retry) journals `error`. Two CONSECUTIVE `error` rows stop the whole
night (assume an account-level rate limit; do not burn the rest of the queue). A `done`,
`gated`, or `stalled` verdict RESETS the consecutive-error counter; a `skipped` row is a
deterministic pass-through that neither increments nor resets it (so `error, skipped, error`
still stops the night -- the cautious direction). `gated`/`stalled` are per-pointer stops
that MOVE ON (the runner records and continues, per the runner-fastpath risks table); only
`error` (the rate-limit signal) accrues toward the night-stop. This is the reconciliation of
the design doc's "two consecutive failed/gated" parenthetical against its own risks table and
NC3 (which tests `error`); recorded in the implementation notes.

### The mux / Computer-Use mechanism ladder

Per the `macos-action-selection` L0-L4 ladder; PRIMARY is send-keys, Computer-Use is the
documented last resort.

| Rung | Mechanism | Used here |
|---|---|---|
| L0/L1 | terminal-mux send-keys (`tmux`/`cmux new-window` + `send-keys` + `capture-pane`) | **PRIMARY.** Deterministic, no GUI, rides the live login. `TERMINAL_MUX` picks tmux (default) or cmux. |
| L4 | Computer-Use (`mcp__computer-use__*`) / peekaboo vision loop | **FALLBACK ONLY**, for an interface with no mux (a GUI-only Claude surface). Not built into the bash launcher; documented as the manual escape hatch. |

The mux verbs are wrapped in `_mux_*` functions that translate to the selected mux's CLI and
invoke `$MUX_CMD`, so both the mux choice AND the binary are CONSUMER-swappable and the whole
mechanism is mockable in tests via a fake `$MUX_CMD`.

## Test plan

bats suite `tests/test-queue.bats`, driven entirely by a STUB mux (a fake `$MUX_CMD` whose
`capture-pane` returns a canned transcript). NO real UI and NO real `claude` in the suite.

| # | Category | Case | Asserts |
|---|---|---|---|
| T1 | happy | one clean row, transcript ends `RUNNER_DONE` | journal `done`, window opened + killed |
| T2 | happy | transcript ends `RUNNER_GATED: held` | journal `gated`, moves on |
| T3 | dry-run | `--dry-run` over a clean row | prints "would launch", NO send-keys, no journal run row |
| T4 | source | `--from-boards` via stub `QUEUE_BOARD_CMD` | rows consumed on the tsv contract |
| NC1 | dirty-tree skip | repo has an uncommitted change | journal `skipped`, NO window opened |
| NC2 | prose-quotes-completion | transcript has `... the line RUNNER_DONE` mid-prose, no anchored marker | NOT `done`; waits then `stalled` |
| NC3 | error-twice-stops-night | two rows whose launch dies twice | night stops after row 2; later row 3 untouched (no journal row) |
| NC4 | journal-done-idempotence | journal preseeded `slug done` | row skipped, no window opened |
| NC5 | queue-metachar argv-safe | slug/repo/pointer carry `; rm -rf / $(x)` | fields stay literal in journal + fake-mux argv; no shell exec |

Plus one LIVE smoke (real tmux, this machine, throwaway mktemp fixture repo + pointer): the
launcher opens a tmux window, sends `/goal <fixture>`, the session completes, journal shows
`done`. Recorded in `docs/proof-of-done.md`.

## Verification

```
bats tests/test-queue.bats          # all T/NC cases green (stub mux)
bash lib/queue.sh run <tsv> --dry-run   # dry-run listing, no send-keys
# live smoke: see docs/proof-of-done.md (real tmux, throwaway repo)
```

## After state

- `lib/queue.sh` exists: the `run` launcher with preflight, mux send-keys, marker poll,
  journal, error-twice-stops-night, `--dry-run`, `--max-megas`, `--from-boards`.
- `orchestrate.sh queue <src>` dispatches to it (one-line arm).
- `tests/test-queue.bats` green: T1-T4 + NC1-NC5.
- `docs/proof-of-done.md` carries the run-table, the live tmux smoke, the `--dry-run`
  sample, the COVERAGE-DELTA, and the rung-4 `VERDICT: SECURE`.
- CONSUMER config documented; no personal data in the kit.

## AMENDMENT 2026-07-05 (post multi-lens review; binding hardening on top of the design above)

A parallel security + architecture review (dispatched before push, per SPEC-069's "touches
`lib/` needs multi-lens" escalation) found real gaps the live smoke and the first bats pass had
not caught. All are fixed; the state machine, journal, and row contract above are otherwise
unchanged. Full narrative: `docs/implementation-notes/orchestrate-queue.md`.

1. **cmux dropped (architecture HIGH).** The first cut mapped every `_mux_*` verb to a `cmux`
   dialect too. This repo's OWN prior CLI verification (`SPEC-119` DEC-001, `SPEC-121` DEC-004)
   already found cmux has no `new-window -- cmd args...` argv-safe launch primitive. Shipping an
   unverified, likely-wrong cmux path against a skip-permissions session was worse than not
   having one. `TERMINAL_MUX=tmux` is now the only supported value; unsupported values are
   rejected loudly (`_mux_ensure_session`).

2. **Completion marker false-positive from the wrapped `/goal` echo (security CRITICAL).**
   `_goal_line` flattens the whole pointer into ONE long typed line, and a pointer is DESIGNED to
   instruct printing `RUNNER_DONE`. A wide-enough pane soft-wraps that echoed line so the marker
   substring can land ALONE on its own rendered row, indistinguishable from a real completion by
   line-anchoring alone. Fix: `_scan_marker` now ALSO requires the marker line be the first
   captured line OR immediately preceded by a blank line (confirmed against the live smoke's real
   completion output, which is always blank-line-flanked; a wrap continuation of one long
   sentence never has a blank line above it). Locked by NC6.

3. **Missing allow-list defense-in-depth on `--from-boards` rows (security CRITICAL).** Sub-goal
   04's board emit is SUPPOSED to confine pointers before ever emitting a row, but this launcher
   must not simply trust an upstream tool has no bugs when the destination is an unattended,
   skip-permissions session. Fix: `_pointer_allowlist_reason` (new) confines `--from-boards`
   pointers to `QUEUE_ALLOWED_POINTER_GLOB` (default `_meta/megagoals/* .claude/goals/*`),
   resolved via `realpath` (so a `..` traversal AND a symlink planted inside the allowed dir but
   pointing outside the repo are both caught, not just a naive prefix check). A hand-authored tsv
   stays EXEMPT (operator authorship is the trust boundary for that path). Locked by T5/T6/T7.

4. **`stalled` now also stops the night (architecture/security MEDIUM).** The original design
   only counted `error` toward the 2-consecutive stop. A review found repeated `stalled` (a hang,
   not a crash) is an equally valid "the launch mechanism itself is dysfunctional" signal and
   would otherwise silently burn a whole night's remaining queue. Fix: `error` and `stalled` now
   share one `consec_fail` counter; `done`/`gated` still reset it; `skipped` is still a
   pass-through. Locked by NC7.

5. **Journal `reason` tab/newline-stripped (security MEDIUM).** A `gated:` reason is pane text,
   not operator-authored; an embedded tab could shift the row's field count for tooling that
   parses the journal by column (the `done`-idempotence check itself is column-exact and was
   unaffected). Fix: `_journal_append` strips `\t`/`\r` and folds `\n` to a space before writing.

6. **Slug validated against tmux target-separator chars (security LOW).** A slug containing `:`
   or `.` could resolve to an unintended `session:window` target. Fix: `_slug_ok` rejects such
   slugs before any mux verb runs.

Test suite grew from 9 to 14 cases (T1-T7 + NC1-NC7); all green, stub mux only. A second live
tmux smoke (`smoke-head2`, pointer under an allow-listed `_meta/megagoals/**` path) re-confirmed
end-to-end behavior post-fix. A second red-team round (path-traversal + symlink-escape allow-list
bypass attempts, marker-wrap false-trigger attempt) also came back SECURE; see
`docs/verification/queue-launcher/proof-of-done.md`.
