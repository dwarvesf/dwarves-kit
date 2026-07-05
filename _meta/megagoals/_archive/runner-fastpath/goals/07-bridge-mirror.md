# Sub-goal 07: bridge-mirror

**Merge policy:** auto
**Time budget:** 2-4 hours after 04 merges
**Proof:** OVER-TEST: test-plan + run-table (full test output) + six named negative controls + a dev-home E2E capture RUN TWICE (second run's plan is EMPTY, proving idempotence live) + a `board status` demo + COVERAGE-DELTA row. The live-Mini mirror is NOT this sub-goal's leg; it runs ONCE at the convergence-gate demo (advisor P5: an `auto` sub-goal must not mutate the live personal Hermes).
**Design:** bearing (the normalized-row schema, the git<->Hermes STATE MAPPING table, and the snapshot format are interfaces 08 builds on). The spec MUST carry a `## Design` block: the ETL flow + the row_hash definition + the state-mapping table.
**Repo:** dwarves-kit (extends the kit `board` command from 04; hand-made worktree from `master`).
**Depends on:** 04 MERGED (the kit `board` tool + `lib/parse-board.sh` + the consumer `boards.txt` shape). Base master.
Model: sonnet
**Branch:** `feat/board-mirror` (dwarves-kit)
**PR base:** master
**Config seam:** the Hermes target (host/board names) + the opted-in repo list are CONSUMER config read at runtime (`CONSUMER_ROOT`/env); NO personal Hermes host or repo list committed to dwarves-kit.

## Outcome

the kit `board` tool (the SAME bash tool 04 created) gains a `mirror` subcommand: it projects the opt-in cockpit boards plus one card per active mega-goal onto a Hermes agent's native kanban, idempotently (a second run with no changes performs zero Hermes operations), plus a `status` subcommand reporting mirror staleness. Proven end-to-end against the hermes-fleet dev-home; the live personal `mini.hermes` gets its first mirror at the convergence demo.

## Quality bar

BASH, no Python/DuckDB (the diff is a keyed comparison over dozens of rows via bash + `jq`, not an analytics engine; DuckDB stays only in `ledger-observatory`). Native-first absolutely: EVERY Hermes access, reads AND writes, goes through `hermes kanban` CLI verbs (`list --json` for reads); NO SQLite ATTACH, NO direct DB. Privacy: only repos opted in via a new `bridge` column in `_meta/boards.txt` are mirrored; `trading` and `family-office` stay OFF; seed the opt-in with `ops-toolkit` + `dwarves-kit` only. Honest-empty everywhere. Reuse 04's board-parse helper (one parser).

## Binding contract (from research/2026-07-04-board-hermes-bridge-design.md + its 2026-07-05 amendment; do not re-litigate)

- STEP 0: re-run the `experiments/hermes-fleet` smoke against the CURRENTLY INSTALLED hermes version (verb flags are version-sensitive); probe the card-body length limit; `ssh mini-tieubao hermes kanban boards list` to check name collisions with the planned board names. Record all three in the spec + DECISIONS.md. Develop against the hermes-fleet dev-home (`deploy/setup-dev-home.sh`, throwaway `HERMES_HOME`, never `~/.hermes`).
- Stack: bash + `jq`. Match the DISCIPLINE of the kit's other tools (tests, proof-of-done), not any Go structure.
- Extract: reuse 04's board-parse helper over the opted-in BACKLOG.md kanbans (`[A-Z]+-[0-9]+` IDs); add the `bridge` opt-in column to `_meta/boards.txt` (document it in the file's own header comment; do NOT break `_meta/board-all` or 04's `queue`); EXCLUDE rows in `shipped`/`dropped`; render one row per ACTIVE mega-goal (progress = flipped-box count + held-PR flags).
- STATE MAPPING is a pinned table in the spec's Design block: git states (queued/claimed/speccing/validated/executing/shipped/parked/dropped) -> Hermes native states (triage/todo/ready/running/blocked/done); Hermes has NO delete verb, so a row that disappears from git flips its card to `done` with an `origin removed` note, never silently orphaned.
- Transform: normalized rows (repo, id, item, notes, status, origin, row_hash, seen_at); diff = a keyed full comparison vs `hermes kanban list --json` (bash + jq), producing an idempotent upsert plan.
- Load: `hermes kanban` verbs only; one board per opted-in repo + one `megagoals` board; cards carry `origin=` back-pointers; mega cards carry a visible `synced: <ISO ts>` line. The mirror SNAPSHOT (rows + hashes, 08's conflict-rule input) is persisted INCREMENTALLY, per successfully-loaded row, so a mid-sync failure never leaves the snapshot claiming un-applied state; a re-run heals the remainder via idempotence.
- Remote execution (used by the convergence demo; build it here): the load plan for a remote target ships as a JSON plan file + a tiny applier invoked over ONE `ssh mini-tieubao` call; the applier execs argv vectors. Card text NEVER gets templated into a shell string (the no-shell absolute applies to card text exactly as to queue text). Record the measured wall time of the batched load in the proof.
- `board status`: compare the snapshot's newest `seen_at` per repo against the BACKLOG.md's last git-log touch; print "N repos changed since last mirror, last synced <ts>".
- `--dry-run` prints the plan without loading. `HERMES_BIN` env injects a stub; NO real Hermes calls in the test suite.

## How to close the loop

Extend the kit `board` tool (README `mirror`/`status` sections, MANIFEST/tool.toml update) + its co-located proof-of-done. Wire the `mirror)` + `status)` dispatch cases into `_meta/board` + `_meta/board-all` (the same thin-exec pattern 04 established; existing render/next/priority stay unchanged, guarded by NC6). Kit-adopted repo: record gate-ledger phases before push.

Named negative controls (each a test):
1. Zero opted-in repos -> zero operations, exit 0, "0 rows" (honest-empty).
2. Idempotence: golden fixture mirrored twice -> second run's plan is EMPTY.
3. An opted-OUT repo (fixture named like `trading`) with rows -> never appears in any plan or board.
4. Stubbed loads: every executed write is a recorded `hermes kanban` CLI invocation; zero direct DB access (assert on the stub's call log).
5. Disappeared row (in the prior snapshot, absent from the current git parse) -> its card flips to `done` + `origin removed`; never left stale, never "deleted".
6. Registry non-regression: the REAL `_meta/board-all` AND `board queue` (04) run against the post-change `_meta/boards.txt` with unchanged output and exit 0.

Live leg (recorded in proof-of-done): dev-home E2E, run TWICE (fixture boards -> real local hermes -> `kanban list` shows the cards; run 2's plan is EMPTY), plus one `board status` render.

**Done =** tests green with the six NCs AND the doubled dev-home E2E capture AND the `status` demo in proof-of-done. (The live-Mini mirror belongs to the convergence demo, not here.)

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. Overwrite HANDOFF.md: next = 08 (`writeback`), first action = read the mirror-snapshot format (name file:line) the conflict rule keys on.
3. Append to DECISIONS.md: hermes version + flag drift + body-length limit + board-name collisions found in STEP 0, the row_hash definition, the state-mapping table, the boards.txt column shape.
4. Report IN the records, then EXIT IMMEDIATELY.

## Scope edges

**In:** the `mirror` + `status` subcommands in the kit `board` tool (bash) + the remote-applier plan format, the `bridge` column in `_meta/boards.txt` + its header comment, MANIFEST/tool.toml rows.
**Out:** `writeback` (08), Notion (P2, later), the runner's `queue` (04 owns it), any Hermes daemon/config change on the Mini, the live-Mini mirror run itself (convergence demo).
**Not:** cron/launchd sync, two-way anything, per-sub-goal mega cards, a web UI, SQLite ATTACH, Python, DuckDB.

## Where to look

`experiments/hermes-fleet/` (proven verbs + dev-home + ADR-0001), `experiments/hermes-triage/` (raw-SQL anti-pattern), `_meta/board-all` (registry walking + the non-regression NC target), 04's board-parse helper, the bridge design doc + its 2026-07-05 amendment.

## PR body

- Outcome: `board mirror` + `status` (bash), cockpit boards + mega cards onto a Hermes kanban, native-CLI-only access, opt-in, idempotent, incremental snapshot.
- Verification: 6-NC run-table + doubled dev-home E2E + status demo (inline).
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`.

## Notes

- 2026-07-05 architecture change (Han-directed): board is now the ONE bash board tool (queue/mirror/writeback); Python+DuckDB dropped. DuckDB stays only in ledger-observatory. Prior advisor deltas (live-Mini leg at the demo, board-all non-regression NC, state-mapping/shipped-filter/disappeared-row/incremental-snapshot/status/synced-stamp/collision-preflight/batched-ssh) all carry forward unchanged.
