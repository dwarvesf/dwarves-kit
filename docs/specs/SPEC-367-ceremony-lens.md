# Spec: ceremony lens (gate work and subagent dispatches versus progress and catches)

Generated: 2026-09-29
Status: SHIPPED (#831)
Lane: normal
References: `lib/stats/src/stats/anomalies.py` (the `_detect_ceremony` floor-and-fire shape, `DEFAULTS`, `--threshold`), `lib/stats/tests/test-anomalies-advisor.sh` (fixture harness: env vars point every source at a temp dir, a real end-to-end rebuild, a negative control per detector)
Source: `docs/research/2026-09-29-openrig-absorption.md`, design D5 and the "Operator hypothesis, tested" table
Revision: round 2 after validator NEEDS REVISION (dispatch and token measurement added and owned here; explicit windows; bounded git read; casefolded phases; gap tag removed; fixture-leak answer recorded)

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
| The pollution is live, not historic, and the source is known | mtime of `sg-01.log` and `tier4-fixture.log` is 2026-09-29 19:21 and 19:22. Answer: `tests/test-orchestrate-hardening.sh`, `tests/test-orchestrate-gate-dispatch.sh` and `tests/test-model-routing.sh` do not set `DWARVES_KIT_LOG_DIR` (their goal files name `feat/sg-01` and `feat/sg-one`). That fix ships as its own separate change, not here |
| No `escaped-from=` marker exists in the live ledgers | 0 hits across `~/.local/state/dwarves-kit/logs/runs/*.log` (2026-09-29), so a gap tag has nothing to tag; dropped (Out of scope) |
| The lens as first drafted was blind to per-task work: a run leaves ONE `build ran` record whatever the task count | `commands/execute.md:485` (`record <rid> build ran "tasks=<N>/<N> verified=<N> tests=<pass|fail>"`); per-task workers, verifiers and rechecks write no GATE line, so SPEC-369's cut would not move a gate-record share |
| Claude Code keeps every subagent's transcript, with type, description and per-message usage | `~/.claude/projects/<slug>/<session>/subagents/agent-<id>.meta.json` holds `agentType`, `description`, `toolUseId`, `spawnDepth`; `agent-<id>.jsonl` holds messages with `timestamp` and `message.usage` (live sample below) |
| Usage repeats per streamed message | in the sampled file 2 message ids appear on two lines each with different `output_tokens` (5 then 290); summing every line double counts, so the reader takes the LAST line per `message.id` |
| Subagent transcripts are retained about 27 days here | oldest `subagents/` file on disk is 2026-09-02 (75 session dirs with a `subagents/` folder); `cleanupPeriodDays` is not set in `~/.claude/settings.json`, so the app default applies (30 days, from the Claude Code docs, not verified on this host). History older than that is unrecoverable, the baseline says so |
| The lead session often runs from another repo | a dispatch's transcript sits under the LEAD session's project slug (for example ops-toolkit), not the ledger's repo, so the join must not use `gitBranch` or `cwd` |
| Sessions reader keeps numbers only, never message text | `adapters.py:612-618` field whitelist; the subagent reader keeps the same rule (see Definitions) |
| Bench rows carry no rid | `lib/bench/README.md:14-15` (rows join the ledgers by `session_id` only); bench is a model race, so it is excluded from this lens |
| Per-run "verifier or lens dispatch" counts are not recorded as such | the ledger has `GATE`, `OUTCOME`, `TOKENS`, `DEBT`, `ACTION`, `START` line types only (count over the live corpus, 2026-09-29); a dispatch shows up only inside a reason string such as `fresh agents=<N>` (`commands/spec.md:307`) |

Consequence: the ledger cannot count dispatches, but the transcripts can. This spec owns that measurement: gate records for the anomaly, subagent dispatches and their tokens (read from transcripts) for the per-run report, so SPEC-369's cut is visible as dispatches per task. Tokens appear only where a recorded value exists.

**Baseline method (operator decision).** The before and after comparison does not wait for organic tagged runs. It is an A/B run of ONE fixture spec through the old spine (master before SPEC-369) and the new spine, both dispatches tagged with `rid=<rid>` by the `feat/dispatch-rid-tag` change, both read by this lens's reader. The historical time-window fallback stays as best-effort context only and never feeds the comparison.

## Solution

### Approaches considered

| Approach | Description | Tradeoff |
|---|---|---|
| A. Extend `lib/stats` | A `ceremony` report command plus one detector in `anomalies.py`, a `git_lines` table, a `subagent_runs` table read from transcripts, one new column for the GATE timestamp | One data path, reuses the propose-only pipeline and `--threshold`. Adds two tables and a column to a lens that already rebuilds slowly (`stats tables` on the live corpus did not finish inside 120 s on 2026-09-29), so both new reads are bounded by the window start (Definitions). |
| B. Extend `lane-telemetry.sh` | Add ceremony counts to `report` in bash and awk | Fast and no new store. Cannot see git (no progress), has no anomaly or propose path, windowing by date in awk is fragile. |

### Chosen approach + why

A, because the anomaly must land where `kit:stats` already proposes them, and the progress and transcript halves need git and JSON reads that awk cannot do safely. B is rejected.

### Extensibility & boundaries

- Load-bearing dimension: the set of ceremony phases. It is one config list (default: every gate phase except `build`, `implement`, `ship`, `wrap`, `wrap-follow`), so a new gate needs no code change here.
- Units: `ceremony.py` (pure function over query rows, returns per-run and per-window numbers), `subagents` adapter (transcripts to `subagent_runs`), one detector `_detect_ceremony_share` (thin wrapper), one CLI command `ceremony` (render). Each is testable alone.

## Design

### Picture

```
 run ledgers ----> kit_gates (+ts) -------+
 (GATE/OUTCOME)                           |   window = --from/--to, else last 14 days
                                          |   of ledger time
 git log --since=<window start> --numstat |
   --> git_lines ---------------------------+--> ceremony.py --+--> `stats ceremony` (per-run + window)
                                          |                    |
 ~/.claude/projects/*/*/subagents/        |                    +--> _detect_ceremony_share --> anomalies
   *.meta.json + *.jsonl (mtime >= start) |                                                       --propose
   --> subagent_runs (rid= tag, else      |
       build-bracket time window) --------+
```

### Definitions

- **Ceremony records**: `kit_gates` rows with outcome `ran` or `override` whose gate is in the ceremony list. Reported as two counts, ran and override. `skipped` is counted separately and never enters the share.
- **Ceremony share** = ceremony records / all `ran`+`override` records in the window. It is a share of gate records, never of tokens or time. The report header says so.
- **Catches**: `ran`+`override` rows with `caught = true`. **Known-caught rows**: rows with `caught IS NOT NULL` (an OUTCOME bracket exists). Unknown is never counted as zero.
- **Progress**: lines shipped (added + deleted, from commits with the `(#N)` squash suffix in the window, non-merge, read with `--since`) and PRs merged (count of those commits). Window-level by time containment. Per-run progress appears only where the existing rid-in-subject bridge matches (`anomalies.py:243-247` technique); otherwise the cell prints `?`.
- **Window**: by default the last `ceremony_window_days` (14) ending at the latest GATE timestamp in the ledgers, not wall clock, so the result is deterministic for a fixed ledger. Explicit bounds override it so before and after runs compare: `stats ceremony --from <iso> --to <iso>`, or `--since-sha <sha>` (window start = that commit's timestamp, end = `--to` or the ledger end). The anomaly always uses the default window.
- **Casefolded phases**: every gate name is lowercased and trimmed before the ceremony-list match and before grouping (`Ship` and `ship` are one gate). The writer already lowercases (`gate-ledger.sh:114`); the read side does not trust that for old or hand-written lines.
- **Bounded reads**: `git log` runs with `--since=<window start>`, never full history; transcript files older than the window start (by mtime) are not opened. Both are needed because the lens rebuild already exceeds 120 s.
- **Dispatch**: one subagent transcript. Counted per rid by `agentType` (`kit:task-verifier`, `kit:recheck-verifier`, `general-purpose`, and so on). Model is read from the meta file when present, else `?`.
- **Dispatch to rid join**, in order: (1) a `rid=<rid>` token in the meta `description` (convention going forward: every Agent dispatch description carries it; the emitter is the separate change on branch `feat/dispatch-rid-tag`, which edits `commands/execute.md` and `commands/spec.md`; this spec documents the convention in `lib/stats/README.md` and reads it, and edits neither command file); (2) for history, time containment: the dispatch's first message timestamp falls inside that rid's `OUTCOME build start` to `end` bracket, and only if exactly one bracket contains it (two overlapping rids make it `ambiguous`, counted, never assigned); (3) otherwise `unattributed`. Never joined on `gitBranch` or `cwd`. Each dispatch row carries `rid_source` = `tag`, `window`, `ambiguous` or `none`, and the report prints the count of each. Only 8 of 85 live `build` rows have a bracket today, so the fallback covers little history; the report says that.
- **Dispatch tokens**: input, output, cache-read and cache-creation summed from the transcript's `message.usage`, LAST line per `message.id`. Per-run tokens are the sum over that run's attributed dispatches, printed with the count of attributed dispatches beside it, `?` when none.
- **Normalization**: dispatches per task and tokens per task, with N from `tasks=<N>` in the run's `build ran` reason (`commands/execute.md:485`); `?` when the reason has no `tasks=`.
- **Privacy**: the transcript reader keeps numbers, timestamps, `agentType`, model, and the extracted `rid` token only. It stores no description text and no message content, the same rule as the sessions reader (`adapters.py:612-618`).
- **Excluded rids**: names matching `sg-*`, `tier4-fixture*`, `turncap-fixture*` (config list, env `STATS_EXCLUDE_RIDS`, comma separated). The report prints the excluded rids and their START and TOKENS line counts so the exclusion is visible.

### Anomaly rule

Fires (key `ceremony_share`) when all hold over the window: ceremony records >= `ceremony_min_records` (30), known-caught rows >= `ceremony_min_known_caught` (10), catches = 0, share >= `ceremony_share_max` (0.70). The two floors make "zero catches" evidence, not absence of data: a window with no OUTCOME brackets proposes nothing. The detector reads only through `materialize.query`, like every detector in the module (`anomalies.py:6-10`). The proposed title is plain words: "Feedback: most gate work, no problem caught in the window". Progress, dispatch and token figures go in the metric string for context; they do not gate the fire, because the run-to-commit bridge is partial and gating on it would silence the anomaly on most repos.

The 0.70 default is a scaffold. The baseline below sets the final default before this spec ships, and the implementation notes record the number chosen and why.

### Boundaries & failure modes

| Failure class | Detection signal | Mitigation |
|---|---|---|
| No OUTCOME brackets in the window | known-caught rows below floor | detector returns nothing; report prints `catches: ? (n known)` |
| GATE line with no parseable timestamp | row `ts` NULL | row is excluded from windowed counts and counted in a printed `no-ts` line |
| `git` missing or repo not the ledger's repo | `git_lines` empty | progress prints `?`; anomaly unaffected (progress does not gate) |
| Transcripts pruned before the window | oldest `subagents/` mtime later than window start | report prints `transcripts: earliest <date>`; dispatch and token cells before it print `?` |
| A dispatch description has no `rid=` and no unique bracket | `rid_source` = `none` or `ambiguous` | counted and printed, never assigned |
| A `subagents/` dir with a malformed meta or jsonl line | JSON parse error | that file is skipped and counted in `skipped-files`; siblings unaffected |
| Ledgers from several repos, one git repo | per-run bridge matches few rids | window progress is labelled with the git repo it read (`STATS_GIT_REPO_DIR`); other repos' ceremony still counts, so the report prints the repo scope of each number |
| A fixture writes into the real ledger again | new rid names outside the exclude list | report prints rids that have START lines and zero GATE lines in a `suspect fixtures` line, so a new leak is visible without a code change |
| Binary file in numstat (`-` counts) | non-integer field | counted as 0 lines, listed in a `binary-files` count, never dropped silently |

## Task Breakdown

### Phase 1: data
- [ ] TASK-A: add `ts` (the GATE line timestamp) as the last column of `KIT_GATES_SCHEMA` and fill it in `read_kit_gates`; update the two schema parity tests. AC: `uv run stats query "SELECT count(*) FROM kit_gates WHERE ts IS NULL"` returns 0 on a fixture with well-formed lines.
- [ ] TASK-B: add `git_lines` (sha, ts, subject, added, deleted; one row per non-merge commit) via `git log --since=<window start> --numstat --no-merges`. AC: on a generated repo, a commit before the window start is absent and a 3-line and a 5-line commit inside it read 3 and 5.
- [ ] TASK-C: rid exclusion list (`STATS_EXCLUDE_RIDS`, default the three globs) in `config.py`, applied in the ceremony code. AC: a fixture `sg-9` ledger does not change any total.
- [ ] TASK-D: `subagent_runs` table (rid, session, agent_id, agent_type, model, first_ts, last_ts, input, output, cache_read, cache_creation, rid_source) from `<STATS_SESSIONS_DIR>/*/*/subagents/`, mtime-bounded, last-line-per-message-id usage, numbers only. AC: criteria 5 and 6.

### Phase 2: lens
- [ ] TASK-E: `lib/stats/src/stats/ceremony.py` (per-run rows, window summary, casefold, normalization) and the `ceremony` CLI command with `--json`, `--from`, `--to`, `--since-sha`. AC: criteria 1, 2, 7.
- [ ] TASK-F: `_detect_ceremony_share` in `anomalies.py`, four new `DEFAULTS` keys, entry in `DETECTORS`. AC: criteria 3 and 4.

### Phase 3: baseline and docs
- [ ] TASK-G: run the lens over the live ledgers and transcripts and commit `docs/verification/ceremony-lens/baseline.md` (criterion 8). Document the `rid=<rid>` dispatch-description convention in `lib/stats/README.md` and add a `ceremony` row to `skills/stats/SKILL.md`. AC: criteria 8 and 9.

## After state

- [ ] `uv run stats ceremony` prints a per-run table and a window summary with ceremony records, share, catches, known-caught rows, lines shipped, PRs merged; every unrecorded value prints `?`. (Today: no such command.)
- [ ] `uv run stats anomalies` can fire `ceremony_share`. (Today: only the per-gate `ceremony` detector exists.)
- [ ] `uv run stats ceremony` shows subagent dispatches by `agentType`, tokens, and dispatches per task for each run, with the join source counted. (Today: per-task workers, verifiers and rechecks are invisible; one `build ran` line per run.)
- [ ] `stats ceremony --from A --to B` and `--since-sha S` compare two windows. (Today: no window control.)
- [ ] A committed baseline report exists that later specs cite. (Today: the dispatch and token claims in the research note are estimates.)

## Acceptance Criteria (global)

Each row has an exact command. Tests run against fixtures pointed at temp dirs, never the real ledger.

| # | Criterion | Verification command |
|---|---|---|
| 1 | `ceremony` counts ran, override, skipped, share, catches and known-caught per window from a fixture ledger; unknown stays `?` | `bash lib/stats/tests/test-ceremony-lens.sh` (cases C-counts, C-unknown) |
| 2 | Progress comes from `git_lines` by time containment; a commit outside the window is not counted | same script, case C-progress |
| 3 | High ceremony and zero known catches fires `ceremony_share` | same script, case A-fire |
| 4 | Negative controls: one catch does not fire; no OUTCOME brackets does not fire; below-floor volume does not fire | same script, cases A-one-catch, A-unknown, A-thin |
| 5 | Dispatches are counted per rid by `agentType`; a `rid=` tag attributes, one containing build bracket attributes, two brackets give `ambiguous`, none gives `none` | `bash lib/stats/tests/test-ceremony-lens.sh` (cases S-tag, S-window, S-ambiguous, S-none) |
| 6 | Tokens sum the LAST usage line per message id, come only from attributed dispatches, and print `?` when none | same script, cases S-tokens, S-unknown |
| 7 | Windows: `--from/--to` and `--since-sha` bound the counts; git is read with `--since`; phase names casefold | same script, cases W-range, W-sha, W-bounded, F-casefold |
| 8 | The baseline report exists and states window, excluded rids, transcript retention (earliest transcript date), share by week, catches, known-caught count, lines, PRs, dispatches by `agentType`, tokens with attributed-dispatch counts, join-source counts, and the chosen threshold | `test -s docs/verification/ceremony-lens/baseline.md && grep -c '^| ' docs/verification/ceremony-lens/baseline.md` (>= 10 table rows) |
| 8b | The A/B baseline: one fixture spec run through the old spine and the new spine, each under its own rid, both tagged; `stats ceremony` reports dispatches by `agentType`, tokens, and dispatches per task for both, `rid_source=tag` for every dispatch | `cd lib/stats && uv run stats ceremony --json` (two rids, all dispatches `tag`) recorded in `docs/verification/ceremony-lens/baseline.md` |
| 9 | The baseline reproduces from the lens, not by hand | `cd lib/stats && uv run stats ceremony --json` output matches the baseline table (three cells spot-checked, recorded in the proof) |
| 10 | Fixture rids never enter a total; the live corpus run prints excluded rids with START and TOKENS counts | `bash lib/stats/tests/test-ceremony-lens.sh` case X-exclude; `cd lib/stats && uv run stats ceremony` |
| 11 | Existing suites stay green | `bash tests/test-meta.sh && bash tests/test-hooks.sh && bash lib/stats/tests/test-anomalies-advisor.sh && bash lib/stats/tests/test-schema-parity.sh && bash lib/stats/tests/test-schema-conform.sh` |

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
| S-tag | fixture `subagents/` with 3 dispatches whose meta description holds `rid=r1` (two `kit:task-verifier`, one `general-purpose`), in a session dir under a DIFFERENT project slug than the ledger repo | r1 shows 2 verifier, 1 general-purpose, `rid_source=tag` |
| S-window | 1 dispatch with no tag, first message inside r2's only build bracket | attributed to r2, `rid_source=window` |
| S-ambiguous | 1 untagged dispatch inside two overlapping build brackets | counted `ambiguous`, in no rid |
| S-none | 1 untagged dispatch outside every bracket | `rid_source=none`, in no rid |
| S-tokens | one message id on two lines, `output_tokens` 5 then 290 | run total uses 290, not 295 |
| S-unknown | run with no attributed dispatch | token and dispatch cells `?`, not 0 |
| S-per-task | `build ran "tasks=4/4 ..."` and 8 attributed dispatches | 2.0 dispatches per task; a reason without `tasks=` prints `?` |
| W-range | gates on days 1 to 30, `--from` day 10 `--to` day 20 | only days 10 to 20 counted |
| W-sha | a commit at day 15, `--since-sha` that commit | window starts at its timestamp |
| W-bounded | a commit older than the window start | absent from `git_lines`; a transcript file older than the start (mtime) is not opened |
| F-casefold | gate rows `Ship` and `ship`, `Build` and `build` | one `ship`, one `build`; `Build` not counted as ceremony |

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
- Attributing the lead session's own tokens (only subagent dispatches are attributed; the lead's usage stays in the `sessions` table with no rid).
- Bench rows (no rid, model race).
- The fixture-leak fix. The source is known: `tests/test-orchestrate-hardening.sh`, `tests/test-orchestrate-gate-dispatch.sh` and `tests/test-model-routing.sh` do not set `DWARVES_KIT_LOG_DIR`. It ships as its own separate change. This spec keeps only the read-time exclusion.
- The gap tag (`gap=context|judgment` on escape records). No `escaped-from=` marker exists in the live ledgers (0 hits, 2026-09-29), so there is nothing to tag or read. Revisit when escapes occur.
- Editing `commands/execute.md` or `commands/spec.md`. This spec documents and reads the `rid=<rid>` dispatch-description convention; the separate `feat/dispatch-rid-tag` change owns the tag in both files.

## Touches

- lib/stats/**
- skills/stats/**
- docs/verification/ceremony-lens/**

No file outside these prefixes is edited: the emitter half of the dropped gap tag (`commands/debug.md`, `tests/test-hooks.sh`) is gone, and `commands/execute.md` and `commands/spec.md` belong to the separate `feat/dispatch-rid-tag` change.

## Decision Log

- DEC-A: the anomaly gates on ceremony share, zero known catches, and two volume floors; progress is reported but does not gate. Reason: the rid-to-git bridge is partial, and gating on it would silence the anomaly. Rejected: gating on ceremony per line shipped (silent on unbridged repos).
- DEC-B: the anomaly's share is of gate records, not tokens or time. Reason: ledger tokens are unrecorded for real runs (one `TOKENS` line in the live corpus outside fixtures), transcripts reach back only about 27 days, and bracket durations exist only for a few gates. Dispatches and transcript tokens are reported per run, not used to fire. Rejected: a token share filled by estimate (violates unknown-stays-unknown).
- DEC-C: new key `ceremony_share`, not an edit of `_detect_ceremony`. Reason: the existing detector answers a different question (one gate that never mattered) and has its own tests (`test-anomalies-advisor.sh`).
- DEC-D: the lens owns dispatch and token measurement, read from transcripts, because the ledger cannot see per-task work (`commands/execute.md:485`). Join key `rid=<rid>` in the dispatch description, time-window fallback for history. Rejected: joining on `gitBranch` or `cwd` (the lead often runs from another repo), and adding a new ledger emitter per dispatch (needs a hook change and still misses history).
- DEC-D2: the gap tag is dropped (no escape markers exist to tag).
- DEC-E: add a `ts` column to `kit_gates` rather than window by run count. Reason: `kit_runs` windows by rid order would need first_ts joins for a per-gate share; the GATE line already has a timestamp that the adapter drops.
- DEC-F: classified `normal`. The change is additive (an appended column, a new derived table rebuilt on every call, one appended marker key that existing readers ignore) and touches no hook, gate decision, or persisted schema. `lib/` work owes the multi-lens review per `AGENTS.md`, so the build runs `/kit:review-team`. The transcript reader touches `~/.claude/projects` read-only, numbers only, so the privacy pause in `AGENTS.md` zone 4 is met by the field whitelist. If the operator reads the extra column as a data-model change, the lane becomes `full`.

## Spec gate

`bash lib/classify/lane-classify.sh classify "<task>"` returned `normal` (2026-09-29). Normal-lane plan (`gate-ledger.sh plan normal`): grill, think, spec, validate, design-record, test-plan, build, review, docs, ship. This spec is the `spec` gate; `validate` is next (a fresh-context validator per `commands/spec.md` step 5, never the writer).

## Grounding

Live samples taken read-only on 2026-09-29:

- Line types in `~/.local/state/dwarves-kit/logs/runs/*.log`: `GATE 933, OUTCOME 459, START 431, TOKENS 126, DEBT 10, ACTION 2` (`awk -F' [|] ' '{print $2}' | sort | uniq -c`).
- Fixture share: `cat sg-*.log tier4-fixture*.log turncap-fixture.log | awk ...` gave `START 392, TOKENS 125` and no other line type.
- Gate records: 786 `ran`+`override` GATE lines; `ship` had 60 OUTCOME ends with 18 `caught=true`, `validate` 52 ends with 31 (raw awk, includes duplicates from re-runs; the lens will pair by FIFO like `read_kit_gates`, so its numbers differ slightly, for example `kit_gates` showed `ship` 87 rows, 27 known, 13 caught on the same day).
- Transcript sample (`~/.claude/projects/<slug>/<session>/subagents/`): meta file `{"agentType":"kit:devops-triage","description":"Devops triage for spec070-drill-crit","toolUseId":...,"spawnDepth":1}`; jsonl assistant lines carry `timestamp`, `message.id`, `message.usage`; 2 message ids repeat with `output_tokens` 5 then 290 and 2 then 274 (`jq` over `agent-a0eec4cd37b99586f.jsonl`). This meta file has no `model` key, hence `?` when absent. 75 session dirs hold a `subagents/` folder; the oldest file is dated 2026-09-02; `cleanupPeriodDays` is unset.
- `grep -h escaped-from ~/.local/state/dwarves-kit/logs/runs/*.log | wc -l` returned 0.
- `commands/execute.md:485` records one `build ran "tasks=<N>/<N> ..."` line per run. The gate writer lowercases phases (`gate-ledger.sh:114`).
- `lane-classify.sh classify` output: `normal`.
- Negative-control dry trace: mutation = drop the `caught_true = 0` clause in `_detect_ceremony_share`; A-one-catch reads the fixture with one `caught=true`; the mutated code fires; case A-one-catch asserts no fire, so it goes red.

## Open questions

- Default `ceremony_share_max`: the live corpus share of ceremony records is about 0.77 (roughly 600 of 786 ran+override records, by phase counts), so 0.70 is always over the line and the zero-catch clause does the discriminating. Set the final default from the baseline.
- Transcript retention is inferred (oldest file 2026-09-02, `cleanupPeriodDays` unset, default 30 days from docs). The baseline prints the actual earliest transcript date, which replaces the inference.
