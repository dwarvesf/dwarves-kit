# Implementation notes: overnight queue launcher (SPEC-146)

Delta from the spec only (not a mirror). Reference SPEC-146 for the design.

## 2026-07-05 12:00 marker anchor relaxed after the live smoke

Context: the spec pinned a STRICT line anchor `^RUNNER_DONE$`.
Decision: relaxed to `^[[:space:]]*RUNNER_DONE[[:space:]]*$` (marker is the only non-space token
on its line).
Why: the live tmux smoke proved the real Claude Code TUI renders the assistant's final line
INDENTED inside its message block, so the strict anchor MISSED the real pane and the launcher
would have stalled every real run. The relaxed anchor still rejects mid-prose (`end with the line
RUNNER_DONE`), so NC2 still holds.
Alternatives: strip pane indentation before matching (more fragile across mux/TUI versions).
Impact: T1/T2 fixtures updated to the indented rendering to lock the regression.

## 2026-07-05 12:10 readiness-wait + verify-and-resubmit added (not in spec)

Context: the spec's state machine went open -> type `/goal` + Enter -> poll.
Decision: inserted `_mux_wait_ready` (poll for the TUI footer/prompt before typing) and split the
Enter into `_mux_submit` (send Enter, verify the prompt actually cleared, re-issue up to 5x).
Why: the first live smoke hung , the `/goal` text was typed but the Enter fired before the TUI was
input-ready and was DROPPED (text sat unsent on the prompt). A manual Enter then submitted it,
confirming the mechanism. This is a real TUI-automation hazard, not covered by the spec.
Alternatives: a fixed startup sleep (pure guess; brittle across machines). The readiness poll +
resubmit is deterministic-ish and self-correcting.
Impact: new CONSUMER config `QUEUE_STARTUP_SECS` (20) + `QUEUE_SUBMIT_SETTLE_SECS` (2); tests set
both to 0. An extra Enter on an empty prompt is a harmless no-op.

## 2026-07-05 12:20 error-twice reconciliation (design-doc ambiguity)

Context: the runner-fastpath design doc says "two consecutive failed/gated megas ... STOPS THE
NIGHT" in one place but its own risks table says a gated mega just "records and moves on", and NC3
tests `error`.
Decision: only `error` accrues toward the night-stop; `gated`/`stalled` are per-pointer stops that
MOVE ON and RESET the counter; a `skipped` row is a pass-through (neither increments nor resets).
Why: matches the rate-limit rationale ("assume account-level rate limit"), the risks table, and
NC3. Documented in SPEC-146 `## Design` and proven fail-closed in the rung-4 red-team (RT-b2: a
skip between two errors still stops).
Impact: the consecutive-error semantics are the counter's whole contract; see NC3 + RT-b1/b2/b3.

## 2026-07-05 12:25 sibling lib, not an orchestrate.sh internal

Context: the sub-goal allowed either an `orchestrate.sh queue` subcommand or a sibling `lib/queue.sh`.
Decision: logic lives in `lib/queue.sh`; `orchestrate.sh` gets a one-line `queue) exec queue.sh
run "$@"` alias.
Why: orchestrate.sh is 1783 lines with 70+ pinned tests driving a DIFFERENT mechanism (headless
`claude -p` per sub-goal). The interactive-`/goal` launcher is a distinct mechanism; a sibling
keeps its tests isolated and orchestrate.sh's suite untouched, while still exposing the documented
`orchestrate.sh queue` entry point.
Impact: `tests/test-queue.bats` is standalone; no orchestrate.sh test changed.

## No further deviations

Everything else matches SPEC-146 verbatim: queue-row contract (`slug<TAB>repo<TAB>pointer`),
journal columns, preflight, `--dry-run`/`--max-megas`/`--from-boards`, CONSUMER config keys.

## 2026-07-05 13:00 multi-lens review found two CRITICAL + several lower findings, all fixed

Context: per SPEC-069 ("a run touching `lib/` or `hooks/` uses `/kit:review-team`, not a single
reviewer"), dispatched a security-reviewer + code-reviewer in parallel before push.
Findings and fixes (full detail in SPEC-146's AMENDMENT section, not restated here):

1. **cmux dropped (architecture HIGH).** I had invented `cmux` verbs (`new-window --name --cwd --
   cmd`) without CLI-verifying them. The reviewer cited this repo's OWN prior findings
   (`SPEC-119` DEC-001, `SPEC-121` DEC-004) that cmux has no such argv-safe launch primitive.
   Decision: drop cmux entirely, `TERMINAL_MUX=tmux` only, reject other values loudly.
   Why: shipping an unverified mechanism against a skip-permissions session is worse than not
   having the option; a documented follow-up beats a silent lie.

2. **Marker false-positive from the wrapped `/goal` echo (security CRITICAL).** The pointer
   content is DESIGNED to instruct printing `RUNNER_DONE` (that's the whole contract), and
   `_goal_line` flattens it to one long line that a real terminal will soft-wrap. The reviewer
   showed this can isolate the marker substring on its own rendered row with no real completion
   having happened. Decision: require the marker line be first-line-or-blank-line-preceded, based
   on the REAL smoke capture's confirmed rendering (blank-flanked). Alternatives considered:
   scanning only the tail of the pane (unreliable, scroll-position-dependent); requiring a
   post-submit "echo cleared" gate before starting to scan (more complex, same root fix). Impact:
   NC6 locks the regression.

3. **Missing allow-list defense-in-depth (security CRITICAL).** The sub-goal contract explicitly
   delegates path allow-listing to sub-goal 04 ("you don't need to build that allow-list
   yourself"). The reviewer's point, which I agree with: this launcher is the LAST line of
   defense before an unattended skip-permissions session, and trusting an upstream tool with zero
   local verification is the wrong posture for that trust level. Decision: add
   `_pointer_allowlist_reason`, applied ONLY to `--from-boards` rows (hand-authored tsv stays
   exempt, since operator authorship IS the trust boundary there). First cut used `cd
   $(dirname)&&pwd -P` (resolves the directory only); a follow-up red-team probe found a symlink
   planted INSIDE the allowed dir but pointing outside the repo would slip past that, so switched
   to `realpath` (resolves the full symlink chain; present on macOS+Linux, verified on this host).
   Impact: T5/T6/T7 lock this; this does NOT replace sub-goal 04's own allow-list, it is a second
   independent check (defense-in-depth, not delegation-only).

4. **`stalled` folded into the consecutive-failure stop (MEDIUM, both reviewers flagged
   variants).** Originally only `error` (launch failed twice) counted toward the 2-consecutive
   night-stop; `stalled` (no progress for the full timeout) reset it. The reviewer's point: a
   hang is just as much "the mechanism is dysfunctional" as a crash, and repeated stalls would
   silently burn a whole night. Decision: `error`+`stalled` share one `consec_fail` counter;
   `done`/`gated` still reset (legitimate per-mega terminal states); `skipped` stays a
   pass-through. Impact: NC7 added; the rung-4 red-team's RT-b family re-verified with `stalled`
   substituted for `error` behaves identically.

5. **Journal reason tab-stripped (MEDIUM).** A `gated:` reason is pane text (not
   operator-authored); `_journal_append` now strips `\t`/`\r`/`\n` before writing so it can never
   shift the row's column count for any tool parsing the journal by field position.

6. **Slug target-separator validation (LOW).** `_slug_ok` rejects `:`/`.` in a slug before any
   mux verb runs (tmux's own `session:window`/`window.pane` separators).

Not changed (reviewed and accepted): the resubmit-loop's OWN retry path is still not directly
exercised by a bats case (only the live smoke proves it); given the marker-anchor and allow-list
fixes were the load-bearing security gaps, this was deprioritized as documented residual risk
rather than blocking further on it.
