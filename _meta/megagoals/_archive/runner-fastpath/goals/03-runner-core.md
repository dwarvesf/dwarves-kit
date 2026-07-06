# Sub-goal 03: runner-core

**Merge policy:** auto
**Time budget:** 2-4 hours of loop work
**Proof:** OVER-TEST: test-plan + run-table (full `go test ./...` output) + the five named negative controls each with its own test + ONE recorded live smoke (real `claude -p --model haiku` against a throwaway git repo fixture) + a `check` and `report` demo + COVERAGE-DELTA row
**Design:** bearing (new component; the loop's state machine and the marker contract are the heart of the mega). The spec MUST carry a `## Design` block: the iteration state machine diagram + the contract table from the design doc.
**Depends on:** none (ops lane head)
Model: sonnet
**Branch:** `feat/mega-runner-core`
**PR base:** main

## Outcome

`tools/mega-runner/` exists: a Go binary `mega-runner` that reads a queue of pointer prompts and executes each sequentially as a headless `claude -p` resume-loop, ending each row with a verdict (done / gated / stalled / max-iter / skipped / error) in a journal. It is the overnight drain for queued mega-goals; all intelligence stays in the pointer contracts.

## Quality bar

The runner is dumb on purpose. It never parses roadmaps, never merges, never writes to any repo; git use is read-only + `pull --ff-only`. Every exit path lands a journal row (no silent verdicts). No secrets touched; no queue-row text ever passes through a shell (exec with arg vectors, never `sh -c`).

## Binding contract (from research/2026-07-04-mega-runner-fastpath-design.md, do not re-litigate)

- STEP 0, before coding the parser: verify the headless interface ONCE with a real call (`claude -p 'say ok' --model haiku --output-format json`) and confirm the field names this contract assumes (`session_id`, `result`, `total_cost_usd`, snake_case). Save that captured JSON as a `testdata/` golden fixture so a future CLI output-format change fails `go test` instead of a 2am night. Record the observed shape in the spec.
- Queue: `queue.tsv` rows `slug<TAB>repo-path<TAB>pointer-path` (`#` comments, `~` expands). Pointer path resolves relative to the repo, then absolute.
- Wrap the pointer with the RUNNER CONTRACT: unattended, never ask; on full completion end the final message with a line exactly `RUNNER_DONE`; on a genuine STOP finish checkpoint bookkeeping FIRST then end with `RUNNER_GATED: <one-line reason>`; never emit either prematurely.
- Markers are LINE-ANCHORED (`^RUNNER_DONE\s*$`, `^RUNNER_GATED:`): quoted contract text mid-prose must not trigger.
- Per row: skip (journal `skipped` + reason) unless repo exists, tree is CLEAN, checkout is on the repo's default branch; then `git pull --ff-only` (warn-and-continue on failure).
- First call: `claude -p "<wrapped pointer>" --dangerously-skip-permissions --output-format json`, cwd = the repo, stdin = /dev/null. Parse `session_id`, `result`, `total_cost_usd`. Iterations 2..N: `claude -p --resume <session_id> "<continue nudge>"` same flags.
- Caps and knobs (flags with env fallbacks): max iterations default 12; per-iteration timeout default 2h; optional model override; retry sleep default 30min.
- Stall: hash(all local branch tips via `for-each-ref` + result text) unchanged for 2 consecutive iterations -> verdict `stalled`, next row.
- Errors: nonzero exit -> sleep, retry once; a second consecutive failure -> verdict `error` AND STOP THE WHOLE NIGHT (assume account-level rate limit).
- Journal `runs/journal.tsv`: ts, slug, verdict, iterations, cost-usd, reason. A row already `done` in the journal is skipped on re-run (idempotent nights). Per-row full text -> `runs/<date>-<slug>.log`. `runs/` is gitignored.
- `RUNNER_CLAUDE_BIN` overrides the claude binary: the test suite injects a stub emitting canned JSON; NO real API calls in `go test`.
- `mega-runner check`: validate every queue row WITHOUT dispatching (repo exists/clean/on-default-branch, pointer resolves, claude binary on PATH); the pre-night sanity command the runbook tells Han to run.
- `mega-runner report`: render the journal since the last run start as the morning digest (verdict counts, per-row verdict + iterations + cost, total cost, held/gated reasons). A formatter over journal.tsv, nothing more.
- `--max-cost-usd <n>` (default off): sum journal cost this run; at the ceiling, stop dispatching further rows (verdict `budget` for the remainder).
- `runs/.lock` with the PID at startup: a second concurrent start against the same runs/ dir refuses with a clear message (stale-PID check, then overwrite).

## How to close the loop

Tool scaffold per ops-tool-shape (README, tool.toml, .gitignore extending root for `runs/`, MANIFEST.md row) + co-located `tools/mega-runner/docs/proof-of-done.md` in the table-first format. The README states explicitly that the queue takes ANY pointer prompt, single-goal pointers included, not only megas (the contract is pointer-agnostic; that generality is free, say it so nobody mentally scopes the tool). Kit-adopted repo: record gate-ledger phases before push.

Named negative controls (each a test):
1. Dirty tree -> row skipped with reason, claude never invoked (stub records zero calls).
2. A result whose PROSE quotes "RUNNER_GATED:" but whose lines contain no anchored marker -> loop continues (no false gate).
3. Stub fails twice -> verdict `error`, queue processing stops (later rows untouched).
4. Journal has `slug done` -> row skipped; the stub records zero calls (idempotence).
5. A slug/repo-path/pointer-path containing shell metacharacters (`;`, backtick, `$( )`) reaches the stub as ONE untouched argv element; no shell ever interprets queue text (this is the test behind the "never passes through a shell" absolute).

Live smoke (recorded in proof-of-done): a throwaway git repo fixture + a 3-line pointer ("report HEAD, write nothing, end per contract"), run with the REAL claude at `--model haiku`; journal shows `done` in 1 iteration.

**Done =** `go test ./...` green with the five NCs present AND the live-smoke journal row captured in proof-of-done AND `check`/`report` each demonstrated once in the run-table.

Record the gates (REQUIRED): `rid=$(bash lib/gate-ledger.sh rid)` then `record` per phase, before the push.

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. Overwrite HANDOFF.md: next = 04 (board-queue) stacked on this branch; first action = read the queue-source seam in cmd/ (name the file:line where QueueSource is consumed).
3. Append to DECISIONS.md: the final flag/env table, the stall-hash definition, any contract deviations (there should be none without a reason).
4. Report IN the records, then EXIT IMMEDIATELY.

## Scope edges

**In:** `tools/mega-runner/` (Go module, cmd + internal), its docs, MANIFEST/tool.toml rows.
**Out:** board parsing (04), the observatory (05), deployment/runbook (06), any launchd plist.
**Not:** a daemon mode, a web UI, parallel rows, cross-mega file-conflict detection (queue discipline + each mega's own guard handle that; the merge-queue idea stays in the portfolio research note).

## Where to look

Design source section 2 (binding). Go conventions: `tools/` has Go precedents; build with the mise-pinned Go, not brew's (known GOROOT mismatch gotcha). The headless-interface verify is STEP 0 of the binding contract above, not optional reading.

## PR body

- Outcome: `tools/mega-runner` Go runner: sequential overnight queue of pointer prompts, marker contract, journal verdicts.
- Verification: `go test ./...` run-table + four NCs + live haiku smoke journal row (inline).
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`.

## Notes

