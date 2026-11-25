# Specs, board and intake: rules, proofs, bridges, findings

Area: `lib/spec/`, `lib/board/`, `lib/intake/intake.sh`, `lib/classify/` (lane, route-suggest, significance,
task-type), `lib/ledger/ledger.sh`, `lib/precedent/precedent.sh`. Each rule is written with gdp-wired's native API
from what the code does; file:function is cited at the top of each `<name>.ts`. Laws are the ones the docs promise
plus the ones a reviewer would ask.

`node lib/rules/specs/prove.ts`:

- proves every rule (step laws from any state; `proven && checked && !assumes`; decisions via `proveDecision`);
- refuses every kept broken variant;
- refutes every finding law (a promise the code knowingly does not keep);
- runs every bridge: the real bash on generated inputs in temp dirs, against `rule.compiled()` / `fun.run()`;
- replays every finding's counterexample on the real bash.

`--no-bridges` runs only the proofs (about 6 s). Seeds are fixed, so counts match across hosts. Supercomputer batches
`20261125-121745-aoml1g` and `20261125-122146-tuhxrq` passed (Linux, node 22, jq 1.8.1), as did macOS locally.

## Rules

| Rule | Source | Laws | Proven | Variants refused | Findings | Bridge |
|---|---|---|---|---|---|---|
| spec-status | lib/spec/spec-status.sh:_set,_read | 8 step | yes, any state | silent-reopen, writes-alias, touches-headerless, same-state-notice | 2 (by design) | 288 agree |
| spec-task-done | lib/spec/spec-task-done.sh:main | 7 step | yes, any state | log-after-flip (pre-fix), flips-duplicates, reflips-checked | 1 | 218 agree (after fix) |
| spec-next | lib/spec/spec-next.sh:next,reserve,_reservations | 1 law + 5 step | yes, any state | ignores-reservations, reserve-unrecorded | 1 (by design) | 146 agree |
| spec-active | lib/spec/spec-active.sh:spec_active; spec-find.sh:spec_for_slug | 8 decisions (1 two-run) | yes | live-ignores-status, ambiguous-picks-first | 1 (pinned) | 214 agree |
| spec-depth | lib/spec/spec-depth.sh:cmd_size,cmd_check,parse | 10 decisions | yes | malformed-is-standard (pre-fix), date-only, standard-mixes | - | 201 agree (after fix) |
| board-set | lib/board/backlog.sh:set_state | 9 step | yes, any state | silent-reopen, writes-duplicates, no-back-notice | 1 | 200 agree |
| board-dedupe | lib/board/backlog.sh:dedupe,dedupe_all | 6 decisions | yes | dedupe-keeps-first, all-keeps-last | 2 (documented) | 141 agree |
| board-queue | lib/board/parse-board.sh:pb_queue_rows | 7 decisions | yes | trusts-repo, no-containment, emits-dangling | - | 160 agree |
| board-run | lib/board/board-run.sh:main,_write_once | 1 law + 8 step | yes, any state | overwrites, refuses-terminal, writes-on-bad-row | - | 47 agree |
| board-work | lib/board/work.sh:JOIN (rung_of, agent_of, rec) | 10 decisions (1 two-run) | yes | parks-unknown, rung-lowest-first, parks-shipped-row | - | 45 agree (jq 1.7 fixed, B1) |
| state-check | lib/board/state_check.py:move_problem | 6 decisions | yes | case-sensitive-transitions (pre-fix), checks-from-legacy, accepts-legacy | - | 400 agree (after fix) |
| intake-gate | lib/intake/intake.sh:cmd_gate,_row_kind | 6 decisions (1 two-run) | yes | substring-eval (pre-fix), skip-hits, skim-first-ignored | - | 64 agree (after fix) |
| lane-classify | lib/classify/lane-classify.sh:classify_core,lane_check,escalate | 10 decisions | yes | words-pick-full, hard-beats-tiny, escalate-lowers | 1 (documented) | 105 cases x 4 verbs agree |
| significance | lib/classify/significance-classify.sh:classify_core | 6 decisions (2 two-run) | yes | taps-on-worth-alone, knob-inverted | - | 90 agree |
| task-type | lib/classify/task-type-classify.sh:task_type_classify | 7 decisions | yes | doc-before-research, tool-before-migration, no-absorb-guard | - | 165 agree |
| route-suggest | lib/classify/route-suggest.sh:tier_of,main | 6 decisions | yes | unknown-is-a-tier (pre-fix), suggests-on-one, last-wins-ties | - | 120 agree (after fix) |
| ledger-append | lib/ledger/ledger.sh:ledger_append | 6 step | yes, any state | joins-torn-line, escapes-root, pre-fix | - | 159 agree (after fix) |

Totals: 17 rules, 127 laws proven and checked; 50 variants refused; 9 finding laws refuted, all reproduced on the real bash.

## Fixes

- **F1 spec-task-done.** Laws: "a refused call changes neither the spec nor the verification log"; "a checked-off task
  with `--verify-log` always gets exactly one log entry". Counterexample: `--verify-log blocker/v.md` with `blocker` a
  regular file gave exit 1, the task flipped to `(DONE, commit …, verified)`, and no entry. Fix: `mkdir -p` and a
  writability check before the `mv`. Bridge: diverged after 44 before; 218/218 after. Test: `test-spec-task-done.sh`
  "a --verify-log that cannot be written errors before the spec moves".
- **F2 spec-depth.** Law: "a Depth line that is present but names no valid level is never small". Counterexample:
  `Lane: normal`, `Depth: research (the lock order)`, 2 tasks gave `size` small, so `ship-rules` skipped validation.
  Fix: a present line with no valid level reads `invalid`. Bridge: diverged after 36; 201/201 after. Tests:
  `test-spec-depth.sh` cases badres and badlvl.
- **F3 intake.** Laws: "a row is labelled eval only when it records an evaluation"; "a skim row cannot close an eval".
  Counterexample: notes `skim of the retrieval paper` gave row_kind eval. Fix: `eval` must be a word. Bridge: diverged
  after 8; 64/64 after. Test: fixture row FX-003 in `test-intake.sh`.
- **F4 route-suggest.** Laws: "a suggestion names a tier the orchestrator allowlist accepts"; "a suggestion needs two
  allowlisted tiers". Counterexample: PASS rows `fable-5` and `gpt-5` gave a suggestion on single-tier data and could
  print `model=gpt-5`. Fix: unknown models are skipped; `declare -A MIN=()` fixes the `set -u` crash that made reachable.
  Bridge: diverged after 3; 120/120 after. Test: three assertions in `test-routing.sh`.
- **F5 ledger, torn line.** Law: "an append never changes a record already written". Counterexample:
  `printf 'torn | GATE | half' >> runs/r.log; ledger append runs/r.log x` gave `torn | GATE | halfx`. Fix: end a torn
  last line first.
- **F6 ledger, `..` stream.** Law: "nothing is ever written outside the ledger root". Counterexample:
  `ledger append ../escape.log x` wrote outside the root. Fix: refuse a stream with a `..` part (exit 64). Bridge for
  F5 and F6: diverged after 5; 159/159 after. Tests: three assertions in `test-ledger-substrate.sh`.
- **F7 state_check.** Law: "a declared transition is never refused, whatever the case". Counterexample: `ignore_case`,
  states [A,B,C], `{A=[B]}`, A→B was refused as undeclared. Fix: fold the transitions lookup like `classify()`.
  Bridge: diverged after 40; 400/400 after. Test: `case_ignore_case_transition_spelling`, mutation `transition-fold`.
- **B1 work.sh on jq 1.7** (fixed by the lead): `($bi | ...) + $mi as $named` parses on jq 1.7 as
  `+ ($mi as $named | rest)`, so `board work` exited 1 on stock Debian/Ubuntu jq. Parenthesized; identical on jq 1.8.
  `test-board-work.sh` 113/113 (its `--help | grep -q` assertion was also SIGPIPE-flaky under pipefail; fixed).

## Unfixed findings (promises the code knowingly does not keep)

| # | Law refuted | Reproduced counterexample | Why not fixed |
|---|---|---|---|
| U1 | a spec becomes SHIPPED only from APPROVED/VALIDATED | `Status: DRAFT`; `spec-status.sh set s.md SHIPPED` exits 0, silent | by design: `next` is advisory ("Detect, don't dictate") |
| U2 | a move off the next path is announced (spec) | VALIDATED→DRAFT is silent | the decision brief promises it; a decision for the brief's owner |
| U3 | a move off the next path is announced (board) | `backlog.sh set BK-1 shipped` from queued is silent | no `next` column lists parked or dropped, so the notice would fire on every park and drop |
| U4 | dedupe never drops a flipped copy; dedupe and dedupe-all agree | [claimed, queued]: dedupe keeps queued, dedupe-all keeps claimed | documented ("else the last occurrence"), but `board set` says "dedupe first" |
| U5 | the name pick is the exact-slug spec | SPEC-001-ship-gate.md + SPEC-002-gate.md, `--branch feat/gate` picks ship-gate | the root glob is pinned by `test-spec-find` row 3; the ship gate and validate-round use this pick |
| U6 | a reserved number is never handed out twice | reserve; age past TTL; reserve gives 001 twice | by design (TTL) |
| U7 | `verified` only with a PASS log entry | no `--verify-log`, or `--verdict FAIL`, both give `(…, verified)` | CLI contract; execute.md trusts the caller |
| U8 | a hard path in `--files` makes the risk full | `risk --files db/migrations/001.sql 'fix typo in the migration'` gives tiny | documented precedence; `floor` covers it at ship |

## Found while bridging

- **B2.** Partial copies of the active-state vocabulary in `board.sh` (`_priority_render`, `_priority_matrix`) and
  `work.sh` pass the `test-board-states` detector, which only flags a line naming every active state.
- **B3 (fixed by the lead).** `precedent.sh` said it keeps "the 8 most specific" keywords but `sort -u | head -8` kept
  the first 8 alphabetically. It now keeps the 8 longest (ties alphabetical) and still emits them alphabetically.
  Test: `test-precedent.sh` "_keywords keeps the 8 longest keywords" (83/83; `test-precedent-index.sh` 59/59).

## Not modelled

- The spec-next mkdir lock and stale-reclaim (concurrency).
- The open-PR `gh` scan (network).
- The row-id mint in `board_add.py`.
- The board sync, publish, capture, promote and init verbs (engines outside this area).
- lane-classify `floor` and `deescalate` (diff-driven regex grammar).
- The classifiers' regexes themselves (each regex's verdict is a rule input).
- Precedent ranking; read-only projections (spec-index, backlog get/row/lint, board-lib); `role-classify.sh`.
