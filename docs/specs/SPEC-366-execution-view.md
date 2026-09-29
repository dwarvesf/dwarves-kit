# Spec: board work, one table of who is on what and how far along

Generated: 2026-09-29
Status: DRAFT
Lane: normal
References: `lib/mega/mega.sh` (`_sub_branch` line 173, `GH_BIN`/`GIT_BIN` env seams lines 131-132: read a branch from a sub-goal file, swap the external binary in tests); `lib/board/parse-board.sh` (`pb_rows` line 60: the one board row parser); `lib/gate/gate-ledger.sh` (`rid` line 750, `normalize_phase` line 109: the branch to run-id rule and the phase names). Research source: `docs/research/2026-09-29-openrig-absorption.md`, section "The dashboard (second operator review)", design D7a.

## Problem

The operator runs several agents in parallel worktrees. Answering "who is on what, how far along, and who is stuck" today takes four lookups: the board (`board` rows), the mega sub-goal files, `orca worktree ps` (live terminals), and the run ledger (`gate-ledger.sh show <rid>`). No command joins them. Two failure shapes follow:

- An item marked in progress whose agent went quiet an hour ago looks identical to one being worked. Nothing flags it.
- A shipped item nobody wrapped (no `wrap ran` record) drops off the board's attention with its worktree and branch still alive.

Existing pieces cover one source each: `mega status` (`lib/mega/mega.sh`) joins a roadmap to git and PRs for one mega only, `board` renders rows only, `orca worktree ps` shows terminals only. `precedent find --surface inventory` found no view that joins them (research doc, line 243).

## Solution

### Approaches considered

| Approach | What it is | Main tradeoff |
|---|---|---|
| A. `board work` verb, one bash script under `lib/board/` | Reads the four sources at call time, joins with jq, prints a table or JSON. | No new entry point and no new dependency (jq is already required). Bash join logic must stay small. |
| B. A `stats` table | Add a `work` table to the uv-managed Python read plane. | `stats` rebuilds from append-only ledgers; live terminal state and git worktrees are not ledgers, and it needs `uv`. SPEC-367 is also editing that plane. |
| C. New `bin/work` entry | A standalone command. | `tests/test-bin-forwarders.sh:38` pins the `bin/` census (ADR-0034); a new entry needs an ADR amendment and a census edit for one verb. |

### Chosen approach + why

A. The rows already come from `lib/board/parse-board.sh`, `bin/board` already forwards every verb, and `_meta/board` shims in consumer repos already append `--backlog-file` (ops-toolkit `_meta/board` shim), so `_meta/board work` works with zero consumer change. B loses on freshness and on the SPEC-367 collision. C spends an ADR on a read-only table.

Name: `board work`. Plain words: the table answers "what work is going on". "execution view" stays the design's internal name and appears nowhere the operator reads.

### Extensibility & boundaries

- Load-bearing dimension: the number of sources. Each source is one function that prints normalized JSON lines (`src_board`, `src_mega`, `src_git`, `src_orca`, `src_ledger`); the join and the rendering never read a source directly. SPEC-370 needs a second worktree backend later; it swaps `src_orca` and leaves the join alone.
- Units: five source readers, one join, one flag calculator, two renderers (table, JSON). Each fits in three sentences.

## Picture

```
 _meta/BACKLOG.md ──pb_rows──┐        .claude/goals/{,done/}*.md
 (in-progress + shipped)     │        (frontmatter id: ID-NNN -> slug)
                             ▼                     │
 mega ROADMAP `- [ ] SG-NN` ─► JOIN by branch ◄────┘
 + goals/SG-NN.md **Branch:**   │   ▲      ▲
                                │   │      └── git for-each-ref / git worktree list
                                │   │           (branch -> path, rid = branch slug)
                                │   └── orca worktree ps --json  (path -> state, lastOutputAt)
                                └────── runs/<rid>.log  (GATE lines -> rung, wrap ran?)
                                            │
                          flags: PARKED / DONE-UNSEEN / INDETERMINATE
                                            │
                                  one table   |   --json
```

## Design

Design-bearing: new module, a five-source join, and a rule about missing data.

### Data model (the row, computed at read time, stored nowhere)

| Field | Source | Notes |
|---|---|---|
| `item` | board id (`ID-923`) or `<mega>/<sub>` | |
| `origin` | `board` or `mega` | |
| `branch`, `worktree` | git | worktree may be null |
| `agent.state` | orca | `working`, `idle`, `unknown` |
| `agent.idle_s` | orca `lastOutputAt` | present only when `state` is `idle` |
| `rung` | ledger | `shipped` > `reviewed` > `built` > `validated`, else `none` |
| `flags` | computed | any of `PARKED`, `DONE-UNSEEN`, `INDETERMINATE` |
| `reasons` | computed | one token per missing key, see below |

### Join rules (in order, each step may fail into INDETERMINATE)

1. Board row to slug: find `.claude/goals/*.md` or `.claude/goals/done/*.md` whose frontmatter has `id: <row id>`; take its `slug:`. Miss: `no-draft`.
2. Slug to branch: local branch whose part after the first `/` normalizes (same rule as `gate-ledger.sh` `runid`) to the slug. Miss: `no-branch`. Two hits: `ambiguous`.
3. Branch to worktree path: `git worktree list --porcelain`. Miss on an in-progress item: `no-worktree`. A shipped item may lose its worktree legitimately; its worktree cell is `-` and no flag is raised for that alone.
4. Path to agent state: the `worktree ps` row with the same `path`. Orca missing, failing, or non-JSON: `no-orca`. Row absent from the page: `not-in-orca`. Row present with zero live terminals or no `lastOutputAt`: `no-terminal`.
5. Branch to rid: `slug="${branch#*/}"`, normalized like `runid`. Ledger file absent: rung `none` with no flag (a freshly claimed row legitimately has no ledger yet).
6. Mega sub-goal: a `- [ ] SG-NN` (or `NN-slug`) roadmap line whose `goals/<sub>.md` carries `**Branch:** <name>` enters at step 2 with that branch. A sub-goal with no Branch line is not started and is not listed.

### Agent state rule

```
status == "working" or any agents[].state == "working"      -> working
liveTerminalCount > 0 and lastOutputAt != null (not working) -> idle, idle_s = now - lastOutputAt/1000
anything else                                                -> unknown  (never idle, never done)
```

### Flag rules

| Flag | Condition |
|---|---|
| PARKED | item in progress (board status leads with `claimed`, `speccing`, `validated` or `executing`; or a started mega sub-goal) AND `agent.state == idle` AND `idle_s >= idle_min * 60` |
| DONE-UNSEEN | ledger has `GATE | ship | ran` AND no `GATE | wrap | ran` in the same rid's ledger |
| INDETERMINATE | any join step above failed; the reason token prints beside it |

A shipped item with a `wrap ran` record is finished and seen, so it is not listed. Board rows that are `queued`, `parked` or `dropped` are not listed. Shipped board rows with no draft or branch cannot be checked; the footer counts them ("N shipped rows unchecked, no local branch") so the gap is visible, not hidden.

"shipped" here means the ledger's `Ship ran` record, written at `commands/ship.md:169` before the PR merges. The legend line says so.

### ADR link(s)

None new. This adds a verb inside the existing `board` subsystem; ADR-0034's `bin/` census is untouched. The JSON shape below becomes a contract SPEC-370 consumes; it is recorded here, not in an ADR.

### Boundaries & failure modes

See `## Failure modes`. The view never writes: no ledger append, no `kit_migrate_log_dir` call (that resolver copies files on first access; this command calls only `kit_resolve_log_dir`, which is pure), no orca verb other than `worktree ps`.

## Technical Design

### Interfaces (I/O contract)

Command: `board work [--json] [--idle-min N] [--backlog-file F] [--repo-root D]`; `bin/board` forwards it, `lib/board/board.sh` gets one dispatch case, the logic lives in `lib/board/work.sh`.

- Inputs: `BACKLOG.md` (via `pb_rows`), `<repo-root>/_meta/megagoals/*/ROADMAP.md` and `goals/*.md`, `<repo-root>/.claude/goals/{,done/}*.md`, `git` (branches, worktrees), `orca worktree ps --json --limit 500`, `<ledger root>/runs/<rid>.log` (root from `kit_resolve_log_dir`).
- Flags: `--idle-min N` sets the PARKED threshold in minutes (default 20). `--now <epoch-seconds>` is a test seam that fixes the clock. Env `ORCA_BIN` (default `orca`) and `GIT_BIN` (default `git`) swap the binaries, same convention as `GH_BIN`/`GIT_BIN` in `lib/mega/mega.sh:131-132`. No `KIT_*` variable and no `kit.toml` key is added.
- Table output: one header line, one row per item (`ITEM  WORKTREE  AGENT  RUNG  FLAGS`), then a footer with the threshold, the orca scope, and the legend.
- `--json` output (stable): `{"generated_at":<epoch>,"idle_min":N,"orca":"ok|absent|error","truncated":bool,"items":[{"item","origin","branch","worktree","agent":{"state","idle_s"},"rung","flags":[],"reasons":[]}],"unchecked_shipped":N}`.
- Exit codes: 0 always after a render (orca absent included). 64 on a bad flag. 1 only when the backlog file is unreadable.
- Invariants: no writes anywhere; a missing key never renders as `idle` or as a finished rung; sorted output (flagged rows first, then by item) so the same inputs give the same bytes.

### Data model changes
n/a: read-time only, no stored status.

### API changes
n/a: one new CLI verb, specified above.

### UI changes
n/a: table and JSON only. No TUI, no daemon.

### Infrastructure changes
n/a: no new dependency, no new bin entry.

## Task Breakdown

### Phase 1: Foundation
- [ ] TASK-A: `tests/test-board-work.sh` plus `tests/fixtures/board-work/` (stub `orca`, two ledgers, backlog, drafts, mega roadmap). Acceptance: the suite runs and fails on every case before TASK-B exists.
- [ ] TASK-B: `lib/board/work.sh` source readers (`src_board`, `src_mega`, `src_git`, `src_orca`, `src_ledger`). Acceptance: each prints its normalized lines from the fixtures; orca absent or broken prints `orca=absent|error` and exits 0.

### Phase 2: Core
- [ ] TASK-C: join, agent-state rule, flag rules, both renderers in `work.sh`. Acceptance: the PARKED, INDETERMINATE and DONE-UNSEEN cases in the test plan are green.
- [ ] TASK-D: dispatch case `work) shift; exec bash "$BOARD_DIR/work.sh" "$@"` in `lib/board/board.sh` `main()` plus one usage line in its header (help is `sed -n '2,168p'`, line 1153, so the line goes inside that range). Acceptance: `bin/board work --json` and `_meta/board work` in a consumer repo both reach the script.

### Phase 3: Polish
- [ ] TASK-E: run the read-only and negative-control cases against the live orca once (output pasted into the proof, ids masked). Acceptance: proof-of-done table per the repo convention.

## After state
- [ ] `bin/board work` prints one table joining board rows, mega sub-goals, orca state and ledger rungs. (Today: four separate lookups.)
- [ ] An in-progress item whose terminal has been quiet at least `--idle-min` minutes shows `PARKED`. (Today: indistinguishable from active work.)
- [ ] A shipped item with no `wrap ran` shows `DONE-UNSEEN`. (Today: invisible.)
- [ ] A row missing any join key shows `INDETERMINATE(<reason>)`, never `idle` or a finished rung. (Today: n/a.)
- [ ] With `orca` absent the command exits 0 and every agent cell is `unknown`. (Today: n/a.)
- [ ] The command changes no file: `git status --porcelain` and the ledger directory hash are identical before and after.

## Acceptance Criteria (global)
- [ ] All tasks pass their individual acceptance criteria
- [ ] AC1 PARKED: fixture in-progress row, terminal idle 45 min, threshold 20: `bash tests/test-board-work.sh` case `parked_idle_past_threshold` prints `ok` and its row carries `PARKED`.
- [ ] AC2 threshold is real: same fixture idle 5 min, or `--idle-min 60`, carries no `PARKED`: case `not_parked_under_threshold`.
- [ ] AC3 no worktree: fixture row whose branch has no worktree renders `INDETERMINATE(no-worktree)` and its agent cell is `unknown`, never `idle`: case `no_worktree_indeterminate`.
- [ ] AC4 no draft: row with no matching draft renders `INDETERMINATE(no-draft)`: case `no_draft_indeterminate`.
- [ ] AC5 orca absent: `ORCA_BIN=/nonexistent bin/board work --json` exits 0, `orca` is `"absent"`, every item's `agent.state` is `"unknown"` and carries `INDETERMINATE`: case `orca_absent`. Same for an orca stub that exits 1 or prints non-JSON (`orca=error`).
- [ ] AC6 DONE-UNSEEN: ledger with `ship ran` and no `wrap ran` renders `DONE-UNSEEN`; adding a `wrap ran` line removes the row: case `done_unseen`.
- [ ] AC7 rung: `validate skipped` alone is `none`; `validate ran` is `validated`; `build ran` on top is `built`: case `rung_ladder`.
- [ ] AC8 mega: a `- [ ] SG-01` line with `**Branch:**` and a matching worktree lists as `<mega>/SG-01`; an SG line with no Branch is absent: case `mega_rows`.
- [ ] AC9 read-only: file hashes of the fixture repo, ledger dir and goals dir are equal before and after, and the stub orca's call log holds only `worktree ps --json --limit 500`: case `read_only`.
- [ ] AC10 `--json` is valid and matches the contract keys: case `json_shape` (`jq -e` on every key in `### Interfaces`).
- [ ] No regressions: `bash tests/test-board.sh && bash tests/test-bin-forwarders.sh` stay green (bin census unchanged).

## Verification
```
bash tests/test-board-work.sh
bash tests/test-board.sh && bash tests/test-bin-forwarders.sh
bash tests/test-meta.sh
bash tests/run-all.sh --only board
```
Live smoke, read-only: `bash bin/board work --idle-min 20` from a repo with a backlog; then `git status --porcelain` unchanged.

## Test plan

Coverage matrix (every case hermetic: temp git repo, temp `DWARVES_KIT_LOG_DIR`, stub `orca` from `tests/fixtures/board-work/`, `--now` fixed; the live `orca` is never called by the suite).

| Case | Category | Setup | Expect |
|---|---|---|---|
| `parked_idle_past_threshold` | happy | executing row, worktree present, stub `lastOutputAt` = now - 45 min, `status` inactive | `agent idle 45m`, flag `PARKED` |
| `not_parked_under_threshold` | NEGATIVE CONTROL | same, idle 5 min; and same 45 min with `--idle-min 60` | no `PARKED` |
| `working_never_parked` | NEGATIVE CONTROL | same row, stub `status` working | `agent working`, no `PARKED` |
| `no_worktree_indeterminate` | NEGATIVE CONTROL | draft and branch exist, no `git worktree add` | `INDETERMINATE(no-worktree)`, agent `unknown`, no `PARKED`, no idle text |
| `no_draft_indeterminate` | edge | row with no draft file | `INDETERMINATE(no-draft)` |
| `not_in_orca` / `no_terminal` | edge | worktree missing from stub page; worktree with `liveTerminalCount` 0 | `INDETERMINATE(not-in-orca)`, `INDETERMINATE(no-terminal)` |
| `ambiguous_branch` | edge | two branches normalize to one slug | `INDETERMINATE(ambiguous)` |
| `orca_absent` | failure | `ORCA_BIN=/nonexistent`; then stub exit 1; then stub prints `not json` | exit 0, `orca` absent or error, all agents `unknown` |
| `orca_truncated` | failure | stub `truncated:true`, target row not in page | `INDETERMINATE(not-in-orca)`, footer says truncated |
| `done_unseen` | happy + NEGATIVE CONTROL | ledger with `ship ran`; then add `wrap ran` | flag present; then row gone |
| `rung_ladder` | happy | four ledgers: none, validate skipped, validate ran, build ran | `none`, `none`, `validated`, `built` |
| `mega_rows` | happy | roadmap with one started and one unstarted sub-goal | only the started one lists |
| `read_only` | invariant | hash before and after, stub call log | identical; one orca call, `worktree ps --json --limit 500` |
| `json_shape` | contract | `--json` on the full fixture | `jq -e` passes on every contract key |
| `shipped_unchecked_footer` | edge | shipped row with no branch | footer `1 shipped rows unchecked` |

The three NEGATIVE CONTROL rows are the ones the operator named: an in-progress row with an idle terminal past the threshold must render PARKED, and the same row with the worktree removed must render INDETERMINATE and never idle.

## Edge Cases
1. A worktree shared by two rows: both rows show the same agent state. Accepted; the join key is the branch.
2. `lastOutputAt` in the future (clock skew): `idle_s` floors at 0, no `PARKED`.
3. Orca reports a `status` other than `working` or `inactive`: agent `unknown`, `INDETERMINATE(no-terminal)`.
4. `ID-NNN` present twice in the backlog (`merge=union` collision): first occurrence wins, same as `parse-board.sh`'s dedupe rule; the second is not listed.
5. Draft moved to `.claude/goals/done/` after ship: still found (both directories are read).
6. A ledger `skipped` record never counts as a rung (the sample ledger shows `validate skipped "NEEDS REVISION ..."`, which must read as not validated).
7. Guarantee inversion: "a missing key never renders as idle or done" is checked by `no_worktree_indeterminate`, `orca_absent` and `not_in_orca` together; "read-only" is checked by `read_only`.
8. `phase` naming: `execute` normalizes to `build` (`gate-ledger.sh:122`); the reader matches `build`, and a legacy ledger that recorded `execute` is normalized the same way.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| `orca` not installed or daemon down | `ORCA_BIN` missing, non-zero exit, or non-JSON | `orca=absent|error`, agents `unknown`, `INDETERMINATE(no-orca)`, exit 0 |
| Orca JSON shape changes | `jq` cannot read `.result.worktrees[]`, or `path`/`lastOutputAt` absent | treated as `error`; the shape sample is pinned in `## Grounding` and `json_shape` fixtures |
| Page truncated | `truncated:true` in the orca result | rows not on the page are `not-in-orca`, footer names it; `--limit 500` keeps this rare |
| Ledger root wrong | `runs/` missing | every rung `none`, footer prints the resolved ledger root so a wrong root is visible |
| Clock differs between hosts | orca on another host (`hostId` not `local`) | rows whose `hostId` is not `local` are `INDETERMINATE(no-orca)` in v1 (see Out of Scope) |

## Out of Scope
- Any write: no board flip, no ledger record, no `orca worktree set`, no terminal send. The view reports; the operator acts.
- Per-role or per-seat state, context percent, queue depth, a topology graph, a TUI, a daemon. The research doc lists them for OpenRig's own view; D7a excludes them.
- Cross-repo aggregation (`board-all` style). One repo per call; SPEC-370 can loop.
- Remote orca hosts (`hostId` other than `local`).
- A `kit.toml` key or `KIT_*` env for the threshold (would touch `lib/config/**`, which SPEC-368 edits). `--idle-min` is the only knob in v1; promote it later if it is set the same way twice.
- The ceremony versus progress lens (SPEC-367), lanes as data (SPEC-368), whole-spec dispatch (SPEC-369), orca as a mega backend (SPEC-370), adopt and onboarding (SPEC-371).

## Touches
- lib/board/**
- tests/fixtures/board-work/**

The suite file `tests/test-board-work.sh` sits directly under `tests/`; the prefix-glob form cannot name a single file there, and no sibling spec adds a file with that name.

## Siblings
| Spec | Relation |
|---|---|
| SPEC-367 ceremony-lens | Reads the same run ledger, different lens (ceremony vs progress). No shared file. Neither depends on the other. |
| SPEC-368 lanes-as-data | Rung is "highest ledger phase reached", not "lane checklist complete", so a light lane that skips `validate` shows `built`, not a lower rung. No file overlap (this spec adds no `kit.toml` key on purpose). |
| SPEC-369 whole-spec-dispatch | The rung reader keys on the recorded phase names `validate`, `build`, `review`, `ship`, `wrap`. If 369 renames or drops the `build` record, this reader must follow. |
| SPEC-370 orca-mega-backend | CONSUMES `board work --json`; the contract above is the interface. `src_orca` is the one place that calls orca, so 370's backend change swaps that function. 370 depends on this spec, not the reverse. |
| SPEC-371 adopt-pointer-onboarding | No overlap. |

## Grounding

Live read-only samples taken 2026-09-29.

Orca shape, `orca worktree ps --json` (7 worktrees; only the keys this spec reads, content fields omitted):
```
result keys:  hostScope, totalCount, truncated, worktrees
worktree keys (excerpt): path, branch ("refs/heads/main"), hostId ("local"), status ("working"|"inactive"),
  liveTerminalCount, lastOutputAt (epoch ms, null on 6 of 7 rows), agents[].state ("done"|"working")
observed status values: inactive, working
```
Orca help: `orca worktree ps [--limit <n>] [--json]`; `orca agent-context --json` reports 236 commands, schema v1. Only `worktree ps` is called. `lastOutputAt` is the terminal's last-activity field; null means no output recorded, which maps to `unknown`, never `idle`.

Run ledger line shape (`~/.local/state/dwarves-kit/logs/runs/land-regate-after-wait.log`):
```
2026-09-29T13:35:20Z | GATE | spec | ran | SPEC-365-land-regate-after-wait drafted, tasks=4
2026-09-29T14:00:30Z | GATE | validate | skipped | NEEDS REVISION round 1 (7/7 parallel): ...
```
Fields split on ` | `: `$2` = `GATE`, `$3` = phase, `$4` = `ran|skipped`. Writer: `lib/gate/gate-ledger.sh:213`. Ledger root: `LOG_DIR/runs` (`gate-ledger.sh:64`), root from `kit_resolve_log_dir` (pure; only `kit_migrate_log_dir` writes, per `lib/telemetry/kit-log-dir.sh:74-79`).

Board rows: `| ID-921 | backlog.sh set folds a stray flag into the note #board #safety | ... | shipped [PR #689] |` (kit `_meta/BACKLOG.md:41`); status is the last cell, leading keyword is the state (`lib/board/parse-board.sh:60-69`). Shipped rows stay in the table. There is no branch or worktree column, which is why the join goes through the goal draft.

Goal draft frontmatter (`commands/assign.md:66-72`): `slug:`, `id: ID-NNN`, `target_spec:`; retired drafts move to `.claude/goals/done/` (`commands/assign.md:76`). Branch to rid: `slug="${branch#*/}"` (`gate-ledger.sh:758`). Mega sub-goal branch: `**Branch:** feat/engine-learn-seam` in `_meta/megagoals/learning-boundary/goals/01-engine-seam-and-lint.md`, read by `lib/mega/mega.sh:173-177`.

Phase records: `Ship ran "shipping pr=#<N>"` at `commands/ship.md:169`; `wrap ran` at `commands/wrap.md:302`; `build ran` at `commands/execute.md:485`; `review ran` at `commands/review.md:156`; `execute` aliased to `build` at `gate-ledger.sh:122`.

Census pin: `tests/test-bin-forwarders.sh:38` (`EXPECTED=` list), so no new `bin/` entry.

Dry traces for the negative controls:
- Mutation 1: make the agent-state rule return `idle` when `liveTerminalCount` is 0. Fixture read: `no_worktree` fixture has a branch but no worktree, so no orca row matches. Code path: join step 3 fails, agent stays `unknown`. With the mutation the agent cell says `idle` and `no_worktree_indeterminate` goes red (asserts the cell is `unknown` and no `PARKED`).
- Mutation 2: drop the `idle_s >= idle_min * 60` comparison. Fixture: `not_under_threshold` (idle 5 min). Code path: PARKED rule fires on any idle. `not_parked_under_threshold` goes red.
- Mutation 3: count a `validate skipped` line as a rung. Fixture: ledger 2 in `rung_ladder`. `rung_ladder` goes red.

## Decision Log
- DEC-A: verb `board work` inside `lib/board/`, not a new `bin/` entry. Census pin at `tests/test-bin-forwarders.sh:38`; alternatives rejected: `stats` table (SPEC-367 collision, needs uv), `bin/work` (ADR amendment for one verb).
- DEC-B: threshold is a flag only in v1. A `kit.toml` key or `KIT_*` env needs a registry row and touches `lib/config/**` (SPEC-368's area).
- DEC-C: no ledger means rung `none`, not INDETERMINATE. A fresh claim has no ledger, and "no ledger" is a fact, unlike an unreadable terminal.
- DEC-D: rung is the highest phase reached, so lighter lanes read correctly (SPEC-368).

## Open questions
- Full lane or normal? The classifier says normal (`lane-classify.sh classify`). The `--json` shape is a contract SPEC-370 consumes, which is a weak "API contract" signal. Chosen: normal; the operator may raise it.
- A worktree with zero live terminals: `unknown` (chosen, conservative) or `idle`? An item in progress with no terminal at all might deserve its own flag later.
- `Ship ran` precedes the merge. Should the rung read `shipped` only after the PR merged (would need a `gh` call, breaking "no network")? Chosen: ledger only, legend says so.
