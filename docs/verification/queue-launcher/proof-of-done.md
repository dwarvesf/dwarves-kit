# Proof of done: overnight queue launcher (SPEC-146, runner-fastpath sub-goal 03K)

Spec: `docs/specs/SPEC-146-overnight-queue-launcher.md` · Lane: full · rid: `orchestrate-queue`

## Acceptance criteria

| # | Criterion | Met by | Status |
|---|---|---|---|
| A1 | `queue.sh run <src>` launches each queued mega in a fresh mux window via `/goal` send-keys | `lib/queue.sh` `_launch_once` (+ `orchestrate.sh queue` alias) | PASS |
| A2 | Completion detected by READING the session's line-anchored marker, never a fixed sleep | `_scan_marker` (`^\s*RUNNER_DONE\s*$` / `^\s*RUNNER_GATED:`) | PASS |
| A3 | Every launch + exit lands a journal row (`ts,slug,verdict,reason`) | `_journal_append`; `queue-journal.tsv` | PASS |
| A4 | Preflight skips (repo missing / dirty / off-default-branch) BEFORE any window opens | `_repo_skip_reason`; NC1 | PASS |
| A5 | Idempotent nights: a `done` slug is skipped on re-run | `_journal_has_done`; NC4 | PASS |
| A6 | Two consecutive `error` megas stop the whole night | `cmd_run` consec-err counter; NC3 | PASS |
| A7 | Queue-row parse is argv-safe (metachars never reach a shell) | `while IFS=$'\t' read`; `send-keys -l --`; NC5 + red-team RT-a | PASS |
| A8 | `--dry-run` lists would-launch, no send-keys, no journal | `cmd_run` dry branch; T3 + dry-run sample | PASS |
| A9 | mux + interactive claude are CONSUMER config, nothing personal hardcoded | env block in `lib/queue.sh` | PASS |
| A10 | bearing `## Design` block (state machine + mechanism ladder) | SPEC-146 `## Design` | PASS |

## Implementation

- `lib/queue.sh` (404 src lines): preflight -> mux `new-window` (interactive `claude`) ->
  wait-ready -> `send-keys -l` `/goal <pointer>` -> verify-submit -> poll `capture-pane` for the
  line-anchored marker -> journal -> next; single-retry launch-failure policy; error-twice stops
  the night; `--dry-run` / `--max-megas` / `--from-boards`.
- `lib/orchestrate.sh`: one-line `queue) exec queue.sh run "$@"` alias (its own suite untouched).
- Mechanism: terminal-mux send-keys is PRIMARY (L0/L1); Computer-Use (L4) documented as the
  fallback. `TERMINAL_MUX=tmux|cmux`; `MUX_CMD` is the mock seam.
- `tests/test-queue.bats` (235 lines) + `tests/fixtures/queue/{fake-mux,fake-board}`.

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| bats suite (9 cases) | `bats tests/test-queue.bats` | 9/9 ok |
| T1 happy done | RUNNER_DONE (indented) -> done, window opened+killed | ok |
| T2 happy gated | RUNNER_GATED -> gated, reason captured | ok |
| T3 dry-run | `--dry-run` -> WOULD LAUNCH, no send-keys, no journal | ok |
| T4 from-boards | `--from-boards` via stub `board queue` | ok |
| NC1 dirty-tree-skip | dirty repo -> skipped, NO window opened | ok |
| NC2 prose-quotes-completion | mid-prose `RUNNER_DONE` -> NOT done -> stalled | ok |
| NC3 error-twice-stops-night | 2 dead launches -> night stops, row 3 untouched | ok |
| NC4 journal-done-idempotence | preseeded `done` -> skipped, no window | ok |
| NC5 queue-metachar argv-safe | metachar fields literal in journal + argv, no exec | ok |
| LIVE smoke (real tmux + real claude) | `queue.sh run <throwaway.tsv>` | journal `done` |
| `--dry-run` demo | 3-row tsv (clean/dirty/missing) | launch/skip/skip |
| COVERAGE-DELTA | `coverage-delta.sh check . master` | `ok` src=404 test=235 |
| Rung-4 red-team | injection + error-stop attacks | `VERDICT: SECURE` |

## Run detail

### bats (stub mux, no real UI, no real claude)

```
1..9
ok 1 T1 happy: RUNNER_DONE -> done, window opened and killed
ok 2 T2 happy: RUNNER_GATED -> gated, moves on
ok 3 T3 dry-run: lists would-launch, no send-keys, no journal
ok 4 T4 from-boards: rows consumed from stub board queue emit
ok 5 NC1 dirty-tree-skip: dirty repo skipped, no window opened
ok 6 NC2 prose-quotes-completion-no-false-done: mid-line marker never triggers done
ok 7 NC3 error-twice-stops-night: 2 consecutive errors stop the night, later rows untouched
ok 8 NC4 journal-done-idempotence: a done slug is skipped on re-run
ok 9 NC5 queue-metachar-argv-safe: metachar fields are literal, no shell exec
```

### LIVE tmux smoke (this machine: tmux 3.7a + claude 2.1.201)

A throwaway `git init` repo + pointer under `mktemp` (never a real repo/board; the launcher only
opened a tmux window and read its output, never `git add/commit/init`). Pointer: "report the git
HEAD short SHA, write nothing, end the final message with the exact line RUNNER_DONE".

```
[queue] smoke-head: launching /goal in a tmux window (repo=/…/tmp.joIm3SLgVS/tw).
[queue] smoke-head: done.

# queue-journal.tsv:
2026-07-04T20:36:06Z<TAB>smoke-head<TAB>done<TAB>
```

The launched pane (captured mid-run) showed the real `/goal` loop completing:
`⏺ Bash(git rev-parse --short HEAD) ⎿ 5211e83` … `RUNNER_DONE` … `✔ Goal achieved (8s · 1 turn)`.
The throwaway repo's tracked tree was left untouched by the launcher.

**Smoke-found bug, fixed (the reason a live leg is mandatory):** the real Claude Code TUI renders
the assistant's final line INDENTED inside its message block, so a strict `^RUNNER_DONE$` MISSED
the real pane. The anchor was relaxed to "marker is the only non-space token on its line"
(`^[[:space:]]*RUNNER_DONE[[:space:]]*$`), which still rejects mid-prose (NC2). A SECOND
smoke-found bug: an early Enter is dropped while the typed text stays unsent, so a readiness-wait
(`_mux_wait_ready`) + a verify-and-resubmit loop (`_mux_submit`) were added. Both are locked into
the suite (T1/T2 use the indented rendering).

### `--dry-run` sample (clean / dirty / missing repo)

```
[dry-run] alpha: WOULD LAUNCH (repo=$D/clean pointer=$D/ptr.txt)
[dry-run] bravo: WOULD SKIP (dirty tree)
[dry-run] charlie: WOULD SKIP (repo missing)
# no journal written -- dry-run touched nothing
```

### COVERAGE-DELTA

```
[coverage-delta] ok: source + test moved together (src=404 test=235 lines)
```

## Rung 4 (UNATTENDED red-team): VERDICT: SECURE

Because this tool drives a live, skip-permissions session unattended overnight, a self-adversarial
pass targeted (a) injecting a shell command / non-allow-listed pointer through the parse /
send-keys path, and (b) breaking the error-stops-night guard. Run isolated (stub mux, temp dirs).

**(a) Command injection through parse + send-keys , BLOCKED (fail-closed).** A queue row with a
metachar slug (`ev;il&$(touch PWNED)|\`id\``) and a pointer whose CONTENT was a shell-injection
attempt (`rm -f <sentinel>; $(touch <s>.pwn) \`touch <s>.bt\`; rm -rf <treedir>`) was run to
completion:

```
verdict reached done:     done
sentinel file survives:   YES-SECURE      # rm -f never executed
no .pwn (cmd-subst):      YES-SECURE      # $(touch ...) never executed
no .bt  (backtick):       YES-SECURE      # `touch ...` never executed
no PWNED (slug subst):    YES-SECURE      # slug $(touch PWNED) never executed
TREEDIR survives rm-rf:   YES-SECURE      # rm -rf <dir> never executed
slug journaled literal:   YES-SECURE      # untouched literal field in the journal
payload in send-keys log: YES-typed-as-inert-data
```

Why it is blocked: the row is parsed with `while IFS=$'\t' read -r` (no `eval`, no unquoted
expansion), the pointer content is TYPED via `send-keys -l -- "$text"` (literal keystrokes, `--`
stops option parsing) so it is data to the launched claude, never a shell parse; the slug reaches
only `git -C` (quoted) and tmux `-n`/`-t` (quoted argv), never a shell. Metachars stay literal
end-to-end.

**(b) Error-stops-night guard , HOLDS.**

```
RT-b1  e1,e2 both error   -> e3 never attempted (YES-SECURE: night stopped)
RT-b2  error,skipped,error-> x4 never attempted (YES-SECURE: skip is pass-through, did not reset)
RT-b3  error,done,error   -> continues (BY DESIGN: a success resets the rate-limit circuit-breaker)
```

The counter increments only on `error`, resets on `done`/`gated`/`stalled`, and a `skipped` row is
a deterministic pass-through that neither increments nor resets , so an attacker cannot slip a
dirty-tree skip between two errors to dodge the stop (RT-b2). RT-b3 is the documented, intended
behavior: the stop is a rate-limit circuit-breaker for CONSECUTIVE failures, not an adversarial
defense against a queue author (the trust boundary is sub-goal 04's allow-list for board-sourced
pointers + operator authorship for hand-authored tsvs, per SPEC-146 `## Design`).

No fail-open path was found: `_launch_once` always prints a verdict or returns 2 (-> `error`), so
there is no empty-verdict route that would silently reset the counter.

**VERDICT: SECURE**

## Reproduce

```
cd <this repo>
bats tests/test-queue.bats
bash lib/coverage-delta.sh check . master --rid orchestrate-queue
# dry-run + live smoke: see the two blocks above (throwaway mktemp repo + pointer)
```
