# Proof of done: overnight queue launcher (SPEC-148, runner-fastpath sub-goal 03K)

Spec: `docs/specs/SPEC-148-overnight-queue-launcher.md` (incl. its 2026-07-05 AMENDMENT) · Lane:
full · rid: `orchestrate-queue`

This proof covers TWO passes: the initial build + live smoke, and a multi-lens review round
(security-reviewer + code-reviewer, dispatched per SPEC-069) that found real gaps, all fixed and
re-verified. Read both; the second pass is what earns the final `VERDICT: SECURE`.

**Rollback:** this is a bash CLI tool with no deployed service and no persistent application
state. `lib/queue/queue.sh` writes only an operational log (`queue-journal.tsv`, not application data)
and opens/kills tmux windows; nothing it does outlives the process beyond that log. Rollback is a
plain `git revert` of this branch's commits (no migration, no schema, no data to restore, no
service to roll back). Command: `git log --oneline -3` / Exit: 0 (see the git log below this repo
carries as evidence of the reversible commit history).

## Acceptance criteria

| # | Criterion | Met by | Status |
|---|---|---|---|
| A1 | `queue.sh run <src>` launches each queued mega in a fresh mux window via `/goal` send-keys | `lib/queue/queue.sh` `_launch_once` (+ `orchestrate.sh queue` alias) | PASS |
| A2 | Completion detected by READING the session's marker, never a fixed sleep, and not false-triggered by the typed prompt's own echo | `_scan_marker` (blank-line-guarded; see review fix #2) | PASS |
| A3 | Every launch + exit lands a journal row (`ts,slug,verdict,reason`), reason sanitized | `_journal_append`; `queue-journal.tsv` | PASS |
| A4 | Preflight skips (repo missing / dirty / off-default-branch) BEFORE any window opens | `_repo_skip_reason`; NC1 | PASS |
| A5 | Idempotent nights: a `done` slug is skipped on re-run | `_journal_has_done`; NC4 | PASS |
| A6 | Two consecutive `error`-or-`stalled` megas stop the whole night | `cmd_run` `consec_fail` counter; NC3/NC7 | PASS |
| A7 | Queue-row parse is argv-safe (metachars never reach a shell) | `while IFS=$'\t' read`; `send-keys -l --`; NC5 + red-team RT-a | PASS |
| A8 | `--dry-run` lists would-launch, no send-keys, no journal | `cmd_run` dry branch; T3 + dry-run sample | PASS |
| A9 | mux + interactive claude are CONSUMER config, nothing personal hardcoded | env block in `lib/queue/queue.sh` | PASS |
| A10 | bearing `## Design` block (state machine + mechanism ladder) | SPEC-148 `## Design` | PASS |
| A11 | `--from-boards` pointers are confined by an allow-list independent of the upstream board tool | `_pointer_allowlist_reason` (`realpath`-resolved); T5/T6/T7 | PASS |

## Implementation

- `lib/queue/queue.sh` (571 src lines): preflight (repo + allow-list) -> mux `new-window` (interactive
  `claude`) -> wait-ready -> `send-keys -l` `/goal <pointer>` -> verify-submit -> poll
  `capture-pane` for the blank-line-guarded marker -> journal -> next; single-retry
  launch-failure policy; error-or-stalled-twice stops the night; `--dry-run` / `--max-megas` /
  `--from-boards`.
- `lib/queue/orchestrate.sh`: one-line `queue) exec queue.sh run "$@"` alias (its own suite untouched).
- Mechanism: terminal-mux send-keys is PRIMARY (L0/L1); Computer-Use (L4) documented as the
  fallback. `TERMINAL_MUX=tmux` ONLY (cmux dropped, see review fix #1). `MUX_CMD` is the mock seam.
- `tests/test-queue.bats` (340 lines, 14 cases) + `tests/fixtures/queue/{fake-mux,fake-board}`.

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| bats suite (14 cases) | `bats tests/test-queue.bats` | 14/14 ok |
| T1 happy done | RUNNER_DONE (indented) -> done, window opened+killed | ok |
| T2 happy gated | RUNNER_GATED -> gated, reason captured | ok |
| T3 dry-run | `--dry-run` -> WOULD LAUNCH, no send-keys, no journal | ok |
| T4 from-boards | `--from-boards` via stub `board queue`, pointer allow-listed | ok |
| T5 from-boards-pointer-allowlist | non-allow-listed pointer -> skipped, no window | ok |
| T6 hand-tsv-allowlist-exempt | plain tsv pointer outside glob still launches | ok |
| T7 from-boards-symlink-escape | symlink escaping the repo via the allowed dir -> skipped | ok |
| NC1 dirty-tree-skip | dirty repo -> skipped, NO window opened | ok |
| NC2 prose-quotes-completion | mid-prose `RUNNER_DONE` -> NOT done -> stalled | ok |
| NC3 error-twice-stops-night | 2 dead launches -> night stops, row 3 untouched | ok |
| NC4 journal-done-idempotence | preseeded `done` -> skipped, no window | ok |
| NC5 queue-metachar argv-safe | metachar fields literal in journal + argv, no exec | ok |
| NC6 marker-wrap-false-positive | wrapped echo fragment -> NOT done -> stalled | ok |
| NC7 stalled-twice-stops-night | 2 stalls -> night stops, row 3 untouched | ok |
| LIVE smoke #1 (pre-review, real tmux + real claude) | `queue.sh run <throwaway.tsv>` | journal `done`; found 2 bugs, fixed |
| LIVE smoke #2 (post-review, real tmux + real claude) | `queue.sh run <throwaway.tsv>` (allow-listed pointer path) | journal `done`, no regression |
| `--dry-run` demo | 3-row tsv (clean/dirty/missing) | launch/skip/skip |
| COVERAGE-DELTA | `coverage-delta.sh check . master` | `ok` src=571 test=340 |
| Multi-lens review | security-reviewer + code-reviewer (SPEC-069) | 2 CRITICAL + 1 HIGH + 3 MEDIUM/LOW found, ALL FIXED |
| Rung-4 red-team, round 1 | injection + error-stop attacks | SECURE |
| Rung-4 red-team, round 2 | allow-list bypass (traversal + symlink) + marker-wrap injection | SECURE |
| Rung-4 red-team, round 3 (symlink follow-up) | symlink planted inside the allow-listed dir | caught by `realpath` fix, SECURE |
| Kit regression | `tests/test-meta.sh`, `tests/test-orchestrate.sh` | 669/669, ALL PASS (both passes) |

## Run detail

### bats (stub mux, no real UI, no real claude) -- final, post-review state

```
1..14
ok 1 T1 happy: RUNNER_DONE -> done, window opened and killed
ok 2 T2 happy: RUNNER_GATED -> gated, moves on
ok 3 T3 dry-run: lists would-launch, no send-keys, no journal
ok 4 T4 from-boards: rows consumed from stub board queue emit, pointer allow-listed
ok 5 T5 from-boards-pointer-allowlist: a non-allow-listed pointer is skipped, no window opened
ok 6 T6 hand-tsv-allowlist-exempt: a plain tsv pointer outside the glob still launches
ok 7 T7 from-boards-symlink-escape: a symlink escaping the repo via the allow-listed dir is skipped
ok 8 NC1 dirty-tree-skip: dirty repo skipped, no window opened
ok 9 NC2 prose-quotes-completion-no-false-done: mid-line marker never triggers done
ok 10 NC3 error-twice-stops-night: 2 consecutive errors stop the night, later rows untouched
ok 11 NC4 journal-done-idempotence: a done slug is skipped on re-run
ok 12 NC5 queue-metachar-argv-safe: metachar fields are literal, no shell exec
ok 13 NC6 marker-wrap-false-positive: a wrapped echo fragment never triggers done
ok 14 NC7 stalled-twice-stops-night: 2 consecutive stalls stop the night, later rows untouched
```

### LIVE tmux smoke #1, pre-review (this machine: tmux 3.7a + claude 2.1.201)

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

**Two bugs found here, fixed (the reason a live leg is mandatory):** the real Claude Code TUI
renders the assistant's final line INDENTED inside its message block, so a strict `^RUNNER_DONE$`
MISSED the real pane (fixed: relaxed to a non-space-only-token anchor, later tightened again by
the review's blank-line guard, see below). Separately, an early Enter was dropped while the typed
text stayed unsent (fixed: `_mux_wait_ready` + `_mux_submit`'s verify-and-resubmit loop).

### Multi-lens review (SPEC-069: `lib/` changes get review-team, not a single reviewer)

Dispatched a `kit:security-reviewer` and a `kit:code-reviewer` (architecture/correctness lens) in
parallel against the diff, before push. Findings and dispositions:

| # | Severity | Finding | Fix |
|---|---|---|---|
| 1 | HIGH (architecture) | Invented `cmux` verbs (`new-window --name --cwd -- cmd`) never CLI-verified; this repo's OWN `SPEC-119`/`SPEC-121` already found cmux has no such argv-safe primitive | `cmux` dropped; `TERMINAL_MUX=tmux` only, other values rejected loudly |
| 2 | CRITICAL (security) | Completion marker can false-trigger from the WRAPPED ECHO of the typed `/goal` prompt (which is designed to contain "RUNNER_DONE") | `_scan_marker` requires the marker line be first-line-or-blank-preceded (matches the confirmed real rendering; NC6 locks it) |
| 3 | CRITICAL (security) | No allow-list defense-in-depth on `--from-boards` pointer/repo paths; the launcher fully trusted an upstream (not-yet-built) tool | `_pointer_allowlist_reason`, `realpath`-resolved (catches traversal AND symlink escapes); hand-tsv stays exempt (T5/T6/T7) |
| 4 | MEDIUM (both lenses) | Only `error` counted toward the 2-consecutive night-stop; repeated `stalled` could silently burn a whole night | `error`+`stalled` share one `consec_fail` counter (NC7) |
| 5 | MEDIUM (security) | Journal `reason` (pane text) not tab-escaped; an embedded tab could shift a downstream parser's column count | `_journal_append` strips `\t`/`\r`, folds `\n` |
| 6 | LOW (security) | A slug containing `:`/`.` could resolve to an unintended tmux `session:window` target | `_slug_ok` rejects such slugs before any mux verb |

Also noted, not requiring a code change: the resubmit-loop's own retry branch is not directly
exercised by a bats case (only the live smoke proves it fired); accepted as documented residual
risk since the marker-anchor and allow-list fixes were the load-bearing gaps.

Full narrative (why each fix, alternatives considered): `docs/implementation-notes/orchestrate-queue.md`.

### LIVE tmux smoke #2, post-review (real tmux + real claude, security-hardened launcher)

Re-ran end-to-end after all fixes, this time with the pointer placed under an allow-listed path
(`_meta/megagoals/fx/goals/pointer.txt`) as `--from-boards` rows now require:

```
[queue] smoke-head2: launching /goal in a tmux window (repo=/…/tmp.X60wlDGACw/tw).
[queue] smoke-head2: done.

# queue-journal.tsv:
2026-07-04T20:55:16Z<TAB>smoke-head2<TAB>done<TAB>
```

Repo left clean (`git status --porcelain` empty apart from the harness's own untracked `.claude/`).
No regression from the security fixes.

### `--dry-run` sample (clean / dirty / missing repo)

```
[dry-run] alpha: WOULD LAUNCH (repo=$D/clean pointer=$D/ptr.txt)
[dry-run] bravo: WOULD SKIP (dirty tree)
[dry-run] charlie: WOULD SKIP (repo missing)
# no journal written -- dry-run touched nothing
```

### COVERAGE-DELTA (final)

```
[coverage-delta] ok: source + test moved together (src=571 test=340 lines)
```

## Rung 4 (UNATTENDED red-team): VERDICT: SECURE

Because this tool drives a live, skip-permissions session unattended overnight, self-adversarial
passes targeted: (a) command/path injection through the parse/send-keys path, (b) breaking the
error-stops-night guard, (c) bypassing the `--from-boards` allow-list via path traversal or a
symlink, (d) false-triggering the completion marker via a crafted pointer. All run isolated (stub
mux, temp dirs, never the real repos).

**(a) Command injection through parse + send-keys -- BLOCKED (fail-closed).** A queue row with a
metachar slug (`ev;il&$(touch PWNED)|\`id\``) and a pointer whose CONTENT was a shell-injection
attempt (`rm -f <sentinel>; $(touch <s>.pwn) \`touch <s>.bt\`; rm -rf <treedir>`) ran to completion:

```
verdict reached done:     done
sentinel file survives:   YES-SECURE      # rm -f never executed
no .pwn (cmd-subst):      YES-SECURE      # $(touch ...) never executed
no .bt  (backtick):       YES-SECURE      # `touch ...` never executed
no PWNED (slug subst):    YES-SECURE      # slug $(touch PWNED) never executed
TREEDIR survives rm-rf:   YES-SECURE      # rm -rf <dir> never executed
slug journaled literal:   YES-SECURE
payload in send-keys log: YES-typed-as-inert-data
```

Why: the row is parsed with `while IFS=$'\t' read -r` (no `eval`), the pointer content is TYPED
via `send-keys -l -- "$text"` (literal keystrokes, `--` stops option parsing) so it is data to the
launched claude, never a shell parse; the slug reaches only `git -C` (quoted) and tmux `-n`/`-t`
(quoted argv), never a shell.

**(b) Error-stops-night guard -- HOLDS (extended to `stalled`).**

```
RT-b1  e1,e2 both error     -> e3 never attempted (SECURE: night stopped)
RT-b2  error,skipped,error  -> x4 never attempted (SECURE: skip is pass-through, did not reset)
RT-b3  error,done,error,done-> continues (BY DESIGN: a success resets the circuit-breaker)
```

A `skipped` row cannot be used to dodge the stop by interleaving between two failures (RT-b2).
`stalled` now shares the counter with `error` (post-review fix); re-verified with the same
structure substituting `stalled` for `error` -- identical hold.

**(c) `--from-boards` allow-list bypass attempts -- BLOCKED (fail-closed).**

```
traversal verdict: skipped   # ../../.. escape resolved by `pwd -P`/realpath, outside-repo caught
symlink verdict:   skipped   # a symlink INSIDE the allowed dir pointing OUTSIDE the repo,
                              # caught by switching the resolver to `realpath` (follows the link);
                              # the FIRST cut (dir-only pwd -P) would have missed this -- caught by
                              # this very red-team pass, fixed, and now locked by T7
```

**(d) Marker-wrap false-trigger attempt -- BLOCKED (fail-closed).**

```
wrapped-echo verdict: stalled   # a transcript simulating a soft-wrapped /goal echo whose last
                                  # fragment IS "RUNNER_DONE" with NO blank line above it (the
                                  # exact false-positive shape the CRITICAL #2 finding described)
                                  # does NOT trigger done -- the blank-line guard holds
```

No fail-open path was found in any of the four probes: `_launch_once` always prints a verdict or
returns 2 (-> `error`); `_pointer_allowlist_reason` fails closed on any unresolvable path; there is
no route that silently accepts an out-of-scope pointer or resets the failure counter unexpectedly.

**VERDICT: SECURE**

## NEGATIVE CONTROL (revert -> RED -> restore)

Proves the suite actually catches the regression it claims to catch, not just that it currently
passes. Target: the CRITICAL marker-wrap fix (`_scan_marker`'s blank-line guard), the highest-value
fix from the review since it closes a real unattended-session false-positive.

**Green run (fix in place):**

```
Command: bats tests/test-queue.bats
Exit: 0
Verdict: PASS
1..14
ok 1 T1 happy: RUNNER_DONE -> done, window opened and killed
...
ok 13 NC6 marker-wrap-false-positive: a wrapped echo fragment never triggers done
ok 14 NC7 stalled-twice-stops-night: 2 consecutive stalls stop the night, later rows untouched
```

**Revert** (`_scan_marker` reverted in-place to the pre-review line-anchor-only form, no
blank-line guard):

```bash
python3 - <<'PY'
p = "lib/queue/queue.sh"
s = open(p).read()
old = '''_scan_marker() {  # transcript-on-stdin
  awk \\'
    /^[[:space:]]*RUNNER_DONE[[:space:]]*$/ && (NR==1 || prevblank) { print "done"; exit }
    /^[[:space:]]*RUNNER_GATED:/ && (NR==1 || prevblank) {
      r=$0; sub(/^[[:space:]]*RUNNER_GATED:[[:space:]]*/,"",r); print "gated:" r; exit
    }
    { prevblank = ($0 ~ /^[[:space:]]*$/) }
  \\'
}'''
new = '''_scan_marker() {  # REVERTED for negative control -- no blank-line guard
  awk \\'
    /^[[:space:]]*RUNNER_DONE[[:space:]]*$/ { print "done"; exit }
    /^[[:space:]]*RUNNER_GATED:/ { r=$0; sub(/^[[:space:]]*RUNNER_GATED:[[:space:]]*/,"",r); print "gated:" r; exit }
  \\'
}'''
open(p, "w").write(s.replace(old, new))
PY
```

**RED (fix reverted):**

```
Command: bats tests/test-queue.bats
Exit: 1
Verdict: FAIL
not ok 13 NC6 marker-wrap-false-positive: a wrapped echo fragment never triggers done
# (in test file tests/test-queue.bats, line 250)
#   `[ "$(jverdict wrap1)" = "stalled" ]            # NOT done -- the wrap fragment is rejected' failed
```

NC6 is the ONLY case that goes red on this exact revert (T1/T2/NC2's single-line transcripts are
`NR==1`, so they still pass under the reverted anchor) -- proof that NC6 targets precisely the
blank-line guard and would have caught the CRITICAL finding had it existed before the review.

**Restore:**

```bash
git checkout -- lib/queue/queue.sh   # (done here via a clean re-write from the pre-revert copy)
```

**Green again (restored):**

```
Command: bats tests/test-queue.bats
Exit: 0
Verdict: PASS
1..14
... (all 14 ok, identical to the first green run)
git diff --stat lib/queue/queue.sh   # empty -- byte-identical to the committed state
```

## Reproduce

```
cd <this repo>
bats tests/test-queue.bats
shellcheck -x lib/queue/queue.sh
bash lib/gate/coverage-delta.sh check . master --rid orchestrate-queue
bash tests/test-meta.sh; bash tests/test-orchestrate.sh   # kit regression
# live smoke + red-team: see the blocks above (throwaway mktemp repos + pointers only)
# negative control: see the revert -> RED -> restore block above
```
