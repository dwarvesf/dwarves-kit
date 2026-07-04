# Proof of done: board-bridge mirror (SPEC-147)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | `row-hash` deterministic + content-sensitive | PASS (3/3) | `tests/test-board-mirror.sh` "AC1" section |
| AC2 | `extract-rows` STATE MAPPING + shipped/dropped exclusion | PASS (11/11) | "AC2" section |
| AC3 | `extract-megas` active detection, progress, held flag, inactive-skip | PASS (5/5) | "AC3" section |
| AC4 | first-ever mirror run plans one CREATE per opted-in row, right flags/followup | PASS (7/7) | "AC4" section |
| AC5 | `board status` staleness (never/changed/up-to-date) + heals after re-mirror | PASS (4/4) | "AC5" section |
| AC6 | **NEGATIVE CONTROL (NC1):** zero opted-in repos -> zero ops, exit 0, honest empty | PASS (4/4) | "NC1" section |
| AC7 | **NEGATIVE CONTROL (NC2), LOAD-BEARING:** idempotence -- second run's plan is EMPTY | PASS (3/3, stubbed) + LIVE (below) | "NC2" section + Live dev-home E2E |
| AC8 | **NEGATIVE CONTROL (NC3):** opted-out repo never leaks into any plan/call/status | PASS (3/3) | "NC3" section |
| AC9 | **NEGATIVE CONTROL (NC4):** native-CLI-only, no direct DB access, no shell-templating | PASS (4/4) | "NC4" section |
| AC10 | **NEGATIVE CONTROL (NC5):** disappeared row -> done + "origin removed", never re-touched | PASS (5/5, stubbed) + LIVE (below) | "NC5" section + Live dev-home E2E |
| AC11 | **NEGATIVE CONTROL (NC6):** registry non-regression (bridge column costs SG-04 zero changes) | PASS (5/5) | "NC6" section |
| CD | Coverage delta | PASS | 0 -> 58 board-mirror-specific assertions |

**Automated suite total: 59/59 PASS, 0 FAIL, 0 SKIP.**

## Implementation

- `lib/board-mirror.sh` (new): the git<->Hermes bridge engine. Subcommands: `row-hash`,
  `extract-rows`, `extract-megas`, `snapshot-read`, `snapshot-upsert`, `plan`, `apply-plan`.
  Reuses `lib/parse-board.sh`'s `pb_rows` (sourced, not re-forked). Diff is a keyed comparison via
  awk (portable, no bash associative arrays -- bash-3.2-safe per the codebase's own discipline in
  `lib/orchestrate.sh`/`lib/parse-board.sh`); load is `hermes kanban` CLI verbs exclusively.
- `lib/board.sh`: two new dispatch cases (`mirror`, `status`) + `cmd_mirror`/`cmd_status`
  functions; five new shared flags (`--snapshot`, `--mega-board`, `--board-prefix`, `--remote`,
  `--remote-kit-path`) folded into the existing `_parse_flags` (harmless no-ops for every other
  subcommand); a new `_iso_to_utc_z` helper (BSD/GNU-portable ISO8601-with-offset normalization,
  needed for `status`'s staleness comparison).
- `tests/test-board-mirror.sh` (new): the 59-assertion run-table above.
- `tests/test-meta.sh`: one new structural pin (board-mirror.sh executable, board.sh wires
  mirror+status dispatch, doc-impact map updated).
- `README.md` / `docs/architecture.md`: doc-impact map entries for the new `lib/` file.
- `.github/workflows/test.yml`: one new CI step (`bash tests/test-board-mirror.sh`).
- `docs/specs/SPEC-147-board-bridge-mirror.md` (the `## Design` block carries the full STEP 0
  findings, state-mapping table, row_hash definition, snapshot format, and remote-applier plan
  format).

## Confirmation run (green)

```
$ bash tests/test-board-mirror.sh
=== AC1: row-hash is deterministic and content-sensitive ===
  PASS row-hash is 64 lowercase hex chars
  PASS row-hash is deterministic (same inputs -> same hash)
  PASS row-hash is content-sensitive (changed item -> different hash)

=== AC2: extract-rows STATE MAPPING + shipped/dropped exclusion ===
  PASS ID-001 (queued) -> target triage
  PASS ID-002 (claimed) -> target ready (todo has no durable synthetic path, see lib/board-mirror.sh)
  PASS ID-003 (speccing) -> target ready
  PASS ID-004 (validated) -> target ready
  PASS ID-005 (executing) -> target ready
  PASS ID-006 (parked) -> target blocked
  PASS ID-007 (shipped) is EXCLUDED from extraction
  PASS ID-008 (dropped) is EXCLUDED from extraction
  PASS ID-007's skip reason is logged
  PASS ID-008's skip reason is logged
  PASS extract-rows emits exactly the 6 bridgeable rows (001-006), not 8

=== AC3: extract-megas -- active detection, progress, held flag, inactive-skip ===
  PASS the active mega (1 unchecked box) is emitted
  PASS progress reads 1/2 (one checked, one unchecked)
  PASS the held-PR text signal is surfaced
  PASS mega target_native is ready
  PASS a fully-checked (inactive) mega is NOT emitted

=== AC4: first-ever mirror run (empty prior snapshot) plans one CREATE per opted-in row ===
  PASS dry-run plans exactly 7 ops (6 board rows + 1 mega card)
  PASS dry-run makes ZERO hermes calls
  PASS dry-run writes NOTHING to the snapshot
  PASS ID-001's create argv carries --triage (queued -> triage)
  PASS ID-002 (claimed->ready) needs no followup (todo has no durable synthetic path, so claimed falls back to ready)
  PASS ID-006's create argv carries NO --initial-status flag (that path auto-promotes back to ready)
  PASS ID-006 (parked->blocked) has followup=block-needs-input (create alone cannot reach a durable blocked)

=== Apply the AC4 plan for real (against the stub), building the golden snapshot for NC2 ===
  PASS run 1 applies with 0 errors
  PASS run 1 writes 7 rows to the snapshot
  PASS run 1 makes real stub calls (create + the ID-006 block-needs-input followup)
  PASS run 1 never issues a --kind dependency call (todo has no durable synthetic path, never attempted)

=== AC5 / board status ===
  PASS status reports up to date right after a mirror
  PASS status summary line matches the contract wording
  PASS status detects drift after a real git touch
  PASS status heals back to up to date after re-mirroring

=== NC1: zero opted-in repos -> zero Hermes operations, exit 0, honest empty ===
  PASS NC1: exit 0 on zero opted-in repos
  PASS NC1: stdout is empty
  PASS NC1: stderr honestly reports 0 changes
  PASS NC1: zero hermes calls made

=== NC2: IDEMPOTENCE (load-bearing) -- second run on an unchanged board is EMPTY ===
  PASS NC2: second dry-run's plan is EMPTY (0 bytes)
  PASS NC2: second run reports 0 create/change/complete
  PASS NC2: second (real, non-dry-run) run makes ZERO stub-hermes calls

=== NC3: an opted-OUT repo (fixTrading) never appears in any plan or applied calls ===
  PASS NC3: fixTrading's TR-001 never appears in the AC4 plan
  PASS NC3: fixTrading never appears in any stub call log so far
  PASS NC3: fixTrading never appears in board status output

=== NC4: every write is a recorded hermes CLI call; no direct DB access ===
  PASS NC4: the create calls in the log are 'kanban --board ... create ...' shaped
  PASS NC4: the ID-006 followup is a 'kanban ... block ... --kind needs_input' call, not a raw status flip
  PASS NC4: static audit -- neither board.sh nor board-mirror.sh ever references a .db/sqlite path in CODE (comments-only mentions, e.g. the ADR-0001 compliance note, are not a violation)
  PASS NC4: static audit -- neither file ever eval/sh-c's a parsed variable (card text never templated into a shell string)

=== NC5: a disappeared row (flips to shipped) -> done + 'origin removed', never stale ===
  PASS NC5: the disappeared ID-003 plans a 'complete' op, not silence
  PASS NC5: the complete op's reason names 'origin removed'
  PASS NC5: the complete op targets 'done'
  PASS NC5: after applying, the completed row is DROPPED from the snapshot (never re-touched)
  PASS NC5: re-running the plan does NOT re-complete ID-003 (idempotent even for disappeared rows)

=== NC6: REGISTRY NON-REGRESSION -- board/next/priority/states/queue unaffected by the bridge column ===
  PASS NC6: 'board all board' still renders both repo headers with a bridge column present
  PASS NC6: 'board all next' still resolves fixR's next queued row
  PASS NC6: 'board all states' still renders per repo
  PASS NC6: 'board queue' still exits 0 with the bridge column present (no #queue{} tokens seeded here, so 0 rows is correct)
  PASS NC6: single-repo 'board priority overview' is unaffected

=== Coverage delta ===
  PASS coverage delta: board-mirror checks went from 0 to 58 in this suite

  ---------------------------------------------
  TOTAL: 59   PASS: 59   FAIL: 0   SKIP: 0
```

## Negative control (load-bearing, confirmed RED then reverted)

`lib/board-mirror.sh`'s unchanged-row detection in the keyed-diff awk changed from
`} else if (p_hash[origin]==hash) {` to `} else if (0 && p_hash[origin]==hash) {` (an
unreachable condition, simulating the idempotence check silently disappearing):

```
$ bash tests/test-board-mirror.sh   (unchanged-detection neutered)
...
  FAIL NC2: second dry-run's plan is EMPTY (0 bytes)
  FAIL NC2: second run reports 0 create/change/complete
  FAIL NC2: second (real, non-dry-run) run makes ZERO stub-hermes calls
  ---------------------------------------------
  TOTAL: 57   PASS: 54   FAIL: 3   SKIP: 0
```

Exactly the three NC2 (idempotence) assertions flip red; every other assertion (AC1-AC5, NC1,
NC3-NC6, coverage) is unaffected, confirming they test independent behavior. File restored via
the Edit tool (byte-identical to the pre-breakage version, confirmed with `cmp`), suite
re-confirmed GREEN (59/59; the count grew from 57 to 59 between this control and the final run
because two assertions were added afterward for the `todo`-removal fix below -- both counts are
internally consistent with their own run).

## STEP 0 findings (Hermes v0.18.0, probed 2026-07-05)

Full detail lives in `docs/specs/SPEC-147-board-bridge-mirror.md`'s `## Design` block; summarized
here as the proof artifact:

1. **Hermes version**: `Hermes Agent v0.18.0 (2026.7.1)`, the currently-installed binary
   (`~/.local/bin/hermes`). No version drift handling was needed (this was the FIRST live probe
   against this exact version for this design).
2. **Card body length**: no truncation observed up to 20,000 characters.
3. **Board-name collision**: the shared `experiments/hermes-fleet` dev-home
   (`~/hermes-fleet-dev/home`) already has a real `ops-toolkit` board with prior-experiment data
   (`done=5, ready=1`). This sub-goal's live E2E therefore used a FRESH, distinctly-named
   disposable `HERMES_HOME` instead of the shared literal path, to avoid contamination --
   still "a throwaway dev-home, never `~/.hermes`", just not the same directory.
4. **The load-bearing finding**: two of the six documented `--status` values (`todo`, `running`)
   have NO durable CLI-only creation path at all -- a card lands there for an instant, then a
   later unrelated `hermes kanban` CLI call (even a plain `list`) silently auto-promotes it back
   to `ready`, with NO gateway/dispatcher process running at all (`ps aux` confirmed empty). Only
   `block <id> "..." --kind needs_input` (a post-create followup) was confirmed durable across
   20+ seconds and multiple intervening CLI calls, in both a 3-row and a 20-row live batch. See
   "Live dev-home E2E" below for the exact reproduction transcript.
5. **A real implementation bug this build's own E2E caught**: a newline-delimited `read` loop
   decoding a plan op's multi-line `--body` argv element split it into several bash array
   elements (bash's `read` splits on newline by default); the REAL Hermes CLI rejected the
   split-off lines as "unrecognized arguments", while a naive stub (`echo "$*"`) masked the bug
   completely. Fixed with a NUL-delimited jq decode (`jq -j '.[] | . + " "'` + `read -r -d
   ''`).

## Live dev-home E2E (doubled run, real Hermes CLI, NOT the automated suite)

Per the sub-goal contract, this leg runs against a real, disposable `HERMES_HOME` (never
`~/.hermes`), is captured here manually, and is NOT part of `tests/test-board-mirror.sh` (which
stubs `HERMES_BIN` and makes zero real Hermes calls, per the contract).

### Setup

```
$ export HERMES_HOME=<scratch>/board-mirror-e2e-home   # fresh, disposable, never ~/.hermes
$ hermes kanban init
$ hermes kanban boards create bm-e2e-repo
$ hermes kanban boards create bm-e2e-megagoals
```

Fixture: a real git repo with a 3-row `BACKLOG.md` (`queued`/`claimed`/`parked`) + one active
mega-goal `ROADMAP.md` (1 checked, 1 unchecked box), registered in a `boards.txt` with
`bridge=on`.

### Run 1 (fresh snapshot, real hermes CLI)

```
$ time bash lib/board.sh mirror --repo-root "$T" --registry "$T/boards.txt" \
    --snapshot "$T/snapshot.jsonl" --mega-board bm-e2e-megagoals
mirror: plan 4 ops (4 create, 0 change, 0 complete), 0 unchanged
mirror: create bm-e2e-repo:ID-001 -> t_6883d99e (triage)
mirror: create bm-e2e-repo:ID-002 -> t_237fe17c (ready)
mirror: create bm-e2e-repo:ID-003 -> t_9d9f8c09 (blocked)
mirror: create megagoals:bm-e2e-repo/bm-e2e-mega -> t_d72e975a (ready)
mirror: applied 4 create, 0 change, 0 complete, 0 error(s)
bash lib/board.sh mirror ...   0.67s user 0.31s system 85% cpu 1.139 total
```

Durability check (20 seconds + multiple intervening CLI calls later, to catch the auto-promotion
finding above):

```
$ sleep 20 && hermes kanban --board bm-e2e-repo list --json | jq -r '.[] | "\(.id) \(.status) \(.title)"'
t_6883d99e triage Write the E2E proof
t_237fe17c ready Claim the review
t_9d9f8c09 blocked Wire the ssh applier
$ hermes kanban --board bm-e2e-megagoals list --json | jq -r '.[] | "\(.id) \(.status) \(.title)"'
t_d72e975a ready bm-e2e-mega
```

All four cards durable at their intended native status after 20+ seconds -- `triage` and
`blocked` held exactly as designed (the `parked`-row's `block ... --kind needs_input` followup
did NOT auto-promote, unlike the earlier `--initial-status blocked`/`--kind dependency` attempts
this build tried and rejected -- see the STEP 0 findings above).

### Run 2 (idempotence, real hermes CLI, SAME snapshot, no git changes)

```
$ time bash lib/board.sh mirror --repo-root "$T" --registry "$T/boards.txt" \
    --snapshot "$T/snapshot.jsonl" --mega-board bm-e2e-megagoals
mirror: plan 0 ops (0 create, 0 change, 0 complete), 0 unchanged
mirror: 0 changes
bash lib/board.sh mirror ...   0.03s user 0.05s system 91% cpu 0.087 total
```

**Run 2's plan is EMPTY** (0 create, 0 change, 0 complete) and makes **zero** Hermes calls
(0.087s vs run 1's 1.14s) -- idempotence proven live, not just against the stub.

### Disappeared-row completion (live)

```
$ sed -i 's/| ID-002 | Claim the review | claimed by the worker | claimed |/... | shipped |/' BACKLOG.md
$ git commit -m "test: ship ID-002 live"
$ bash lib/board.sh mirror --repo-root "$T" --registry "$T/boards.txt" --snapshot "$T/snapshot.jsonl" --mega-board bm-e2e-megagoals
board-mirror: skip ID-002 (bm-e2e-repo): status 'shipped' not bridged (shipped/dropped/unrecognized)
mirror: plan 2 ops (1 create, 0 change, 1 complete), 0 unchanged
mirror: create bm-e2e-repo:ID-004 -> t_fa26eb38 (triage)
mirror: complete bm-e2e-repo:ID-002 -> t_237fe17c (done)
mirror: applied 1 create, 0 change, 1 complete, 0 error(s)

$ hermes kanban --board bm-e2e-repo show t_237fe17c --json | jq -r '.task.status, .task.result'
done
board-mirror: origin removed from bm-e2e-repo board
```

### Batched load (20 rows, real hermes CLI) -- the measured wall time

```
$ time bash lib/board.sh mirror --repo-root "$T" --registry "$T/boards.txt" --snapshot "$T/snapshot.jsonl"
mirror: plan 20 ops (20 create, 0 change, 0 complete), 0 unchanged
... (20 create lines: 5 triage, 5 ready, 5 ready, 5 blocked)
mirror: applied 20 create, 0 change, 0 complete, 0 error(s)
bash lib/board.sh mirror ...   3.31s user 1.45s system 86% cpu 5.504 total

$ sleep 20 && time bash lib/board.sh mirror --repo-root "$T" --registry "$T/boards.txt" --snapshot "$T/snapshot.jsonl"
mirror: plan 0 ops (0 create, 0 change, 0 complete), 0 unchanged
mirror: 0 changes
bash lib/board.sh mirror ...   0.07s user 0.13s system 96% cpu 0.209 total

$ hermes kanban --board bigrepo list --json | jq -r '.[] | .status' | sort | uniq -c
   5 blocked
  10 ready
   5 triage
```

**Batched load: 5.504s wall time for 20 rows (25 total `hermes kanban` subprocess invocations
including followups), ~220ms/invocation.** Idempotent re-run: 0.209s, 0 Hermes calls. Durability
at scale confirmed: exactly 5 blocked, 5 triage, 10 ready -- matching the fixture's 5
`parked`/5 `queued`/10 `claimed`+`speccing` rows exactly, still correct after 20+ seconds.

## `board status` demo

```
$ bash lib/board.sh status --repo-root "$T" --registry "$T/boards.txt" --snapshot "$T/snapshot.jsonl"
status: bm-e2e-repo: up to date (mirrored 2026-07-04T22:02:07Z)
0 repos changed since last mirror, last synced 2026-07-04T22:02:07Z

$ echo "| ID-004 | Post-mirror addition | ... | queued |" >> BACKLOG.md && git commit
$ bash lib/board.sh status --repo-root "$T" --registry "$T/boards.txt" --snapshot "$T/snapshot.jsonl"
status: bm-e2e-repo: changed since last mirror (touched 2026-07-04T22:02:47Z, mirrored 2026-07-04T22:02:07Z)
1 repos changed since last mirror, last synced 2026-07-04T22:02:07Z
```

(The automated suite's AC5 section additionally confirms `status` heals back to "up to date"
after a re-mirror.)

## Also verified: no regression to sibling suites

```
$ bash tests/test-board.sh
...
=== NC-e: RENDER NON-REGRESSION against the REAL ops-toolkit cockpit ===
  PASS NC-e: single-board byte-identical
  ... (9/9)
  ---------------------------------------------
  TOTAL: 45   PASS: 45   FAIL: 0   SKIP: 0

$ bash tests/test-meta.sh
...
  PASS board-bridge mirror wired: lib/board-mirror.sh executable, board.sh dispatches mirror+status, doc-impact map updated (SPEC-147)
=== Results ===
Passed: 669 / 670
Failed: 1
```

The one `test-meta.sh` failure (`no duplicate SPEC numbers (dups: SPEC-146)`) is PRE-EXISTING
and unrelated to this sub-goal: `docs/specs/SPEC-146-cockpit-board-tool.md` and
`docs/specs/SPEC-146-overnight-queue-launcher.md` both already existed on `master` before this
branch started (a numbering collision from the earlier parallel-wavefront dispatch of sub-goals
03K/04). This sub-goal reserved its own number correctly via `bash lib/spec-next.sh reserve`
(returned 147, no collision).

```
$ bash tests/test-hooks.sh
=== Results ===
Passed: 452 / 452
All tests passed.
```

## `shellcheck` (clean)

```
$ shellcheck lib/board-mirror.sh lib/board.sh tests/test-board-mirror.sh
$ echo $?
0
```

(Two INFO-level findings needed an explicit directive to reach exit 0: `# shellcheck
source=/dev/null` above the dynamic `source "$PARSE_BOARD_SH"`, and `# shellcheck disable=SC2029`
above the intentional client-side `${remote_kit}` expansion in the ssh call.)

## Reproduce

```bash
cd dwarves-kit
bash tests/test-board-mirror.sh
bash tests/test-board.sh
bash tests/test-meta.sh
bash tests/test-hooks.sh
shellcheck lib/board-mirror.sh lib/board.sh tests/test-board-mirror.sh

# For the negative control: in lib/board-mirror.sh, change
# `} else if (p_hash[origin]==hash) {` to `} else if (0 && p_hash[origin]==hash) {`
# inside cmd_plan's awk script, re-run tests/test-board-mirror.sh, observe the 3 NC2
# failures above, then revert.

# Live dev-home E2E (NOT the automated suite; never ~/.hermes):
export HERMES_HOME=/tmp/some-throwaway-dir
hermes kanban init
hermes kanban boards create <repo-name>
hermes kanban boards create megagoals
bash lib/board.sh mirror --repo-root <fixture-repo-root> --registry <fixture-boards.txt> \
  --snapshot <fixture-repo-root>/_meta/.board-mirror-snapshot.jsonl
hermes kanban --board <repo-name> list --json
# run again to confirm the second plan is empty:
bash lib/board.sh mirror --repo-root <fixture-repo-root> --registry <fixture-boards.txt> \
  --snapshot <fixture-repo-root>/_meta/.board-mirror-snapshot.jsonl
```
