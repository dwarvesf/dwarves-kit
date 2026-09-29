# Spec: ceremony lens (gate work versus progress and catches, plus a gap tag on escapes)

Generated: 2026-09-29
Status: DRAFT
Lane: normal
References: `lib/stats/src/stats/anomalies.py` (the `_detect_ceremony` floor-and-fire shape, `DEFAULTS`, `--threshold`), `lib/stats/tests/test-anomalies-advisor.sh` (fixture harness: env vars point every source at a temp dir, a real end-to-end rebuild, a negative control per detector)
Source: `docs/research/2026-09-29-openrig-absorption.md`, design D5 and the "Operator hypothesis, tested" table

## Problem

The kit records what its gates did but not whether the gate work paid off. The OpenRig absorption pass (D5) wants one number that shows whether the middle of the pipeline is ceremony: gate activity, against what shipped, against what the gates caught. Later specs (whole-spec dispatch, light default lanes) claim to cut that activity. Without a baseline measured first, those claims stay estimates.

Premise check, what the code does today (all read on 2026-09-29):

| Claim | Evidence |
|---|---|
| A ceremony detector already exists, but it is per gate ("this gate never caught anything"), not per run or per window | `lib/stats/src/stats/anomalies.py:204-324`; it groups by `gate` and never reads diff size or PRs |
| The detector list is a tuple, and a new detector is one function plus one entry | `lib/stats/src/stats/anomalies.py:561-565`; thresholds live in `DEFAULTS` at `:38-69`; `parse_thresholds` rejects any key not in `DEFAULTS` (`:582-609`) |
| `kit_gates` has no timestamp for the GATE line itself, only bracket times when an OUTCOME pair exists | `lib/stats/src/stats/schemas.py:75-84` (columns `rid, gate, outcome, caught, reason, start_ts, end_ts, cost`) |
| `git_fixes` has files and subject, no line counts | `lib/stats/src/stats/schemas.py:94`, and `adapters.py:296` runs `git log --name-only`, never `--numstat` |
| Sessions carry tokens but no rid, so tokens cannot be attributed to a run from the sessions table | `lib/stats/src/stats/anomalies.py:335-337`, `schemas.py:124` |
| Per-run token lines are almost all fixture data | live ledgers under `~/.local/state/dwarves-kit/logs/runs/`: 125 of 126 `TOKENS` lines and 392 of 431 `START` lines sit in `sg-*`, `tier4-fixture*`, `turncap-fixture` files (awk count, 2026-09-29); the real runs carry one `TOKENS` line between them |
| Fixture ledgers carry no GATE or OUTCOME lines, so the gate-based counts are clean; only START and TOKENS are polluted | same awk count: those 8 files hold 0 `GATE`, 0 `OUTCOME` lines |
| The pollution is live, not historic | mtime of `sg-01.log` and `tier4-fixture.log` is 2026-09-29 19:21 and 19:22; `tests/test-tier4-close.sh:119` and `tests/test-turn-cap.sh:112` export `DWARVES_KIT_LOG_DIR` for the orchestrate call, so another call path or another test still writes to the real root (not yet located) |
| The escape record exists: an `ACTION` line carrying `escaped-from=<spec-slug>`, written at `/kit:debug` ledger-open | `commands/debug.md:46-49`, `lib/gate/gate-ledger.sh:216-220` (`action` verb, free text), read by `lib/telemetry/lane-telemetry.sh:163-175` (`_escapes`) and printed at `:250-252` and `:311` |
| No miss taxonomy on that record | the marker carries only the spec slug; no reader distinguishes why a review missed it |
| Bench rows carry no rid | `lib/bench/README.md:14-15` (rows join the ledgers by `session_id` only); bench is a model race, so it is excluded from this lens |
| Per-run "verifier or lens dispatch" counts are not recorded as such | the ledger has `GATE`, `OUTCOME`, `TOKENS`, `DEBT`, `ACTION`, `START` line types only (count over the live corpus, 2026-09-29); a dispatch shows up only inside a reason string such as `fresh agents=<N>` (`commands/spec.md:307`) |

Consequence: "dispatches" cannot be counted per run from recorded data. The lens counts gate records, the activity the ledger does hold, and says so. Tokens appear only where a recorded non-fixture value exists.

## Solution

### Approaches considered

| Approach | Description | Tradeoff |
|---|---|---|
| A. Extend `lib/stats` | A `ceremony` report command plus one detector in `anomalies.py`, one new git table for line counts, one new column for the GATE timestamp | One data path, reuses the propose-only pipeline and `--threshold`. Adds a table and a column to a lens that already rebuilds slowly (`stats tables` on the live corpus did not finish inside 120 s on 2026-09-29). |
| B. Extend `lane-telemetry.sh` | Add ceremony counts to `report` in bash and awk | Fast and no new store. Cannot see git (no progress), has no anomaly or propose path, windowing by date in awk is fragile. |

### Chosen approach + why

A for the ceremony numbers and the anomaly, because the anomaly must land where `kit:stats` already proposes them and the progress half needs git. The `gap` tag reader goes into `lane-telemetry.sh`, because that file already owns the escape reader (`_escapes`, `:163`) and adding a second escape parser in Python would fork it. B is rejected for the anomaly, kept for the escape reader.

### Extensibility & boundaries

- Load-bearing dimension: the set of ceremony phases. It is one config list (default: every gate phase except `build`, `implement`, `ship`, `wrap`, `wrap-follow`), so a new gate needs no code change here.
- Units: `ceremony.py` (pure function over query rows, returns per-run and per-window numbers), one detector `_detect_ceremony_share` (thin wrapper), one CLI command `ceremony` (render), one shell reader change (gap tally). Each is testable alone.

## Design

### Picture

```
 run ledgers ----> kit_gates (+ts) ----+
 (GATE/OUTCOME)                        |     window = last 14 days of ledger time
                                       +--> ceremony.py --+--> `stats ceremony` (per-run + window table)
 git log --numstat --> git_lines ------+                  |
 (sha, ts, subject,                                       +--> _detect_ceremony_share --> anomalies
  added, deleted)                                                                          --propose

 /kit:debug --action "escaped-from=<spec> gap=<context|judgment>" --> run ledger
                                       lane-telemetry.sh report: escapes listed + tally by gap
```

### Definitions

- **Ceremony records**: `kit_gates` rows with outcome `ran` or `override` whose gate is in the ceremony list. Reported as two counts, ran and override. `skipped` is counted separately and never enters the share.
- **Ceremony share** = ceremony records / all `ran`+`override` records in the window. It is a share of gate records, never of tokens or time. The report header says so.
- **Catches**: `ran`+`override` rows with `caught = true`. **Known-caught rows**: rows with `caught IS NOT NULL` (an OUTCOME bracket exists). Unknown is never counted as zero.
- **Progress**: lines shipped (added + deleted, from commits with the `(#N)` squash suffix in the window, non-merge) and PRs merged (count of those commits). Window-level by time containment. Per-run progress appears only where the existing rid-in-subject bridge matches (`anomalies.py:243-247` technique); otherwise the cell prints `?`.
- **Window**: the last `ceremony_window_days` (default 14) ending at the latest GATE timestamp in the ledgers, not wall clock, so the result is deterministic for a fixed ledger.
- **Tokens**: a per-run value appears only from a phase-tagged `cost=` (existing pairing, `adapters.py:114`) or a nonzero rid-wide `TOKENS` line, and only for non-excluded rids. Otherwise `?`. Sessions tokens are not attributed to runs.
- **Excluded rids**: names matching `sg-*`, `tier4-fixture*`, `turncap-fixture*` (config list, env `STATS_EXCLUDE_RIDS`, comma separated). The report prints the excluded rids and their START and TOKENS line counts so the exclusion is visible.

### Anomaly rule

Fires (key `ceremony_share`) when all hold over the window: ceremony records >= `ceremony_min_records` (30), known-caught rows >= `ceremony_min_known_caught` (10), catches = 0, share >= `ceremony_share_max` (0.70). The two floors make "zero catches" evidence, not absence of data: a window with no OUTCOME brackets proposes nothing. The detector reads only through `materialize.query`, like every detector in the module (`anomalies.py:6-10`). The proposed title is plain words: "Feedback: most gate work, no problem caught in the window". Progress figures go in the metric string for context; they do not gate the fire, because the run-to-commit bridge is partial and gating on it would silence the anomaly on most repos.

The 0.70 default is a scaffold. The baseline below sets the final default before this spec ships, and the implementation notes record the number chosen and why.

### The gap tag

The escape marker becomes `escaped-from=<spec-slug> gap=<context|judgment>`:

- `context`: the review or gate did not have information that existed elsewhere (a missing input, a file it never saw).
- `judgment`: it had the information and judged wrong.
- Absent, or any other word: the reader prints `unknown`. The reader never guesses.

Emitter: one sentence added to `commands/debug.md:46-49` telling the debugger to add `gap=` when the cause is clear and omit it when not. Reader: `lane-telemetry.sh` `_escapes` (`:163`) also emits the gap, `report` prints it on each escape line and adds one tally line (`escapes by gap: context N, judgment N, unknown N`). Both ship in the same change.

### Boundaries & failure modes

| Failure class | Detection signal | Mitigation |
|---|---|---|
| No OUTCOME brackets in the window | known-caught rows below floor | detector returns nothing; report prints `catches: ? (n known)` |
| GATE line with no parseable timestamp | row `ts` NULL | row is excluded from windowed counts and counted in a printed `no-ts` line |
| `git` missing or repo not the ledger's repo | `git_lines` empty | progress prints `?`; anomaly unaffected (progress does not gate) |
| Ledgers from several repos, one git repo | per-run bridge matches few rids | window progress is labelled with the git repo it read (`STATS_GIT_REPO_DIR`); other repos' ceremony still counts, so the report prints the repo scope of each number |
| A fixture writes into the real ledger again | new rid names outside the exclude list | report prints rids that have START lines and zero GATE lines in a `suspect fixtures` line, so a new leak is visible without a code change |
| Binary file in numstat (`-` counts) | non-integer field | counted as 0 lines, listed in a `binary-files` count, never dropped silently |

## Task Breakdown

### Phase 1: data
- [ ] TASK-A: add `ts` (the GATE line timestamp) as the last column of `KIT_GATES_SCHEMA` and fill it in `read_kit_gates`; update the two schema parity tests. AC: `uv run stats query "SELECT count(*) FROM kit_gates WHERE ts IS NULL"` returns 0 on a fixture with well-formed lines.
- [ ] TASK-B: add `git_lines` (sha, ts, subject, added, deleted; one row per non-merge commit) via `git log --numstat --no-merges`, new schema entry, adapter, materialize load. AC: on a generated repo with a known 3-line and 5-line commit, the table holds 3 and 5.
- [ ] TASK-C: rid exclusion list (`STATS_EXCLUDE_RIDS`, default the three globs) in `config.py`, applied in the ceremony code and to rid-wide token reads. AC: a fixture `sg-9` ledger with `TOKENS in=10` does not change the per-run token cell.

### Phase 2: lens
- [ ] TASK-D: `lib/stats/src/stats/ceremony.py` (per-run rows, window summary) and the `ceremony` CLI command with `--json`. AC: see Acceptance criteria 1 and 2.
- [ ] TASK-E: `_detect_ceremony_share` in `anomalies.py`, four new `DEFAULTS` keys, entry in `DETECTORS`. AC: criteria 3 and 4.

### Phase 3: gap tag
- [ ] TASK-F: `_escapes` emits `gap`; `report` prints it and the tally; `commands/debug.md` line added. AC: criterion 5.

### Phase 4: baseline and docs
- [ ] TASK-G: run the lens over the live ledgers and commit `docs/verification/ceremony-lens/baseline.md` (see criterion 6). Add a `ceremony` row to `skills/stats/SKILL.md` and the `lib/stats/README.md` table list. AC: criterion 7.

## After state

- [ ] `uv run stats ceremony` prints a per-run table and a window summary with ceremony records, share, catches, known-caught rows, lines shipped, PRs merged; every unrecorded value prints `?`. (Today: no such command.)
- [ ] `uv run stats anomalies` can fire `ceremony_share`. (Today: only the per-gate `ceremony` detector exists.)
- [ ] An escape marker with `gap=` is read and tallied by `lane-telemetry.sh report`. (Today: the marker carries no reason class.)
- [ ] A committed baseline report exists that later specs cite. (Today: the dispatch and token claims in the research note are estimates.)

## Acceptance Criteria (global)

Each row has an exact command. Tests run against fixtures pointed at temp dirs, never the real ledger.

| # | Criterion | Verification command |
|---|---|---|
| 1 | `ceremony` counts ran, override, skipped, share, catches and known-caught per window from a fixture ledger; unknown stays `?` | `bash lib/stats/tests/test-ceremony-lens.sh` (cases C-counts, C-unknown) |
| 2 | Progress comes from `git_lines` by time containment; a commit outside the window is not counted | same script, case C-progress |
| 3 | High ceremony and zero known catches fires `ceremony_share` | same script, case A-fire |
| 4 | Negative controls: one catch does not fire; no OUTCOME brackets does not fire; below-floor volume does not fire | same script, cases A-one-catch, A-unknown, A-thin |
| 5 | `gap=context` and `gap=judgment` are read and tallied; missing or invalid reads `unknown` | `bash tests/test-hooks.sh` (new block "escape gap tally") |
| 6 | The baseline report exists and states the window, excluded rids, share by week, catches, known-caught count, lines, PRs, gap tally, and the chosen threshold | `test -s docs/verification/ceremony-lens/baseline.md && grep -c '^| ' docs/verification/ceremony-lens/baseline.md` (>= 8 table rows) |
| 7 | The baseline reproduces from the lens, not by hand | `cd lib/stats && uv run stats ceremony --json` output matches the numbers in the baseline table (spot check three cells, recorded in the proof) |
| 8 | Fixture rids never enter a total | `bash lib/stats/tests/test-ceremony-lens.sh` case X-exclude; `uv run stats ceremony` on the live corpus prints the excluded rids with their START and TOKENS counts |
| 9 | Existing suites stay green | `bash tests/test-meta.sh && bash tests/test-hooks.sh && bash lib/stats/tests/test-anomalies-advisor.sh && bash lib/stats/tests/test-schema-parity.sh && bash lib/stats/tests/test-schema-conform.sh` |

## Verification

`bash lib/stats/tests/test-ceremony-lens.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh && bash lib/stats/tests/test-anomalies-advisor.sh && bash lib/stats/tests/test-schema-parity.sh && bash lib/stats/tests/test-schema-conform.sh`

## Test plan

Fixture harness copied from `lib/stats/tests/test-anomalies-advisor.sh` (env vars `DWARVES_KIT_LOG_DIR`, `STATS_GIT_REPO_DIR`, `STATS_SESSIONS_DIR` and the rest point at a temp dir; a generated git repo with controlled commit dates). One rebuild per case.

| Case | Setup | Expected |
|---|---|---|
| A-fire | window of 14 days, 40 ceremony `ran` records across 8 rids, 12 with OUTCOME `caught=false`, 0 `caught=true`, share 0.8 | `anomalies` fires `ceremony_share`; metric shows records 40, known 12, caught 0 |
| A-one-catch (negative control) | identical fixture, one OUTCOME end flipped to `caught=true` | does NOT fire |
| A-unknown | identical volume, no OUTCOME lines at all | does NOT fire; report prints `catches: ? (0 known)` |
| A-thin | 20 ceremony records, 12 known, 0 caught | does NOT fire (below `ceremony_min_records`) |
| A-share-low | 40 records but 25 are `build` and `ship`, share 0.37, 0 caught | does NOT fire |
| C-counts | mixed `ran`, `override`, `skipped` rows | ran, override, skipped counted separately; skipped absent from share |
| C-unknown | rid with no TOKENS and no cost | token cell is `?`, not 0 |
| C-progress | three commits, two inside the window (one with `(#12)`), one outside | lines and PR count reflect the two |
| X-exclude | ledgers `sg-9` (START and `TOKENS in=10`, no GATE) and `turncap-fixture` beside a real rid | totals unchanged; both listed under excluded with counts |
| X-suspect | a new rid `zz-leak` with START and no GATE | listed on the `suspect fixtures` line |
| G-gap | escape ACTION lines with `gap=context`, `gap=judgment`, none, `gap=banana` | tally context 1, judgment 1, unknown 2 |

Negative control by mutation: change the detector to skip the `caught = 0` clause. A-one-catch must go red. Restore, green.

## Edge Cases

1. A window with zero GATE records: `ceremony` prints an honest empty state, the detector returns nothing, exit code 0.
2. Override records: counted as ceremony activity (a waved gate is gate work that produced nothing) and shown as their own column so a reader can see waved versus run.
3. A rid whose gate names are not in the ceremony list and not in the progress list (a new gate phase): counted as ceremony by default, because the list names the exceptions.
4. Two rids from different repos in one ledger root: ceremony counts both, progress is labelled with the one repo git read.
5. Clock skew: a GATE timestamp in the future extends the window end; the report prints the window bounds so a skew is visible.

## Failure modes

See `### Boundaries & failure modes` under Design.

## Out of Scope

- Cutting or sampling any gate (SPEC-369 whole-spec dispatch owns the cut; this spec only measures).
- Lane definitions, `lane-classify.sh`, `WORKFLOW.md` (SPEC-368).
- A live view of who owns what (SPEC-366).
- Attributing session tokens to runs by time containment. It is a bridge the `digest` command already approximates; building it here would import that approximation into a gating number. Tokens stay counts until a run records its own.
- Bench rows (no rid, model race).
- Finding and fixing the call path that still leaks fixture ledgers into the real root. Named here, excluded at read time, not fixed: the leaking tests live under `tests/`, which sibling specs also touch. Open question below.
- A per-dispatch record in the ledger (a new emitter for verifier and lens dispatches). Worth a separate spec if the gate-record proxy proves too coarse.

## Touches

- lib/stats/**
- lib/telemetry/**
- skills/stats/**
- docs/verification/ceremony-lens/**

Also edited, outside the disjoint-prefix form and lead-owned at convergence: one sentence in `commands/debug.md` (the emitter half of the gap tag). `commands/**` is not listed because SPEC-369 owns `commands/execute.md`. Also `tests/test-hooks.sh` (one new block, criterion 5), the same reason for not listing `tests/**`.

## Decision Log

- DEC-A: the anomaly gates on ceremony share, zero known catches, and two volume floors; progress is reported but does not gate. Reason: the rid-to-git bridge is partial, and gating on it would silence the anomaly. Rejected: gating on ceremony per line shipped (silent on unbridged repos).
- DEC-B: share is of gate records, not tokens or time. Reason: per-run tokens are unrecorded for real runs (one `TOKENS` line in the live corpus outside fixtures), and bracket durations exist only for a few gates. Rejected: a token share filled by estimate (violates unknown-stays-unknown).
- DEC-C: new key `ceremony_share`, not an edit of `_detect_ceremony`. Reason: the existing detector answers a different question (one gate that never mattered) and has its own tests (`test-anomalies-advisor.sh`).
- DEC-D: the marker field is `gap=` (key=value, the ledger's convention, `lane-telemetry.sh:20`), the concept name in prose is "gap". Reason: every other marker in the ledger is key=value.
- DEC-E: add a `ts` column to `kit_gates` rather than window by run count. Reason: `kit_runs` windows by rid order would need first_ts joins for a per-gate share; the GATE line already has a timestamp that the adapter drops.
- DEC-F: classified `normal`. The change is additive (an appended column, a new derived table rebuilt on every call, one appended marker key that existing readers ignore) and touches no hook, gate decision, or persisted schema. `lib/` work owes the multi-lens review per `AGENTS.md`, so the build runs `/kit:review-team`. If the operator reads the extra column as a data-model change, the lane becomes `full`.

## Spec gate

`bash lib/classify/lane-classify.sh classify "<task>"` returned `normal` (2026-09-29). Normal-lane plan (`gate-ledger.sh plan normal`): grill, think, spec, validate, design-record, test-plan, build, review, docs, ship. This spec is the `spec` gate; `validate` is next (a fresh-context validator per `commands/spec.md` step 5, never the writer).

## Grounding

Live samples taken read-only on 2026-09-29:

- Line types in `~/.local/state/dwarves-kit/logs/runs/*.log`: `GATE 933, OUTCOME 459, START 431, TOKENS 126, DEBT 10, ACTION 2` (`awk -F' [|] ' '{print $2}' | sort | uniq -c`).
- Fixture share: `cat sg-*.log tier4-fixture*.log turncap-fixture.log | awk ...` gave `START 392, TOKENS 125` and no other line type.
- Gate records: 786 `ran`+`override` GATE lines; `ship` had 60 OUTCOME ends with 18 `caught=true`, `validate` 52 ends with 31 (raw awk, includes duplicates from re-runs; the lens will pair by FIFO like `read_kit_gates`, so its numbers differ slightly, for example `kit_gates` showed `ship` 87 rows, 27 known, 13 caught on the same day).
- `lane-classify.sh classify` output: `normal`.
- Negative-control dry trace: mutation = drop the `caught_true = 0` clause in `_detect_ceremony_share`; A-one-catch reads the fixture with one `caught=true`; the mutated code fires; case A-one-catch asserts no fire, so it goes red.

## Open questions

- Which call path still writes `sg-*`, `tier4-fixture*`, `turncap-fixture` into the real ledger root? Both tests export `DWARVES_KIT_LOG_DIR`, yet the files were touched today. A snapshot-diff run of `tests/test-tier4-close.sh`, `tests/test-turn-cap.sh` and `tests/test-orchestrate-hardening.sh` (the rid `sg-01` comes from `**Branch:** feat/sg-01` in the last one, line 252) would find it. Left to the operator because those files sit in `tests/`.
- Default `ceremony_share_max`: the live corpus share of ceremony records is about 0.77 (roughly 600 of 786 ran+override records, by phase counts), so 0.70 is always over the line and the zero-catch clause does the discriminating. Set the final default from the baseline.
