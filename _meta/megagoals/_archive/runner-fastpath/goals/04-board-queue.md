# Sub-goal 04: board-tool (in the kit)

**Merge policy:** auto
**Time budget:** 3-5 hours
**Proof:** OVER-TEST: test-plan + run-table (`board queue` bats asserts + render output) + five named negative controls (honest-empty, unregistered repo, out-of-tree/`..`-traversal pointer, shell-metachar argv, RENDER non-regression byte-identical across every registered repo) + one live `board queue --dry-run` against the cockpit + COVERAGE-DELTA row + the rung-4 captured `VERDICT: SECURE`
**Design:** bearing (the kit's board command is born here; the queue token grammar is an interface other sessions write to; a render regression breaks Han's daily cockpit)
**Repo:** dwarves-kit (the `board` command joins the kit, per "ship the harness suite together"; hand-made worktree from `master`).
**Depends on:** none for the tool itself; agree the `queue` row format (`slug<TAB>repo-path<TAB>pointer-path`) with 03K up front so they compose.
Model: sonnet
**Branch:** `feat/board-tool` (dwarves-kit)
**PR base:** master

## Outcome

`dwarves-kit` gains the `board` command (bash, GENERIC + config-driven; follow the `lib/backlog.sh` precedent, e.g. `lib/board.sh` + a `bin/board` entry per kit convention). It becomes the SOLE cockpit board command: it ABSORBS the render logic from ops-toolkit `_meta/board` (the `priority` quadrant awk) and `_meta/board-all` (the `boards.txt` registry walk + `priority matrix` pivot), and ADDS a `queue` subcommand that emits the overnight queue 03K consumes. The ops-toolkit `_meta/board` + `_meta/board-all` shrink to ONE-LINE shims that `exec` the kit `board` with the CONSUMER config. Base kanban render still delegates to `backlog.sh` (kit-native).

## Quality bar

Bash, in the kit, GENERIC: NO personal data committed to dwarves-kit. The personal registry (`boards.txt`), bridge opt-ins, and Hermes target are CONSUMER config the kit `board` reads at runtime via `CONSUMER_ROOT`/env (the kit's existing consumer pattern). **The render migration changes NO output: `board`/`next`/`priority [mode|matrix]`/`states` are BYTE-IDENTICAL to today's ops-toolkit `_meta/board`/`_meta/board-all` for every registered repo (the load-bearing non-regression NC).** Do NOT reimplement `backlog.sh` (delegate base render). `queue` parses via `lib/parse-board.sh` (the one structured parser, reused by 07/08). ALLOW-LIST (load-bearing security): a queue token's `repo-path` MUST be in the consumer `boards.txt`; `pointer-path` MUST resolve inside `_meta/megagoals/**` or `.claude/goals/**`; else skipped with a logged reason. Honest-empty. Queue text NEVER passes through a shell (argv-exec); a hand-authored tsv is allow-list-exempt.

## How to close the loop

- Build the kit `board` command per kit convention (`lib/board.sh` + `bin/board`, or extend the existing dispatch), + `lib/parse-board.sh`. Kit-adopted: read AGENTS.md + WORKFLOW.md, lane-classify, record gate-ledger phases before push.
- MIGRATE render: move the `priority` quadrant awk + the `boards.txt` registry walk + `priority matrix` pivot from ops-toolkit `_meta/board`+`_meta/board-all` into the kit `board` (`board`/`all`/`next`/`priority [mode|matrix]`/`set`/`states`), delegating base render to `backlog.sh` via `BACKLOG_FILE`. The registry path + repo list come from CONSUMER config, not hardcoded.
- SHIM the ops-toolkit entry points: `_meta/board` -> one-line `exec` of the kit `board` with `CONSUMER_ROOT` set to ops-toolkit; `_meta/board-all` -> `exec` of the kit `board all`. (This shim edit lands in the ops-toolkit consumer, cross-repo; do it in the same PR family or a paired ops-toolkit commit noted in the PR body.)
- ADD `board queue [--dry-run]`: walk the consumer `boards.txt`, parse each BACKLOG.md via `lib/parse-board.sh`, filter `queued` + runner token, apply the allow-list, emit `slug<TAB>repo-path<TAB>pointer-path`. This is what 03K consumes (03K also accepts a tsv).
- Tests (bats): fixture BACKLOG.md (valid token; malformed skipped; non-queued+token ignored). NCs: (a) zero tokens -> empty, exit 0, "0 rows"; (b) repo not in boards.txt -> skipped w/ reason; (c) pointer outside allow-listed dirs incl `../` -> skipped; (d) shell-metachar field -> ONE argv element; (e) RENDER NON-REGRESSION: capture the ops-toolkit `_meta/board`+`_meta/board-all` output for `board`/`next`/`priority [overview|matrix]`/`states` across EVERY registered repo BEFORE, assert the kit `board` (via the shims) is byte-identical AFTER.
- Live: `board queue --dry-run` against the real cockpit (READ-ONLY), captured in proof-of-done.

**Done =** bats green incl. all five NCs (esp. byte-identical render) AND the live `--dry-run` AND the rung-4 `VERDICT: SECURE`.

**Rung 4 (INJECTION SURFACE):** a free-text Notes cell feeds an unattended runner (03K), so an in-harness `kit:security-reviewer` tries to break the allow-list + argv-safety of `board queue`. Frozen diff `git diff master...HEAD`; fail-closed; cap 3; record `redteam` rows.

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. HANDOFF: next = 07 (`board mirror`) on this kit tool; first action = read `lib/parse-board.sh` + the `queue` emit (file:line).
3. DECISIONS: the token grammar, the `lib/parse-board.sh` interface, the CONSUMER config keys (`boards.txt` path, Hermes target var), the shim shape, the `boards.txt` `bridge` column 07 adds.
4. Report IN the records, EXIT.

## Scope edges

**In:** the kit `board` command (render migrated + `queue` + `lib/parse-board.sh`), the ops-toolkit `_meta` shims (cross-repo, noted), docs, fixtures, proof.
**Out:** `mirror`/`writeback` (07/08), `backlog.sh` (delegated, untouched), the OTHER repos' `board` wrappers, 03K's queue loop.
**Not:** reimplementing `backlog.sh`, a Go anything, committing personal data to the kit, changing render OUTPUT.

## Where to look

ops-toolkit `_meta/board` + `_meta/board-all` (the logic to migrate; read first), `_meta/boards.txt` (registry -> becomes consumer config), dwarves-kit `lib/backlog.sh` (delegated render + states), the kit's CONSUMER_ROOT/env pattern, the runner/bridge design docs + their 2026-07-05 amendments.

## PR body

- Outcome: the kit `board` command (render migrated out of ops-toolkit `_meta`, now shims) + `board queue` feeding 03K; generic + config-driven, personal data stays consumer-side.
- Verification: byte-identical render non-regression + `queue` run-table + 5 NCs + live `--dry-run` + `VERDICT: SECURE`.
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`.

## Notes
