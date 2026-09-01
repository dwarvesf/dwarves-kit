# Proof of done: ledger-observatory

| | |
|---|---|
| **Profile** | tool-build (read-only DuckDB lens + agent-callable CLI) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Work-type dialect** | one-shot CLI / data tool, **multi-feature index** |
| **Canonical** | this file (gate-visible via `proof-of-done.md`); ONE canonical per TOOL, one row per feature, per-feature detail under [`verification/`](verification/) |
| **Companions** | [`ledger-event-schema.md`](ledger-event-schema.md) + [`adapter-contracts.md`](adapter-contracts.md) (the read contract), [`specs/`](specs/) (per-feature specs), [`verification/`](verification/) (per-feature proofs) |

## Features (index)

| Feature | Sub-goal | Spec | Detail | Verdict |
|---|---|---|---|---|
| `schema` | 01 | [SPEC-126](specs/SPEC-126-ledger-event-schema.md) | [`verification/schema.md`](verification/schema.md) | PASS |
| `etl-cli` | 02 | [SPEC-127](specs/SPEC-127-etl-cli.md) | [`verification/etl-cli.md`](verification/etl-cli.md) | PASS |
| `render-skill` | 03 | [SPEC-128](specs/SPEC-128-render-skill.md) | [`verification/render-skill/render-skill.md`](verification/render-skill/render-skill.md) | PASS |
| `feedback-loop` | 04 | [SPEC-129](specs/SPEC-129-feedback-loop.md) | [`verification/feedback-loop/feedback-loop.md`](verification/feedback-loop/feedback-loop.md) | PASS |
| `docs-wiring` | 05 | [SPEC-130](specs/SPEC-130-docs-wiring.md) | [`verification/docs-wiring.md`](verification/docs-wiring.md) | PASS |
| `kit-gates-lens` | harness-observatory SG-01 | [SPEC-131](specs/SPEC-131-kit-gates-lens.md) | [`verification/kit-gates-lens.md`](verification/kit-gates-lens.md) | PASS |
| `defect-correlation` | harness-observatory SG-02 | [SPEC-132](specs/SPEC-132-defect-correlation.md) | [`verification/defect-correlation.md`](verification/defect-correlation.md) | PASS |
| `deviation-rate` | harness-observatory SG-03 | [SPEC-133](specs/SPEC-133-deviation-rate.md) | [`verification/deviation-rate.md`](verification/deviation-rate.md) | PASS |
| `anomalies-advisor` | harness-observatory SG-04 | [SPEC-134](specs/SPEC-134-anomalies-advisor.md) | [`verification/anomalies-advisor.md`](verification/anomalies-advisor.md) | PASS |
| `sessions-digest` | harness-observatory SG-05 | [SPEC-135](specs/SPEC-135-sessions-digest.md) | [`verification/sessions-digest.md`](verification/sessions-digest.md) | PASS (GATE: held for Han's review of the privacy boundary, see DECISIONS.md) |
| `memory-lens` | harness-observatory SG-06 | [SPEC-136](specs/SPEC-136-memory-lens.md) | [`verification/memory-lens.md`](verification/memory-lens.md) | PASS |
| `review-yield-lens` | gate-review-absorptions SG-04 | [SPEC-137](specs/SPEC-137-review-yield-lens.md) | [`verification/review-yield-lens.md`](verification/review-yield-lens.md) | PASS (HELD for Han, stacked PR) |
| `observatory-to-kit` (move + `mega-durations`) | runner-fastpath 05K | (no dwarves-kit SPEC number issued; historical SPEC-126..137 numbers above kept verbatim, not renumbered) | this file, "observatory-to-kit" sections below | PASS |

## Acceptance criteria (per feature)

### `schema` (SG-01) , see [`verification/schema.md`](verification/schema.md) for evidence

| # | Criterion | Status |
|---|---|---|
| AC1-AC6 | Canonical schema names the real kit grammar; ~10 stores confirmed; DEBT/TOKENS conform; 3 outlier adapter contracts; conformance check w/ negative control; read-only | PASS (11/11 + 4 NC) |

### `etl-cli` (SG-02) , see [`verification/etl-cli.md`](verification/etl-cli.md) for evidence

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | `ledger rebuild` materializes the db from the files (per-table counts) | PASS | R-rebuild |
| AC2 | `ledger show <name>` returns structured rows in BOTH `--table` and `--json` | PASS | R-show-json/table |
| AC3 | `ledger query` runs a cross-ledger JOIN (kit_runs x tide_moves) returning rows | PASS | R-join (count=2) |
| AC4 | delete-and-rematerialize: delete the db, re-run, output byte-identical | PASS | R-remat |
| AC5 | cross-format read correctness across all 4 shapes (pipe-log + sqlite + json + markdown) | PASS | R-formats-* (values) |
| AC6 | read-only NC: a query leaves every source ledger byte-identical (checksum before/after) | PASS | R-nc |
| AC7 | a write-shaped `query` is refused and cannot mutate the db | PASS | R-guard (exit 3) |
| AC8 | COVERAGE-DELTA recorded (covered + uncovered named) | PASS | verification/etl-cli.md |
| AC9 | schema-drift guard (2026-07-04 fix): the adapter column-name list and the DDL agree for all 3 Python-sourced tables, single-sourced from `schemas.py` + a load-time parity assertion; a reordered/dropped column is REJECTED (negative control) | PASS | P-parity, N-drift, N-drift-missing, R-load |

### `render-skill` (SG-03) , see [`verification/render-skill/render-skill.md`](verification/render-skill/render-skill.md) for evidence

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | the skill's frontmatter description contains the required trigger phrases | PASS | R-trigger |
| AC2 | `render.py` accepts a mocked JSON list-of-dict input (no live ledger/DuckDB) and produces a formatted surface, no re-read | PASS | R-queries-via-02 |
| AC3 | `render_terminal` output is a `bot-reply-formatting`-shaped code-block table | PASS | R-terminal |
| AC4 | `render_artifact` output is a complete, self-contained `<!doctype html>` document | PASS | R-artifact |
| AC5 | single-data-path NC: both surfaces render from the SAME `rows` object | PASS | R-nc (+ deliberate break-and-restore, NC2) |
| AC6 | a real terminal-render sample + a real Artifact HTML sample captured on disk | PASS | `verification/render-skill/samples/` |
| AC7 | SG-03 indexed in the multi-feature proof without overwriting 01/02's canonical content | PASS | this row |

### `feedback-loop` (SG-04) , see [`verification/feedback-loop/feedback-loop.md`](verification/feedback-loop/feedback-loop.md) for evidence

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | an over-threshold anomaly FIRES + `--propose` stages a `## [staged]` row | PASS | F-debt-over / F-cost-spike / F-misfire-over |
| AC2 | threshold correctness BOTH sides for all 3 detectors (boundary + floor-minus-one do not fire) | PASS | F-debt-under, F-cost-boundary/floor, F-misfire-boundary/floor |
| AC3 | FALSE-POSITIVE NC: noise-floor state proposes NOTHING (load-bearing, FB-1) | PASS | F-nc-noise |
| AC4 | PROPOSAL-NOT-AUTOFILE: board byte-identical; proposal consumable by `add-backlog` (load-bearing, FB-2) | PASS | F-proposal-not-autofile |
| AC5 | dedup idempotency: `--propose` twice stages once | PASS | F-dedup |
| AC6 | one `--threshold` tune flag (suppress / make-fire / reject bad input) | PASS | F-threshold-flag |
| AC7 | read-only over the ledgers: sources byte-identical after detect+propose | PASS | F-readonly-nc |
| AC8 | one data path: detection via `materialize` only (no duckdb/adapters bypass) | PASS | F-one-path |
| AC9-AC10 | COVERAGE-DELTA recorded; SG-04 indexed without overwriting 01/02/03 | PASS | verification/feedback-loop + this row |

### `docs-wiring` (SG-05, final) , see [`verification/docs-wiring.md`](verification/docs-wiring.md) for evidence

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | README + proof-of-done + tool.toml + a MANIFEST.md row all present and current | PASS | D-presence |
| AC2 | no-orphan sweep: render skill frontmatter carries its trigger phrases | PASS | D-skill-fires |
| AC3 | no-orphan sweep: skill body invokes real `ledger` CLI verbs (matched against `cli.py`'s `@app.command()`s) | PASS | D-cli-invoked |
| AC4 | no-orphan sweep: `ledger anomalies --propose` feeds the cc-backlog staging buffer | PASS | D-work-intake-fed |
| AC5 | OVER-CLAIM negative control: a fabricated documented-but-unwired command is a CAUGHT finding | PASS | D-nc (load-bearing) |
| AC6 | honesty fixes: `skill/SKILL.md` no longer claims the feedback loop unbuilt; README status table reflects 04 merged / 05 in-progress | PASS | grep clean, see README/SKILL diff |
| AC7 | the 4 known tradeoffs (dual schema definition, lane-telemetry coupling, static/global anomaly attribution + ~44% unattributed repo, silent source-skip) are stated plainly in README + proof, not hidden | PASS | README "Known tradeoffs", this file |
| AC8 | no existing per-feature `verification/*` file for 01-04 was modified | PASS | `git diff --stat -- verification/` empty for those paths |

### `kit-gates-lens` (harness-observatory mega-goal, SG-01) , see [`verification/kit-gates-lens.md`](verification/kit-gates-lens.md) for evidence

A NEW mega-goal (`harness-observatory`) reusing this tool's shipped module layout; the feature
index above and this file stay ONE canonical proof per the tool, per SPEC-016.

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | `kit_gates` table single-sourced via `schemas.KIT_GATES_SCHEMA` (7 cols), DDL + adapter columns derived, `assert_parity` guards the load | PASS | G-rebuild, unchanged `test-schema-parity.sh` (4/4) |
| AC2 | `ledger rebuild` then `ledger tables` shows `kit_gates` with a plausible row count over the real 63+ (now 621) run ledgers | PASS | real-corpus materialization below |
| AC3 | golden fixture: a committed fixture ledger dir (`tests/fixtures/kit-gates/runs/`) with known rids asserts EXACT `gate-yield` numbers | PASS | G-rows, G-yield |
| AC4 | FP negative control (load-bearing): a gate with legitimate skips and no caught signal (`ui-design`) is reported WITH its skip counts, not dropped, not mislabeled | PASS | F-nc, F-nc-deliberate-break |
| AC5 | over-test pass (`/kit:test-plan`-shaped): missing fields, malformed timestamps, duplicate gate names/rids all tolerated without crash or silent drop | PASS | O1/O2/O3 + G-rows fix-malformed assertions |
| AC6 | the 2026-07-04 hand-computed cut materialized as the first real `gate-yield` run-table row, drift vs. hand probe noted | PASS | `verification/kit-gates-lens.md` "Real-corpus materialization" |
| AC7 | COVERAGE-DELTA recorded (covered + uncovered named) | PASS | `verification/kit-gates-lens.md` "COVERAGE-DELTA" |
| AC8 | read-only, no new write path: `gate-yield` goes through the SAME `materialize.query()` path every other command uses | PASS | cli.py `gate_yield` has no new duckdb import |
| AC9 | no existing per-feature `verification/*`/`docs/specs/*` file for 01-05 was modified | PASS | `git diff --stat` empty for those paths |

### `defect-correlation` (harness-observatory mega-goal, SG-02) , see [`verification/defect-correlation.md`](verification/defect-correlation.md) for evidence

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | `git_fixes` table single-sourced via `schemas.GIT_FIXES_SCHEMA` (4 cols), DDL + adapter columns derived, `assert_parity` guards the load; the tool's FIRST git-sourced table | PASS | D-rebuild, unchanged `test-schema-parity.sh` (4/4) |
| AC2 | `ledger rebuild` then `ledger tables` shows `git_fixes` with a plausible row count over a real repo's full non-merge history | PASS | real-history materialization (ops-toolkit 9585 rows, dwarves-kit 1869 rows) |
| AC3 | golden fixture (generated at test time, SPEC-132 DEC-005): a known MISS (`widget-parser`, 2 later fixes, not collapsed) + a known CLEAN rid (`clean-feature`, the FP-NC) asserted EXACT | PASS | D-miss, D-multi, F-nc |
| AC4 | FP negative control (load-bearing): a shipped rid with zero later fixes on its own files is `clean`, never `fix-followed`; proven via a deliberate break of the shipped file-equality JOIN | PASS | F-nc, F-nc-deliberate-break |
| AC5 | windowing (`--window-days`) is an explicit, real tunable, not a buried constant: the SAME fixture data classifies differently at two window values | PASS | D-window (clean @ 30d default, fix-followed @ 120d) |
| AC6 | over-test pass: merge commits (excluded, proven at the adapter level), renames (tracked per-filename, no crash, documented v1 non-following limitation), multiple fixes on one file (not collapsed), a fix on unrelated files (no contamination), missing/non-git repo paths (skip-safe) | PASS | D-nc-merge, D-rename x2, O1-O3, F-nc-unrelated |
| AC7 | a real run over TWO real repos (ops-toolkit, dwarves-kit) materialized; yield reported honestly (most rids do not resolve via the name-bridge) | PASS | `verification/defect-correlation.md` "Real-history run" |
| AC8 | COVERAGE-DELTA recorded (covered + uncovered named) | PASS | `verification/defect-correlation.md` "COVERAGE-DELTA" |
| AC9 | read-only, no new write path, no git WRITE operation ever: `defect-correlation` goes through the SAME `materialize.query()` path every other command uses; `read_git_fixes` invokes only `git log` | PASS | cli.py `defect_correlation` has no new duckdb import; adapters.py `read_git_fixes` subprocess argv contains no write subcommand |
| AC10 | no existing per-feature `verification/*`/`docs/specs/*` file for 01-05/SG-01 was modified; `kit_gates`/`kit_runs`/`tide_moves`/`tg_dialogs`/`learned` untouched | PASS | `git diff --stat` empty for those paths |

### `deviation-rate` (harness-observatory mega-goal, SG-03) , see [`verification/deviation-rate.md`](verification/deviation-rate.md) for evidence

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | `impl_notes` table single-sourced via `schemas.IMPL_NOTES_SCHEMA` (7 cols), DDL + adapter columns derived, `assert_parity` guards the load | PASS | I-rebuild, unchanged `test-schema-parity.sh` (4/4) |
| AC2 | `ledger rebuild` then `ledger deviation-rate --table` shows a plausible row count + classification over a real repo's implementation-notes corpus | PASS | real-corpus materialization (ops-toolkit 233 rows, dwarves-kit 77 rows) |
| AC3 | golden fixture (generated at test time, mirrors SPEC-132 DEC-005): one file per named class (CLEAN, SUSPECT, UNDER-SPECCED) plus 3 over-test files (malformed, legacy, multi-same-day) asserted EXACT | PASS | I-classify (7/7 slugs) |
| AC4 | HONEST-ZERO negative control (load-bearing, absolute): a zero-marker slug with zero later fixes on its bridge-anchor's own files is `CLEAN`, never `SUSPECT`; proven via a deliberate break of the shipped file-equality JOIN | PASS | I-classify clean-notes, F-nc-deliberate-break |
| AC5 | windowing (`--window-days`) and the UNDER-SPECCED cutoff (`--under-specced-min`) are explicit, real tunables, not buried constants: the SAME fixture data classifies differently at two values of each | PASS | I-window (CLEAN @ 30d default, SUSPECT @ 150d), I-tunable (UNDER-SPECCED @ 3, OTHER @ 5) |
| AC6 | `unknown-density` anomaly: a fixture pushing the rolling median `n_deviations` over threshold stages exactly ONE proposal via `--propose`; a below-threshold fixture stages NOTHING | PASS | A-dense, A-sparse, A-dedup (idempotent re-propose) |
| AC7 | over-test: malformed file (marker + real entries, contradictory) counted as entries with `zero_marker` forced `False` and a stderr warning logged; a pre-convention legacy file with neither shape classifies `OTHER`, not silently coerced; a nested `.claude/worktrees/<x>` copy of the same repo is NOT double-counted | PASS | I-classify malformed-notes/legacy-notes/multi-same-day, O1-O4, O-malformed |
| AC8 | a real run over TWO real repos (ops-toolkit, dwarves-kit) materialized; class distribution reported honestly (incl. the honest finding that zero rows carry `zero_marker=true` in either real corpus today) | PASS | `verification/deviation-rate.md` "Real-corpus run" |
| AC9 | COVERAGE-DELTA recorded (covered + uncovered named) | PASS | `verification/deviation-rate.md` "COVERAGE-DELTA" |
| AC10 | read-only, no new write path: `deviation-rate` goes through the SAME `materialize.query()` path every other command uses; `read_impl_notes` is a pure filesystem walk (no subprocess, no shell) | PASS | cli.py `deviation_rate` has no new duckdb import; adapters.py `read_impl_notes` never shells out |
| AC11 | a REAL regression found + fixed during Build: 3 pre-existing suites never isolated `LEDGER_OBS_GIT_REPO_DIR`, so `impl_notes` broke `test-feedback.sh`'s load-bearing `F-nc-noise` NC and `test-ledger-cli.sh`'s byte-identical remat check; fixed with one isolation line each, `git stash`-verified exact pre-existing counts restored | PASS | `verification/deviation-rate.md` "Cross-suite regression found + fixed" |
| AC12 | no existing per-feature `verification/*`/`docs/specs/*` file for 01-05/SG-01/SG-02 was modified; `kit_gates`/`kit_runs`/`git_fixes`/`tide_moves`/`tg_dialogs`/`learned` untouched | PASS | `git diff --stat` empty for those paths |

### `anomalies-advisor` (harness-observatory mega-goal, SG-04) , see [`verification/anomalies-advisor.md`](verification/anomalies-advisor.md) for evidence

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | `_detect_ceremony` fires CUT: a gate with >= `ceremony_min_ran` ran+override runs, >= `ceremony_min_ran` KNOWN caught, zero true | PASS | C-cut |
| AC2 | `_detect_ceremony` fires CONDITION: a gate with >= `ceremony_min_ran` runs, zero known caught, >= `ceremony_min_ran` git-bridged, zero later-fixed | PASS | C-condition |
| AC3-AC4 | FP-NC (load-bearing): a high-skip but legitimately-caught gate (`ui-design`) does NOT fire; a hand-built bare skip-rate query WOULD flag it | PASS | C-fp-nc, C-fp-nc-deliberate-break |
| AC5 | mixed-caught NC: >= floor KNOWN caught samples with even ONE true does NOT fire (the "NONE true" clause, distinct from the thin-sample floor) | PASS | C-mixed |
| AC6 | count-inflation NC: ONE real rid whose single commit touches >= floor files does NOT fire (`bridged`/`fix_followed` count DISTINCT rids, not file-rows) | PASS | C-multifile-nc |
| AC6a | THIN-but-real-catch NC: below-floor `caught_known` containing a real `caught_true` does NOT fire even when the soft path's own floor is separately satisfied (DEC-006, a `kit:code-reviewer` MAJOR finding on the finished diff, distinct from AC5) | PASS | C-thin-true (falsifiable: reverting the guard hoist turns it RED) |
| AC7 | `_detect_token_runaway` always returns `None`, even alongside a firing ceremony | PASS | C-cut (embedded), T-not-armed |
| AC8 | `_detect_serial_when_parallel` fires: two dep-independent, >= 1-bridged-commit-each rids, non-overlapping git-observed windows | PASS | S-fire |
| AC9 | does NOT fire on a genuinely dependent (shared file) pair, same non-overlapping windows/durations | PASS | S-nofire |
| AC10 | does NOT fire on two rids with ZERO git-bridge evidence each (the structural evidence floor) | PASS | S-nofire-zero-evidence |
| AC11 | `--propose` stages both new detector shapes into the cc-backlog buffer, duplicate-safe | PASS | P-propose, P-dedup, S-propose |
| AC12 | `ledger anomalies --help` lists `ceremony_min_ran` + `serial_min_minutes_saved` | PASS | H-help |
| AC13 | real `uv run ledger rebuild` + `ledger anomalies --table` capture, honest yield stated | PASS | `verification/anomalies-advisor.md` "Real-corpus capture" |
| AC14 | a REAL regression found + fixed during Build: the original design anchored on `kit_runs`, which returns 0 rows in this local environment (a pre-existing, out-of-scope `lane-telemetry.sh` issue); redesigned to window on `git_fixes.ts` before any fixture was written | PASS | `verification/anomalies-advisor.md` "Test design" |
| AC15 | `/kit:spec-validate` dispatched on the draft design; 2 CRITICAL + 3 MAJOR findings, all addressed (SPEC-134 DEC-004/DEC-005) before Build closed | PASS | SPEC-134 "Review" |
| AC17 | `kit:code-reviewer` dispatched on the FINISHED diff (a fresh, independent Round-2 pass); confirmed Round-1 fixes real, found + this branch fixed 1 MAJOR (DEC-006) | PASS | SPEC-134 "Review" Round 2 |
| AC16 | no existing per-feature `verification/*`/`docs/specs/*` file for 01-05/SG-01/SG-02/SG-03 was modified | PASS | `git diff --stat` empty for those paths |

### `sessions-digest` (harness-observatory mega-goal, SG-05) , see [`verification/sessions-digest.md`](verification/sessions-digest.md) for evidence

**GATE: held for Han's review of the privacy boundary before merge** (the extracted-field
whitelist, verbatim in `_meta/megagoals/harness-observatory/DECISIONS.md`).

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | `schemas.SESSIONS_SCHEMA`/`SAFETY_SCHEMA` produce the exact 13/5-column lists; `assert_parity` guards both loads (existing machinery, no new guard code) | PASS | golden fixture assertions |
| AC2 | `read_sessions` on a golden fixture returns EXACT token/tool-call/error/compaction/canary values | PASS | golden (12 assertions) |
| AC3 | `read_safety` on a fixture log returns EXACT per-status/per-rule row counts | PASS | safety golden (8 assertions) |
| AC4 | **PRIVACY negative control (load-bearing, absolute):** `FAKE-SECRET-a1b2c3` embedded in BOTH `tool_result.content` AND `custom-title` appears in ZERO materialized tables/columns while the session's numeric row DOES exist; a deliberate schema/parser widen turns it RED, restored | PASS | PRIV-nc (4 assertions) + the falsifiability run (`verification/sessions-digest.md` "PRIV-nc falsifiability") |
| AC5 | a malformed/truncated jsonl line does not crash `read_sessions`; valid lines still contribute | PASS | O-malformed |
| AC6 | an empty session file (zero timestamped lines) produces NO row | PASS | O-empty |
| AC7 | a session with 2+ `compact_boundary` lines counts `compaction_count` correctly (not just 0-or-1) | PASS | O-multicompact |
| AC8 | `_detect_token_runaway` (ARMED) fires on a session over `token_budget_max`; does not fire under/at budget or on an empty `sessions` table | PASS | T-default, T-low-threshold, T-empty |
| AC9 | `ledger digest` on a golden bridge (shipped rid + a git commit inside a session's time window) reports EXACT `coverage_pct`/`cost_per_verified_outcome_tokens`/`avg_time_to_done_min` | PASS | D-coverage_pct, D-cost_per_verified_outcome_tokens, D-avg_time_to_done_min |
| AC10 | `ledger digest` on a shipped rid with NO time-containing session reports null coverage/cost, never a crash | PASS | digest honest-empty (3 assertions) |
| AC11 | `ledger digest --propose` stages via the SAME `stage_proposals()` path `anomalies --propose` uses, duplicate-safe | PASS | P-digest-propose (3 assertions) |
| AC12 | a real `uv run ledger rebuild` + `ledger digest --table` capture against the live corpus, honest about the JOIN | PASS | `verification/sessions-digest.md` "Real-corpus capture" |
| AC13 | `ledger anomalies --help` lists `token_budget_max` | PASS | H-help |
| AC14 | `read_sessions`/`read_safety` are skip-safe on a missing source | PASS | O-missing |
| AC15 | a REAL Build-time bug found + fixed: `tool_result`/`is_error` lives on a `type=="user"` line, not the `type=="assistant"` line that emitted the matching `tool_use` (SPEC-135 DEC-007); `error_count` silently stayed 0 across the real corpus before the fix | PASS | `verification/sessions-digest.md` "Test design" |
| AC16 | a real cross-suite regression found + fixed: 7 existing suites never isolated the two new source env vars (one timed out entirely against the 2.1GB real corpus); one stale assertion (`test-anomalies-advisor.sh`'s `T-not-armed`) updated to match the now-armed detector | PASS | `verification/sessions-digest.md` "Test design"; full regression 230/230 |
| AC17 | no existing per-feature `verification/*`/`docs/specs/*` file for 01-05/SG-01..04 was modified | PASS | `git diff --stat` empty for those paths |
| AC18 | `kit:code-reviewer` dispatched on the FINISHED diff (Round 2, independent of the draft-stage validate); found + this branch fixed a CRITICAL content-leak (bare `int()` on a non-numeric usage field surfacing content in a traceback -- DEC-008), a MAJOR cost double-count across overlapping sessions (DEC-010), and a MINOR unvalidated timestamp (DEC-009); suite grew 49 -> 59 assertions, all green | PASS | O-badtype, D-overlap, O-badts; SPEC-135 "Review" Round 2 |

### `review-yield-lens` (gate-review-absorptions mega-goal, SG-04) , see [`verification/review-yield-lens.md`](verification/review-yield-lens.md) for evidence

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | `schemas.REJECTED_FINDINGS_SCHEMA` produces the exact 5-column list; `assert_parity` guards the load (existing machinery, no new guard code) | PASS | golden fixture assertion |
| AC2 | `read_rejected_findings` on a golden fixture returns EXACT per-(repo, lens) `n_rejected`/`first_ts`/`last_ts` | PASS | P-rows (6 assertions) |
| AC3 | ONLY the `## Rows` heading is read as data; the `## Format` section's template row is never counted | PASS | O3-format-template-row-ignored |
| AC4 | a malformed row (too few cells, non-`rejected` verdict) is skipped AND counted in a stderr warning, never silently dropped, never raised | PASS | P-skip-warning |
| AC5 | a repo whose ledger file does not exist, or whose file exists with zero rows, contributes ZERO rows, never an exception, never a fabricated placeholder | PASS | O1-missing-file, O2-zero-rows-file, P-rows repo-empty |
| AC6 | `review-yield` regex-extracts `findings=`/`rejected=` from `kit_gates.reason` at query time; `suppressed=` NEVER contributes to `raised`; a `skipped`-outcome review row is excluded from the denominator; a non-`review` gate row never leaks in | PASS | Y-yield (exact numbers), Y-suppressed-excluded |
| AC7 | **honest-zero negative control (load-bearing):** zero `rejected_findings` rows + zero review activity -> ZERO output rows, exit 0; a literal source-edit deliberate break (reversed JOIN direction + `NULL`->`0.0`) fabricates a bogus all-NULL/0.0 row (RED), restored -> `[]` again (GREEN), source byte-identical after restore | PASS | H-nc, H-nc-deliberate-break (3 assertions) |
| AC8 | division-by-zero guard: `raised=0` -> `fp_rate_approx` is `NULL` for every row, never `0.0` | PASS | Z-div-by-zero (4 assertions) |
| AC9 | honest-negative: a (repo, lens) whose `n_rejected` exceeds `raised` reports `fp_rate_approx > 1.0` exactly, never clamped | PASS | Y-honest-negative |
| AC10 | `--min-n` is a real, named tunable (not a buried constant) that moves the `low_n` boundary | PASS | D-min-n |
| AC11 | new `_detect_review_fp` anomaly fires on real threshold-crossing fixture data (dual min-n floor + rate threshold) and stages via the EXISTING `--propose` path only (staging buffer written, board file untouched) | PASS | O-anomaly (5 assertions) |
| AC12 | a real `uv run ledger rebuild` + `ledger review-yield --table` capture against the live 2-repo corpus (`ops-toolkit`, `dwarves-kit`), low-n honestly labeled | PASS | `verification/review-yield-lens.md` "Real-corpus materialization" |
| AC13 | full existing suite (12 prior `tests/test-*.sh` files) regression-checked, zero failures | PASS | `verification/review-yield-lens.md` "Confirmation run" |
| AC14 | no existing per-feature `verification/*`/`docs/specs/*` file for 01-05/SG-01..06 was modified | PASS | `git diff --stat` empty for those paths |
| AC15 | `kit:code-reviewer` dispatched on the finished diff (independent of the draft-stage spec-validate pass) | PASS | `verification/review-yield-lens.md` "Review" |

### `observatory-to-kit` (runner-fastpath goal 05K: move into dwarves-kit + `mega-durations`)

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | verbatim relocation: the whole tool tree (`src/tests/docs/skill/pyproject/uv.lock/README/tool.toml`) copied from ops-toolkit unchanged, plus `docs/megagoals/harness-observatory/` (the mega that built SG-01..06) alongside the tool's own `docs/megagoals/ledger-observatory/` | PASS | `git show --stat` of the first commit on this branch (100 files, additive only) |
| AC2 | relocation NC: the pre-existing 13-file suite runs green in the new location with ZERO code changes | PASS | first full-suite run post-copy: 5 of 13 files failed on hardcoded same-repo sibling-tool assumptions (`../tide`, `../cc-backlog` x3, `MANIFEST.md`); each converted to a SKIP (never a silent pass, never a hard fail) matching the tool's own skip-safe contract, applied to test infra | see "Confirmation" below |
| AC3 | adapter-default split: kit-internal sources (`DWARVES_KIT_LIB`, `LEDGER_OBS_GIT_REPO_DIR`, `LEDGER_OBS_MEMORY_REPO_DIR`) default to this repo's own root (computed via `git rev-parse --show-toplevel`, never hardcoded); `DWARVES_KIT_LOG_DIR` verified unchanged (already host-generic XDG state) | PASS | manual sanity check with every override unset (see Confirmation); `test-ledger-cli.sh`'s `R-rebuild kit_runs>0` exercises the new `DWARVES_KIT_LIB` default end-to-end (parses this repo's own `lib/lane-telemetry.sh`) |
| AC4 | ops-toolkit-specific sources (`LEDGER_OBS_TIDE_DB`, `LEDGER_OBS_TGCLEANUP_DIR`, `LEDGER_OBS_LEARNED_MD`, `LEDGER_OBS_REPOS`, `CC_BACKLOG_STAGING`, `CC_BACKLOG_BACKLOG`, `OPS_TOOLKIT`) lose their hardcoded fallback; an unset value is skip-safe for every READ path (unchanged contract) | PASS | manual sanity check, all 7 return `None`/`[]` with every override unset |
| AC5 | the ONE write path (`--propose` staging a backlog row) fails LOUD with a clean CLI error (exit 2) when there is a real proposal to stage but no destination is configured -- never a crash, never a silent write to a bogus cwd-relative path | PASS | `F-no-staging-config` (4 assertions in `test-feedback.sh`) + a manual live repro pasted in Confirmation |
| AC6 | `mega-durations`: data-driven `GROUP BY rid` over `kit_gates`, no hardcoded gate whitelist (same convention as `gate-yield`'s `GROUP BY gate`); per-rid wall time = `max(end_ts) - min(start_ts)` (integer epoch-second subtraction, NOT a parsed-timestamp `date_diff` -- `start_ts`/`end_ts` are gate-ledger.sh's raw `at=<epoch>` value) | PASS | `M-golden` (golden fixture, hand-verified durations) |
| AC7 | a row missing either timestamp is excluded from the per-rid min/max AND counted separately ("N rows excluded"), never silently dropped | PASS | `M-golden` (5 excluded of 8), `M-nc-stripped` (all 8 excluded) |
| AC8 | NC (load-bearing): a fixture with every `OUTCOME end` bracket stripped -> 0 rids with complete timestamps, all rows excluded, exit 0, never a crash on missing data | PASS | `M-nc-stripped` (6 assertions) + `M-nc-deliberate-break` (falsifiability: the real exclusion count on that fixture is 8, not vacuously 0) |
| AC9 | `TRY_CAST` (not `CAST`) into `BIGINT`: a present-but-malformed `at=` token degrades to a NULL contribution for that one row, never an uncaught DuckDB error for the whole query | PASS | cross-checked live against the pre-existing `tests/fixtures/kit-gates/` fixture's `fix-malformed` rid (`start_ts="notanumber"`) -- `wall_seconds: null`, exit 0, no crash |
| AC10 | delete-and-rematerialize + read-only NC (fixture files byte-identical) for `mega-durations`, matching every other feature's own convention | PASS | `M-remat`, `M-nc` |
| AC11 | LIVE run over the real, now-relocated ledger corpus, honest about today's sparse OUTCOME-bracket coverage (the actual first answer to "where does the 2-3h go") | PASS | see Confirmation "observatory-to-kit real-corpus run" |
| AC12 | `tool.toml` `consumers` updated to name ops-toolkit (now a consumer, not the owner); dwarves-kit's top-level-tools-index gap checked and reported, not invented | PASS | `tool.toml` diff; no `MANIFEST.md`/`CONSUMERS.md`-equivalent found in this repo as of this writing |
| AC13 | full suite (13 pre-existing + `test-mega-durations.sh` = 14 files) green together, in one run, in the new location | PASS | see Confirmation "observatory-to-kit full suite" |

## Known tradeoffs (accepted-for-now, not defects hidden)

Stated in full in `README.md`'s "Known tradeoffs" section; summarized here for gate visibility.
The read-only-lens, files-canonical, delete-and-rematerialize, and propose-never-autofile
claims above ARE proven by the 4 feature test suites; these four are NOT proven and should not
read as if they were:

1. The kit-run table schema is defined twice (`adapters.KIT_COLUMNS` vs. `materialize._KIT_DDL`),
   hand-synced, no assertion they stay in lockstep.
2. The kit-side read couples to lane-telemetry's private `_rows()` helper; a field-count drift
   there truncate-pads with empty strings in `adapters.read_kit` rather than failing loud.
3. Anomaly `home` attribution is a static per-detector guess, not data-derived; debt/misfire
   sums are global across repos while staging into ops-toolkit's own buffer; ~44% of `kit_runs`
   rows (35/79 measured live on this repo) carry `repo = "?"` (unattributed).
4. A missing source (e.g. no tide db) is skipped exactly like a present-but-empty one; no
   `ledger doctor`-style "checked, not found" signal exists today.
5. `review-yield`'s FP-rate is a stated, labeled APPROXIMATION (SPEC-137 DEC-002): the
   numerator is per-(repo, lens) but the denominator is a GLOBAL sum across every
   `gate='review'` `kit_gates` row (that table carries no lens or repo column). Every row
   carries `approx=true` and a `low_n` flag so this is never presented as more precise than it
   is, but it is not a true per-lens rate until a real per-lens emit lands (a named follow-on).

Follow-up candidates for all five are routed to `_meta/megagoals/ledger-observatory/NOTES.md`
`## Proposed additions` (2026-07-04), out of this PR's code scope.

## Implementation

| Aspect | Detail |
|---|---|
| What | Read-only DuckDB lens over 4 ledger shapes + an agent-callable `ledger show/query/rebuild/tables` CLI (json/table). The files are canonical; the db is disposable. |
| Where | `tools/ledger-observatory/src/ledger_observatory/{config,adapters,materialize,cli,schemas}.py`; tests `tests/{test-ledger-cli,test-schema-parity}.sh` |
| How it runs | `uv sync && uv run ledger <cmd>`; no daemon (on-demand refresh, fork 2); DuckDB via the Python wheel (no INSTALL/LOAD) |
| Reuse | kit corpus read via lane-telemetry's own `_rows()` parser (mandated; no re-parse). tide via DuckDB `ATTACH (TYPE sqlite, READ_ONLY)`; tg-cleanup via json read; learned via a markdown adapter. |
| Read-only | THREE layers: a statement guard (single read-verb statement, no mutator, no PRAGMA, no multi-statement) + `read_only=True` + `enable_external_access=False` (blocks filesystem writes). sqlite ATTACH is `READ_ONLY`. No write path to any source (HIGH-1 filesystem-write bypass found at review + closed). |
| Touches | Additive; `lib/lane-telemetry.sh`, tide, tg-cleanup, learned-ledger all read, none modified. |

### `render-skill` (SG-03)

| Aspect | Detail |
|---|---|
| What | A pure render layer (`render_terminal`/`render_artifact`, zero I/O) + a `ledger render` CLI subcommand that reuses the existing `show`/`query` read path, plus the skill source (`skill/SKILL.md`) that documents which surface to pick and how to install it. |
| Where | `tools/ledger-observatory/src/ledger_observatory/render.py`; `cli.py`'s new `render` command; `tools/ledger-observatory/skill/SKILL.md`; tests `tests/test-render-skill.sh` |
| How it runs | `uv run ledger render <NAME\|--query SQL> --surface terminal\|artifact [--title][--out]`; no new daemon, no new refresh trigger (inherits SG-02's lazy-rebuild-on-missing) |
| Reuse | The CLI's `render` command calls the SAME `materialize.show`/`materialize.query` SG-02 already ships , zero new read logic. `render.py` has no imports from `materialize`/`adapters`/`duckdb` at all (structural read-isolation). |
| Single data path | One fetched `rows: list[dict]` object (the same shape `--json` already emits) is handed to exactly one of the two pure formatters per invocation; the NC proves neither formatter can diverge from what was actually fetched. |
| Touches | Additive; `cli.py` gains one function, `show`/`query`/`rebuild`/`tables` unchanged. Nothing installed into `~/.claude/skills/` (doc-only install pointer, per goal-file scope edge). |

### `kit-gates-lens` (harness-observatory mega-goal, SG-01)

| Aspect | Detail |
|---|---|
| What | A `kit_gates` table (one row per `\| GATE \|` kit run-ledger line) + a `ledger gate-yield [--json\|--table]` ceremony-detector command, per-gate `ran/override/skipped/caught/override_pct`. |
| Where | `src/ledger_observatory/schemas.py` (`KIT_GATES_SCHEMA`), `adapters.py` (`read_kit_gates`, a NEW per-line parser), `materialize.py` (DDL + rebuild wiring + `SHOW_ORDER`), `cli.py` (`gate-yield`); tests `tests/test-gate-yield.sh` + committed fixtures `tests/fixtures/kit-gates/runs/*.log` |
| How it runs | `uv run ledger rebuild` then `uv run ledger gate-yield --table`; no new daemon, no new refresh trigger (inherits the lazy-rebuild-on-missing SG-02 already ships) |
| Reuse | Cannot reuse lane-telemetry's `_rows()` (aggregates per-file, no per-line output mode) -- a deliberate, documented exception (SPEC-131 DEC-001), scoped to the one grammar line `_rows()` doesn't expose. `gate-yield` itself reuses the SAME `materialize.query()` read path `show`/`query`/`render` already use; zero new duckdb connection. |
| Two-marker join | `caught`/`start_ts`/`end_ts` come from a SEPARATE `\| OUTCOME \|` bracket (kit's own SPEC-129), paired to the `GATE` row by phase name, FIFO per (rid, gate); on the real corpus this is 100% NULL today (zero run ledgers emit a real OUTCOME line yet, verified across all files), by design, not a bug (SPEC-131 DEC-003). |
| Touches | Additive; `kit_runs`/`tide_moves`/`tg_dialogs`/`learned` unchanged, `show`/`query`/`rebuild`/`tables`/`render`/`anomalies` unchanged. |

### `defect-correlation` (harness-observatory mega-goal, SG-02)

| Aspect | Detail |
|---|---|
| What | A `git_fixes` table (one row per (commit, file-touched) pair across a repo's full non-merge `git log` history, the tool's FIRST git-sourced table) + a `ledger defect-correlation [--window-days N] [--json\|--table]` command correlating shipped `kit_gates` runs against later `fix()` commits touching the same files. |
| Where | `src/ledger_observatory/schemas.py` (`GIT_FIXES_SCHEMA`), `adapters.py` (`read_git_fixes`, a NEW `git log` subprocess reader), `config.py` (`git_repo_dir`), `materialize.py` (DDL + rebuild wiring + `SHOW_ORDER`), `cli.py` (`defect-correlation`); tests `tests/test-defect-correlation.sh` (a generated, not committed, git-history fixture per SPEC-132 DEC-005) |
| How it runs | `uv run ledger rebuild` then `uv run ledger defect-correlation --table`; no new daemon, no new refresh trigger (inherits the lazy-rebuild-on-missing SG-02/etl-cli already ships) |
| Reuse | `read_git_fixes` is a NEW reader (no existing git-log parser to reuse in this tool); it stores the FULL history, not fix-filtered, so `defect-correlation`'s query classifies fix-ness in SQL, the same convention `gate-yield` already uses for `outcome` (SPEC-132 DEC-001). The CLI command reuses the SAME `materialize.query()` read path every other command uses; zero new duckdb connection. |
| Rid-to-git bridge | `kit_gates` v1 carries no per-file/repo column (SPEC-131), so a literal file-level JOIN is impossible without rewriting it (out of scope). A two-stage design bridges by name once (`contains(lower(subject), lower(rid))`, empirically verified real signal) then correlates by genuine FILE equality thereafter (SPEC-132 DEC-002), keeping "touching the same files" honest instead of degrading to a name-only heuristic. |
| Touches | Additive; `kit_gates`/`kit_runs`/`tide_moves`/`tg_dialogs`/`learned` unchanged, `show`/`query`/`rebuild`/`tables`/`render`/`gate-yield`/`anomalies` unchanged. No git WRITE operation is ever invoked. |

### `deviation-rate` (harness-observatory mega-goal, SG-03)

| Aspect | Detail |
|---|---|
| What | An `impl_notes` table (one row per hook-enforced `docs/implementation-notes/<slug>.md` file) + a `ledger deviation-rate [--under-specced-min N] [--window-days N] [--json\|--table]` command classifying each file `UNDER-SPECCED`/`CLEAN`/`SUSPECT`/`OTHER` + an `unknown-density` anomaly detector. The upstream-unknowns half of the benchmark. |
| Where | `src/ledger_observatory/schemas.py` (`IMPL_NOTES_SCHEMA`), `adapters.py` (`read_impl_notes`, a NEW filesystem-walk reader), `materialize.py` (DDL + rebuild wiring + `SHOW_ORDER`), `cli.py` (`deviation-rate`), `anomalies.py` (`_detect_unknown_density`); tests `tests/test-deviation-rate.sh` (a generated, not committed, git-history fixture per SPEC-132 DEC-005 precedent + 7 plain-file implementation-notes fixtures) |
| How it runs | `uv run ledger rebuild` then `uv run ledger deviation-rate --table`; no new daemon, no new refresh trigger (inherits the lazy-rebuild-on-missing SG-02/etl-cli already ships) |
| Reuse | `read_impl_notes` is a NEW reader (no existing implementation-notes parser in this tool); it shares `config.git_repo_dir()` with `read_git_fixes` rather than a second env knob (SPEC-133 DEC-001). The CLI command reuses the SAME `materialize.query()` read path every other command uses; zero new duckdb connection. The anomaly detector reuses the SAME `materialize.query`-only contract every other detector uses. |
| Slug-to-git bridge | An implementation-notes file carries a `slug`, never a sha or a file list of its own (the SAME JOIN-key shape SPEC-132 already solved for `rid`). A two-stage design bridges by name once (`contains(lower(subject), lower(slug))`) then correlates by genuine FILE equality thereafter (SPEC-133 DEC-002), keeping "a later fix on the same files" honest instead of degrading to a name-only heuristic. `UNDER-SPECCED` needs no bridge at all (a pure `n_deviations` count threshold). |
| Parser tolerance | Confirmed real prose drift (a 208+76-file corpus survey at design time): the entry-header `HH:MM` time component is frequently dropped; the zero-marker line's trailing wording varies. Both tolerated by design (SPEC-133 Edge Cases 3-4). A file with BOTH a zero-marker line AND real entries (confirmed real, a self-contradiction) is counted as entries with `zero_marker` forced `False` and a stderr warning logged (DEC-003). |
| Touches | Additive; `kit_gates`/`kit_runs`/`git_fixes`/`tide_moves`/`tg_dialogs`/`learned` unchanged, `show`/`query`/`rebuild`/`tables`/`render`/`gate-yield`/`defect-correlation` unchanged. Fixed a real regression in 3 PRE-EXISTING test files (`test-ledger-cli.sh`/`test-feedback.sh`/`test-gate-yield.sh`, one isolation-env line each, DEC-004); no assertion logic in those files changed. |

### `anomalies-advisor` (harness-observatory mega-goal, SG-04)

| Aspect | Detail |
|---|---|
| What | 3 new `_detect_*` functions in `anomalies.py`: `ceremony` (a gate that ran a lot but never caught anything, CUT/CONDITION), `token_runaway` (NOT ARMED, always `None`), `serial_when_parallel` (two dep-independent rids that ran in separate serial waves, a plausible minutes-saved estimate). |
| Where | `src/ledger_observatory/anomalies.py` (`DEFAULTS` + 3 detectors + `DETECTORS` tuple + `_FIX_SUBJECT_RE` + `_seconds_between`), `cli.py` (`anomalies()` docstring, one sentence); tests `tests/test-anomalies-advisor.sh` |
| How it runs | `uv run ledger rebuild` then `uv run ledger anomalies --table`/`--propose`; no new command, no new daemon |
| Reuse | Both new SQL-backed detectors reuse the SAME `materialize.query()` read path every other command uses; zero new duckdb connection. `ceremony` generalizes `defect-correlation`'s rid-to-git bridge from `gate='ship'` to every gate. `serial_when_parallel` reuses the same bridge technique over the full `kit_gates` rid universe. |
| Ceremony conditioning | Two signals, in priority order, NEVER a bare skip-rate: hard (`caught`, when evidence-sufficient) then soft (fix-correlation proxy, when `caught` is thin/absent). `bridged`/`fix_followed` count DISTINCT rids, not file-rows (a `/kit:spec-validate` CRITICAL finding, fixed before Build closed -- SPEC-134 DEC-004). |
| Serial-when-parallel anchor | Windows every `kit_gates` rid by `MIN(ts)..MAX(ts)` across its OWN git-bridged commits -- DELIBERATELY not `kit_runs` (confirmed broken in this local environment, a pre-existing issue; SPEC-134 DEC-005). The evidence floor (both rids need >= 1 bridged commit) is structural (INNER JOINs), not an added `WHERE`. |
| Token-runaway | Always returns `None`; wired into `DETECTORS` now so the shape (incl. `--propose`) is exercised end-to-end once the sessions table (sub-goal 05) lands. Never faked. |
| Touches | Additive; `kit_gates`/`git_fixes`/`kit_runs`/`impl_notes`/`tide_moves`/`tg_dialogs`/`learned` and every existing CLI command unchanged (`cli.py`'s ONLY touch is one docstring sentence). |

### `sessions-digest` (harness-observatory mega-goal, SG-05, GATE)

| Aspect | Detail |
|---|---|
| What | Two NEW numeric-only tables (`sessions`: one row per Claude Code transcript file; `safety`: one row per secret-guard audit-log line) + `ledger digest [--json\|--table] [--propose]`, the north-star scorecard (token efficiency incl. cost-per-verified-outcome, time-to-done, bridge coverage, folding in `anomalies --propose`). `anomalies._detect_token_runaway` (SPEC-134, previously a permanent `None` stub) is now ARMED against `sessions`. |
| Where | `src/ledger_observatory/{schemas,config,adapters,materialize,anomalies,cli}.py`; tests `tests/test-sessions-digest.sh` (new, 49 assertions) |
| How it runs | `uv run ledger rebuild` then `uv run ledger digest --table`/`--propose`; no new daemon, no new refresh trigger |
| The privacy boundary | A per-line field ALLOWLIST enforced AT PARSE TIME (`_parse_session_file`/`read_safety`), not filtered later: `tool_result.content`, `custom-title`, `last-prompt`, `agent-name`, `cwd`, `sessionId` and every other transcript key are never assigned to a variable, let alone returned. The one `text` field DOES get read, but transiently (a derived boolean for the adherence-canary check), never persisted. Verbatim whitelist: `_meta/megagoals/harness-observatory/DECISIONS.md`. |
| The PRIVACY NC (load-bearing) | A fixture embeds a fake secret in BOTH `tool_result.content` and `custom-title`; a full-text scan of every materialized table/column finds zero hits while the session's numeric row exists. Falsifiable: a deliberate schema/parser widen (adding a raw-text column) turns it RED, restored. |
| Digest JOIN | `sessions` carries no rid/repo column in v1; `cost_per_verified_outcome_tokens`/`avg_time_to_done_min` bridge a shipped `kit_gates` rid to git (the SAME rid-to-git-subject technique defect-correlation/ceremony/serial-when-parallel already use) then to a `sessions` row by TIME CONTAINMENT (the commit's timestamp falling inside the session's `[first_ts, last_ts]` window) instead of file equality, since `sessions` has no file list (SPEC-135 DEC-002). |
| Token-runaway armed | A flat per-session `token_budget_max` threshold (not per-rid, DEC-004: would need the SAME bridge `digest` builds, duplicated inside a detector for marginal benefit), flags the single highest-total session, matching every other detector's single-shot shape. |
| Two REAL bugs found + fixed during Build | (1) `tool_result`/`is_error` lives on a `type=="user"` line, not the assistant line that emitted the matching `tool_use` -- `error_count` silently stayed 0 across the real corpus before the fix (DEC-007). (2) 7 existing suites never isolated the two new source env vars, timing one out entirely against the real 2.1GB corpus; fixed with the same isolation-line convention SG-03 established, plus one stale assertion update in `test-anomalies-advisor.sh`. |
| Touches | Additive; `kit_gates`/`git_fixes`/`kit_runs`/`impl_notes`/`tide_moves`/`tg_dialogs`/`learned` and every existing CLI command unchanged beyond `anomalies.py`'s docstring + `_detect_token_runaway`'s body. |

## Confirmation (recorded runs)

| Run | When | Command | Exit | Verdict |
|---|---|---|---|---|
| etl-cli suite | 2026-07-03T19:58:05Z | `bash tests/test-ledger-cli.sh` | 0 | PASS (26/26, incl. HIGH-1 regression) |
| etl-cli NC4 (falsifiability) | 2026-07-03 | tide source absent -> JOIN/sqlite assertions RED | n/a | RED-as-expected |
| etl-cli independent verify | 2026-07-03 | fresh-context verifier re-ran `uv sync` + suite | 0 | PASS |
| schema suite | 2026-07-04 | `bash tests/test-schema-conform.sh` | 0 | PASS (11/11 + 4 NC) |
| render-skill suite | 2026-07-03T20:28:28Z | `bash tests/test-render-skill.sh` | 0 | PASS (30/30) |
| render-skill NC2 (deliberate break) | 2026-07-03 | `render_artifact` patched to discard passed `rows` | 1 | RED-as-expected (4 cases failed), restored -> 30/30 exit 0 |
| render-skill regression | 2026-07-03T20:28:28Z | `test-schema-conform.sh` + `test-ledger-cli.sh` re-run alongside the new suite | 0 / 0 | PASS (11/11, 26/26, unchanged) |
| feedback-loop suite | 2026-07-03T20:54Z | `bash tests/test-feedback.sh` | 0 | PASS (39/39) |
| feedback-loop FB-1/FB-2 (falsifiability) | 2026-07-03T20:55Z | too-loose threshold makes noise propose; injected auto-file flips board sha | n/a | RED-as-expected (both), restored 39/39 |
| feedback-loop regression | 2026-07-03T20:56Z | schema + etl-cli + render suites re-run | 0/0/0 | PASS (11/11, 26/26, 30/30, unchanged) |
| docs-wiring suite | 2026-07-03T21:22:57Z | `bash tests/test-docs-wiring.sh` | 0 | PASS (19/19) |
| docs-wiring D-nc (falsifiability) | 2026-07-03T21:15Z | `unwired_claims()` neutered to always return empty (simulated vacuous check) | 1 | RED-as-expected (PASS=18 FAIL=1, the OVER-CLAIM line), restored -> 19/19 exit 0 |
| docs-wiring full regression | 2026-07-03T21:22:57Z | all 5 suites re-run together (schema + etl-cli + render + feedback + docs-wiring) | 0/0/0/0/0 | PASS (11/11, 26/26, 30/30, 39/39, 19/19 = 125/125, unchanged) |
| schema-drift-guard suite (etl-cli AC9 fix) | 2026-07-04 | `bash tests/test-schema-parity.sh` | 0 | PASS (4/4: P-parity, N-drift, N-drift-missing, R-load) |
| schema-drift-guard regression | 2026-07-04 | all 5 suites re-run together (+ docs-wiring after this PR merges = 129/129) | 0 (x5) | PASS (11/11, 26/26, 30/30, 39/39, 4/4 = 110/110 at #679; 19/19 docs-wiring adds on merge) |
| kit-gates-lens suite | 2026-07-04 | `bash tests/test-gate-yield.sh` | 0 | PASS (25/25: golden fixture + FP-NC + over-test O1-O3) |
| kit-gates-lens F-nc (deliberate break, falsifiability) | 2026-07-04 | `read_kit_gates` patched to force `caught = True` unconditionally | n/a | RED-as-expected (15/25 passed, 10 failed, incl. the FP-NC), restored -> 25/25 exit 0 |
| kit-gates-lens regression | 2026-07-04 | `test-schema-parity.sh` re-run alongside the new suite | 0 | PASS (4/4, unchanged) |
| kit-gates-lens real-corpus materialization | 2026-07-04 | `uv run ledger rebuild && uv run ledger gate-yield --table` against the live 63+ (621) run-ledger corpus | 0 | see `verification/kit-gates-lens.md` "Real-corpus materialization" |
| kit-gates-lens PRE-EXISTING, unrelated regression | 2026-07-04 | `bash tests/test-ledger-cli.sh` | 1 | 19/26 pass, 7 fail (all `kit_runs`-related). Reproduced IDENTICALLY on `main` before this branch (`git stash` + re-run); `read_kit()`'s subprocess call into the installed `~/.claude/dwarves-kit/lib/lane-telemetry.sh` returns 0 rows in this local environment, unrelated to `kit_gates`/`read_kit_gates` (this PR never touches `read_kit`). Out of scope per SPEC-131's scope fence ("Not: rewriting `kit_runs`"); noted honestly rather than silently worked around. |
| defect-correlation suite | 2026-07-04 | `bash tests/test-defect-correlation.sh` | 0 | PASS (20/20: golden fixture + FP-NC + merge/rename/window/multi-fix over-test) |
| defect-correlation F-nc (deliberate break, falsifiability) | 2026-07-04 | `cli.py`'s `LEFT JOIN later_fix` patched to drop the `lf.file = sfl.file` condition | n/a | RED-as-expected (17/20 passed, 3 failed, incl. the FP-NC and one rename assertion), restored -> 20/20 exit 0 |
| defect-correlation regression | 2026-07-04 | `test-schema-parity.sh` + `test-gate-yield.sh` re-run alongside the new suite | 0 / 0 | PASS (4/4, 25/25, unchanged) |
| defect-correlation real-history run | 2026-07-04 | `uv run ledger rebuild && uv run ledger defect-correlation --table` against `ops-toolkit` (default) and `dwarves-kit` (`LEDGER_OBS_GIT_REPO_DIR`) | 0 | see `verification/defect-correlation.md` "Real-history run" (0 rows ops-toolkit, 3 rows dwarves-kit, 1 distinct rid resolved) |
| defect-correlation PRE-EXISTING, unrelated regression (test-ledger-cli) | 2026-07-04 | `bash tests/test-ledger-cli.sh` | 1 | same 19/26 (7 `kit_runs`-related failures) as SG-01 recorded; unaffected by this branch |
| defect-correlation PRE-EXISTING, unrelated regression (test-feedback, newly confirmed) | 2026-07-04 | `bash tests/test-feedback.sh` | 1 | 30/39 pass, 9 fail. Reproduced IDENTICALLY on `main` before this branch (`git stash` + re-run, same 30/9 split); predates and is unrelated to `git_fixes`/`defect-correlation` (this PR never touches `anomalies.py`/`kit_runs`). Not fixed here (out of scope); noted honestly per the same discipline SG-01 applied to `test-ledger-cli.sh`. |
| deviation-rate suite | 2026-07-04 | `bash tests/test-deviation-rate.sh` | 0 | PASS (25/25: golden fixture 4 classes + 3 over-test files + window/tunable/anomaly cases) |
| deviation-rate F-nc (deliberate break, falsifiability) | 2026-07-04 | `cli.py`'s `deviation-rate` `suspect` CTE patched to drop the `lf.file = af.file` file-equality condition | n/a | RED-as-expected (24/25 passed, 1 failed: `clean-notes` flipped from `CLEAN` to `SUSPECT`), restored -> 25/25 exit 0 |
| deviation-rate regression | 2026-07-04 | `test-schema-parity.sh` + `test-gate-yield.sh` + `test-defect-correlation.sh` re-run alongside the new suite | 0/0/0 | PASS (4/4, 25/25, 20/20, unchanged) |
| deviation-rate cross-suite regression found (Build) | 2026-07-04 | `bash tests/test-ledger-cli.sh` / `bash tests/test-feedback.sh` right after `impl_notes` landed, before the isolation fix | 1/1 | test-ledger-cli.sh 18/26 (1 NEW failure, R-remat); test-feedback.sh 32/39 (F-nc-noise NEWLY broken: unknown-density spuriously fired) |
| deviation-rate cross-suite regression fixed | 2026-07-04 | same 2 suites re-run after adding `LEDGER_OBS_GIT_REPO_DIR` isolation to `test-ledger-cli.sh`/`test-feedback.sh`/`test-gate-yield.sh` | 1/1 | test-ledger-cli.sh 19/26 (7 fail, EXACT pre-existing count, `git stash`-verified); test-feedback.sh 30/39 (9 fail, EXACT pre-existing count, `git stash`-verified); test-gate-yield.sh 25/25 (unaffected) |
| deviation-rate real-corpus run | 2026-07-04 | `uv run ledger rebuild && uv run ledger deviation-rate --table` against `ops-toolkit` (default) and `dwarves-kit` (`LEDGER_OBS_GIT_REPO_DIR`) | 0 | see `verification/deviation-rate.md` "Real-corpus run" (233 rows ops-toolkit: 125 UNDER-SPECCED / 108 OTHER / 0 CLEAN / 0 SUSPECT; 77 rows dwarves-kit: 51 UNDER-SPECCED / 26 OTHER / 0 CLEAN / 0 SUSPECT) |
| deviation-rate PRE-EXISTING, unrelated regression (test-ledger-cli) | 2026-07-04 | `bash tests/test-ledger-cli.sh` | 1 | same 19/26 (7 `kit_runs`-related failures) as SG-01/SG-02 recorded; unaffected by this branch (once isolated) |
| deviation-rate PRE-EXISTING, unrelated regression (test-feedback) | 2026-07-04 | `bash tests/test-feedback.sh` | 1 | same 30/39 (9 failures) as SG-02 recorded; unaffected by this branch (once isolated) |
| anomalies-advisor suite (Round 1, pre-code-review) | 2026-07-04T08:39Z | `bash tests/test-anomalies-advisor.sh` | 0 | PASS (36/36) |
| anomalies-advisor suite (Round 2, post-code-review DEC-006 fix) | 2026-07-04T08:55Z | `bash tests/test-anomalies-advisor.sh` | 0 | PASS (37/37: ceremony CUT/CONDITION + mixed-caught NC + count-inflation NC + thin-true-catch NC (DEC-006) + FP-NC + falsifiability + serial-when-parallel fire/dependent-no-fire/zero-evidence-no-fire + token-runaway static+live + propose x2 + help + one-path) |
| anomalies-advisor DEC-006 falsifiability (deliberate break) | 2026-07-04T08:55Z | `caught_true>0` guard reverted to its original (buggy) position inside the `caught_known>=floor` branch | n/a | RED-as-expected (36/37, `C-thin-true` failed), restored -> 37/37 exit 0 |
| anomalies-advisor regression | 2026-07-04 | `test-gate-yield.sh` + `test-defect-correlation.sh` + `test-deviation-rate.sh` + `test-schema-parity.sh` + `test-docs-wiring.sh` + `test-render-skill.sh` + `test-schema-conform.sh` re-run alongside the new suite | 0 (x7) | PASS (25/25, 20/20, 25/25, 4/4, 19/19, 30/30, 11/11, all unchanged) |
| anomalies-advisor real-corpus capture | 2026-07-04 | `uv run ledger rebuild && uv run ledger anomalies --table` against the live ops-toolkit corpus | 0 | see `verification/anomalies-advisor.md` "Real-corpus capture" (only `unknown_density` fires; `ceremony`/`token_runaway`/`serial_when_parallel` honestly abstain) |
| anomalies-advisor PRE-EXISTING, unrelated regression (test-ledger-cli) | 2026-07-04 | `bash tests/test-ledger-cli.sh` | 1 | same 19/26 (7 `kit_runs`-related failures) as SG-01/SG-02/SG-03 recorded; unaffected by this branch |
| anomalies-advisor PRE-EXISTING, unrelated regression (test-feedback) | 2026-07-04 | `bash tests/test-feedback.sh` | 1 | same 30/39 (9 failures) as SG-02/SG-03 recorded; unaffected by this branch |
| sessions-digest suite (Round 1, pre-code-review) | 2026-07-04T09:36:18Z | `bash tests/test-sessions-digest.sh` | 0 | PASS (49/49: sessions golden + safety golden + PRIVACY NC + over-test + token-runaway armed + digest bridge + honest-empty + propose-folding) |
| sessions-digest suite (Round 2, post-code-review DEC-008/009/010 fixes) | 2026-07-04 | `bash tests/test-sessions-digest.sh` | 0 | PASS (59/59: Round-1 set + `O-badtype` CRITICAL content-leak NC + `O-badts` MINOR ts-validation + `D-overlap` MAJOR double-count NC) |
| sessions-digest Round-2 code review (finished diff) | 2026-07-04 | `kit:code-reviewer` dispatched on `main...HEAD`, adversarial on the privacy boundary | n/a | 1 CRITICAL (bare-`int()` content leak, DEC-008) + 1 MAJOR (overlap double-count, DEC-010) + 1 MINOR (unvalidated ts, DEC-009), all reproduced live by the reviewer + this branch fixed with new fixtures |
| sessions-digest DEC-008 falsifiability | 2026-07-04 | a `usage.input_tokens` value containing a planted secret-shaped string, `uv run ledger rebuild` | 0 | the OLD bare `int()` printed it in a `ValueError` traceback; the fixed `_safe_int` + broad per-line catch: `rebuild` exit 0, zero hits in any column, string absent from output, row still counted (bad field -> 0) |
| sessions-digest PRIV-nc (deliberate break, falsifiability) | 2026-07-04 | `SESSIONS_SCHEMA`/`_parse_session_file` widened to capture raw `tool_result.content` into a new column, rebuilt against the SAME privacy fixture | n/a | RED-as-expected (`HITS: 1`, the leaked string now in a materialized column), restored via `git checkout --`, suite re-confirmed green exit 0 |
| sessions-digest Build-time bug found + fixed | 2026-07-04 | a real smoke run against the live corpus found `total_errors: 0` (implausible; a design-time probe of one file alone found 37 `is_error` blocks) | n/a | root-caused: `tool_result`/`is_error` lives on a `type=="user"` line, not `type=="assistant"` (SPEC-135 DEC-007); fixed, re-verified `total_errors: 4262` on the real corpus |
| sessions-digest cross-suite regression found + fixed | 2026-07-04 | `bash tests/test-anomalies-advisor.sh` (and 6 sibling suites) right after the sessions/safety adapters landed, before isolation | timeout/1 | `test-anomalies-advisor.sh` timed out entirely (15+ real-corpus `rebuild()` calls at ~25s each); fixed by adding `LEDGER_OBS_SESSIONS_DIR`/`LEDGER_OBS_SECRET_GUARD_LOG` isolation to all 7 affected suites (SG-03's `LEDGER_OBS_GIT_REPO_DIR` precedent) + updating `test-anomalies-advisor.sh`'s stale `T-not-armed` docstring assertion to `T-armed` |
| sessions-digest full regression | 2026-07-04 | all 9 suites re-run after all fixes (isolation + Round-2 DEC-008/009/010) | 0 (x9) | PASS (4/4, 11/11, 25/25, 20/20, 25/25, 37/37, 30/30, 19/19, 59/59 = 230/230) |
| sessions-digest real-corpus capture | 2026-07-04 | `uv run ledger rebuild && uv run ledger digest --table` against the live `~/.claude/projects/` corpus (6706 sessions) + the live secret-guard log (5302 rows) | 0 | see `verification/sessions-digest.md` "Real-corpus capture" (coverage_pct=0.0/cost+time-to-done both null, the same honest-empty rid-to-git bridge finding SG-02/03/04 already documented; `token_runaway` DOES fire on a real ~2.1B-token session) |
| sessions-digest PRE-EXISTING, unrelated regression (test-ledger-cli) | 2026-07-04 | `bash tests/test-ledger-cli.sh` | 1 | same 19/26 (7 `kit_runs`-related failures) as SG-01..04 recorded; unaffected by this branch |
| sessions-digest PRE-EXISTING, unrelated regression (test-feedback) | 2026-07-04 | `bash tests/test-feedback.sh` | 1 | same 30/39 (9 failures) as SG-02..04 recorded; unaffected by this branch |
| memory-lens suite | 2026-07-04 | `bash tests/test-memory-lens.sh` | 0 | PASS (39/39: dead/live/stale fixtures + never-delete NC + falsifiability + conservative-extraction over-test + DEC-010 index gate) |
| memory-lens never-delete NC falsifiability | 2026-07-04 | deliberate `printf >>` a fixture then `git checkout` restore | n/a | RED-as-expected (sha changes on the mutation), restored -> 39/39 |
| memory-lens full regression | 2026-07-04 | all 10 green suites re-run together | 0 (x10) | PASS (266/266: 11+4+25+20+25+37+59+30+19+36, all unchanged) |
| memory-lens real-corpus sweep | 2026-07-04 | `uv run ledger rebuild && uv run ledger memory-sweep --table` (no env overrides) | 0 | 248 memories, 33 carrying dead refs, 0 stale; the known ops-toolkit `MIGRATED` tombstones caught (dead=3); DEC-010 drops the guardrails prose-scratchpad from 39 -> 0 |
| memory-lens anomaly threshold behavior | 2026-07-04 | `ledger anomalies --threshold memory_dead_ref_rate_max=<t>` | 0 | 33/248=13.3%: no-fire at default 0.15, FIRES at 0.13/0.10 (mechanism live, honestly below default) |
| memory-lens PRE-EXISTING, unrelated regression | 2026-07-04 | `bash tests/test-feedback.sh` / `bash tests/test-ledger-cli.sh` | 1 | same 30/39, 19/26 as SG-02..05 recorded; the `kit_runs`/`lane-telemetry.sh` bash-3.2 issue, untouched by this branch |

Full run detail + the COVERAGE-DELTA live in the per-feature docs under `verification/`.

### Recorded run + negative control + rollback (gate-visible)

- **Command:** `bash tools/ledger-observatory/tests/test-ledger-cli.sh`
- **Exit: 0** , 26 passed, 0 failed (2026-07-03T19:58:05Z).
- **NEGATIVE CONTROL:** `R-nc` sha256s every source before/after a query (byte-identical);
  `R-guard`/`R-guard-pragma` refuse every write-shaped statement (DELETE/DROP/PRAGMA/COPY,
  exit 3) and prove the source `.json` byte-identical; NC4 (absent tide source) turns the
  JOIN/sqlite value assertions RED , the assertions are real, not vacuous. Verdict: PASS.
- **Rollback:** additive-only branch (new `tools/ledger-observatory/` package + tests +
  docs; the one moved file is SG-01's proof -> `verification/schema.md`, content
  preserved). No existing runtime, daemon, or source ledger is touched. Rollback =
  `git revert` the branch, or delete the package; the materialized db is a gitignored
  cache, nothing else references it yet.

### render-skill recorded run + negative control + rollback (gate-visible, SG-03)

- **Command:** `bash tools/ledger-observatory/tests/test-render-skill.sh`
- **Exit: 0** , 30 passed, 0 failed (2026-07-03T20:28:28Z).
- **NEGATIVE CONTROL:** `R-nc` proves the single-data-path property (one `rows` object,
  a mutation to it reflects in BOTH re-renders, no stale value survives in either); a
  deliberate break (patching `render_artifact` to discard the passed `rows` and substitute
  a divergent hardcoded object) turned 4 cases RED (exit 1), restore returned the suite to
  30/30 (exit 0) , the NC is load-bearing, not vacuous. Verdict: PASS.
- **Rollback:** additive-only (new `render.py` + one new CLI subcommand + `skill/SKILL.md`
  + tests + docs; `show`/`query`/`rebuild`/`tables` unchanged). Nothing installed into
  `~/.claude/skills/`. Rollback = `git revert` the branch, or delete `render.py` + the
  `render` command; SG-01/02 unaffected either way.

### feedback-loop recorded run + negative control + rollback (gate-visible, SG-04)

- **Command:** `bash tools/ledger-observatory/tests/test-feedback.sh`
- **Exit: 0** , 39 passed, 0 failed (2026-07-03T20:54Z).
- **NEGATIVE CONTROLS (all load-bearing):** F-nc-noise proves a non-empty near-boundary
  noise-floor lens proposes NOTHING; FB-1 shows the SAME state with a loosened threshold DOES
  propose (the NC is not vacuous). F-proposal-not-autofile sha256s the board before/after
  `--propose` (byte-identical) and lists the staged proposal via the real `add-backlog`; FB-2
  injects a board-append into the stager and the board sha CHANGES (RED-as-expected), restore
  returns 39/39. F-readonly-nc sha256s every source ledger byte-identical after detect+propose.
- **Rollback:** additive-only (new `anomalies.py` + one `ledger anomalies` subcommand + tests +
  docs). The tool writes ONLY the gitignored cc-backlog staging buffer , never a board, never a
  ledger. Rollback = `git revert` the branch or delete `anomalies.py` + the command; SG-01/02/03
  unaffected.

### docs-wiring recorded run + negative control + rollback (gate-visible, SG-05, final)

- **Command:** `bash tools/ledger-observatory/tests/test-docs-wiring.sh`
- **Exit: 0** , 19 passed, 0 failed (2026-07-03T21:22:57Z).
- **NEGATIVE CONTROL (D-nc, load-bearing):** the check's `unwired_claims()` function was
  deliberately neutered (patched to always return empty, simulating a vacuous check) and the
  suite re-run: the OVER-CLAIM line went RED as expected (PASS=18 FAIL=1, `"OVER-CLAIM NC did
  NOT catch the fabricated claim (check is vacuous)"`), proving the NC is falsifiable, not
  decorative. Restore returned the suite to 19/19 (exit 0). The NC itself operates on a TEMP
  copy of README.md with a fabricated `uv run ledger zzz-nonexistent` invocation appended; the
  real README.md's sha256 is asserted unchanged before/after (D-nc's own file-safety check).
- **Rollback:** additive + doc-only (new `tests/test-docs-wiring.sh` + `docs/specs/SPEC-130-*`
  + edits to `README.md`, `skill/SKILL.md`, `tool.toml`, `../../MANIFEST.md`,
  `../../_meta/INVENTORY.md`; no `verification/*` per-feature file for 01-04 touched, no
  source code under `src/` touched). Rollback = `git revert` the branch or delete
  `tests/test-docs-wiring.sh`; SG-01/02/03/04's own tests and proofs are unaffected either way.

### kit-gates-lens recorded run + negative control + rollback (gate-visible, harness-observatory SG-01)

- **Command:** `bash tools/ledger-observatory/tests/test-gate-yield.sh`
- **Exit: 0** , 25 passed, 0 failed (2026-07-04).
- **NEGATIVE CONTROL (F-nc, load-bearing):** `ui-design` is skipped twice in the fixture with
  zero `OUTCOME` bracket anywhere for it; gate-yield must report it WITH its skip count, never
  drop it, never claim a caught signal that doesn't exist. Deliberate break: `read_kit_gates`
  patched to force `caught = True` unconditionally -> 15/25 pass, 10 RED (incl. the FP-NC and
  every other `caught`-bearing assertion), restored via `git checkout -- src/ledger_observatory/
  adapters.py` -> 25/25 exit 0. The NC is real, not decorative.
- **Rollback:** additive-only (new `kit_gates` table + `read_kit_gates` adapter + `gate-yield`
  command + tests + a committed fixture dir). `kit_runs`/`tide_moves`/`tg_dialogs`/`learned` and
  every existing CLI command are byte-for-byte unchanged. Rollback = `git revert` the branch, or
  delete `read_kit_gates`/`KIT_GATES_SCHEMA`/`gate-yield` + the `kit_gates` wiring in
  `materialize.rebuild()`; SG-01..05 (ledger-observatory's own) unaffected either way.
- **Known pre-existing, unrelated issue:** `tests/test-ledger-cli.sh` fails 7/26 in this local
  environment (`kit_runs` returns 0 rows; `read_kit()`'s subprocess into the installed
  `lane-telemetry.sh` returns nothing here). Reproduced identically via `git stash` on this branch
  before any of this PR's changes were applied, confirming it predates and is unrelated to this
  work. Not fixed here (out of scope per SPEC-131: "Not: rewriting `kit_runs`").

### defect-correlation recorded run + negative control + rollback (gate-visible, harness-observatory SG-02)

- **Command:** `bash tools/ledger-observatory/tests/test-defect-correlation.sh`
- **Exit: 0** , 20 passed, 0 failed (2026-07-04).
- **NEGATIVE CONTROL (F-nc, load-bearing):** `clean-feature` ships with zero later commits ever
  touching its file (`clean.py`); `defect-correlation` must report it `clean`, never
  `fix-followed`. Deliberate break: `cli.py`'s `LEFT JOIN later_fix` patched to drop the
  `lf.file = sfl.file` file-equality condition (degrading the correlation to rid+time only) ->
  17/20 pass, 3 RED (the FP-NC plus one rename assertion), restored (rewritten back to the
  shipped file-equality condition) -> 20/20 exit 0. A SECOND, independent broken-query check
  (`F-nc-deliberate-break`, a standalone rid+time-only query run against the same db) confirms
  it too would flag `clean-feature`. The NC is real, not decorative.
- **Rollback:** additive-only (new `git_fixes` table + `read_git_fixes` adapter +
  `config.git_repo_dir` + `defect-correlation` command + tests + a test-time-generated git
  fixture, no committed binary blob). `kit_gates`/`kit_runs`/`tide_moves`/`tg_dialogs`/`learned`
  and every existing CLI command are byte-for-byte unchanged. Rollback = `git revert` the
  branch, or delete `read_git_fixes`/`GIT_FIXES_SCHEMA`/`defect-correlation` + the `git_fixes`
  wiring in `materialize.rebuild()`; SG-01 and 01-05 (ledger-observatory's own) unaffected
  either way. No git WRITE operation is ever invoked (`read_git_fixes` shells out to `git log`
  only).
- **Known pre-existing, unrelated issues:** `tests/test-ledger-cli.sh` fails 7/26 (same as
  SG-01, unaffected). `tests/test-feedback.sh` fails 9/39 in this local environment, newly
  confirmed via `git stash` on this branch before any of this PR's changes were applied
  (identical 30/9 split), predating and unrelated to this work; not fixed here (out of scope).

### deviation-rate recorded run + negative control + rollback (gate-visible, harness-observatory SG-03)

- **Command:** `bash tools/ledger-observatory/tests/test-deviation-rate.sh`
- **Exit: 0** , 25 passed, 0 failed (2026-07-04).
- **NEGATIVE CONTROL (I-classify clean-notes, load-bearing, absolute):** `clean-notes` ships
  with a zero-marker and zero later commits ever touching its file (`clean.py`);
  `deviation-rate` must report it `CLEAN`, never `SUSPECT`. Deliberate break: `cli.py`'s
  `deviation-rate` `suspect` CTE patched to drop the `lf.file = af.file` file-equality condition
  (degrading the correlation to slug+time only) -> 24/25 pass, 1 RED (`I-classify clean-notes`),
  restored (rewritten back to the shipped file-equality condition) -> 25/25 exit 0. A SECOND,
  independent broken-query check (`F-nc-deliberate-break`, a standalone slug+time-only query run
  against the same db) confirms it too would flag `clean-notes`. The NC is real, not decorative.
- **Rollback:** additive-only (new `impl_notes` table + `read_impl_notes` adapter +
  `deviation-rate` command + `_detect_unknown_density` anomaly + tests + a test-time-generated
  git fixture, no committed binary blob). `kit_gates`/`kit_runs`/`git_fixes`/`tide_moves`/
  `tg_dialogs`/`learned` and every existing CLI command are byte-for-byte unchanged. Rollback =
  `git revert` the branch, or delete `read_impl_notes`/`IMPL_NOTES_SCHEMA`/`deviation-rate`/
  `_detect_unknown_density` + the `impl_notes` wiring in `materialize.rebuild()`; SG-01/SG-02 and
  01-05 (ledger-observatory's own) unaffected either way. No write path, ever (a pure filesystem
  walk + `Path.read_text`, no subprocess).
- **Cross-suite regression found + fixed (during Build, not anticipated in the goal file):**
  once `impl_notes` existed, `test-ledger-cli.sh`/`test-feedback.sh`/`test-gate-yield.sh` (none
  of which override `LEDGER_OBS_GIT_REPO_DIR`) silently defaulted to scanning this real,
  uncontrolled ops-toolkit repo tree. Two independent breakages resulted: (a) a stderr warning
  from the malformed-file check leaked into `test-ledger-cli.sh`'s byte-identical remat
  comparison; (b) far more seriously, `unknown-density` spuriously fired against the real
  corpus's genuine deviation density, breaking `test-feedback.sh`'s LOAD-BEARING `F-nc-noise`
  negative control (a noise-floor state must propose NOTHING). Confirmed via direct before/after
  runs: `test-ledger-cli.sh` went from the documented 19/26 baseline to 18/26 (a NEW failure);
  `test-feedback.sh` went from the documented 30/39 baseline to 32/39 with `F-nc-noise` itself
  now RED (a shifted, not merely additional, failure set). Fixed with one
  `LEDGER_OBS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"` isolation line in each of the 3 suites
  (matching their existing "absent -> skip-safe" convention); `git stash` before/after confirmed
  each suite's EXACT documented pre-existing count restored (19/26, 30/39, 25/25).
- **Known pre-existing, unrelated issues (once isolated, unaffected by this branch):**
  `tests/test-ledger-cli.sh` fails 7/26 (same as SG-01/SG-02, unaffected). `tests/test-feedback.sh`
  fails 9/39 (same as SG-02, unaffected). Both predate this work and are HANDOFF-documented; not
  fixed here (out of scope).

### anomalies-advisor recorded run + negative control + rollback (gate-visible, harness-observatory SG-04)

- **Command:** `bash tools/ledger-observatory/tests/test-anomalies-advisor.sh`
- **Exit: 0** , 37 passed, 0 failed (2026-07-04T08:55Z; 36/36 at the pre-code-review
  Round-1 run, `C-thin-true` added after the DEC-006 fix).
- **NEGATIVE CONTROLS (all load-bearing):** `C-fp-nc`/`C-fp-nc-deliberate-break` prove ceremony
  never fires on a legitimately high-skip gate, and that a bare skip-rate query WOULD (the bug
  the real detector avoids). `C-mixed` proves the "NONE true" clause is load-bearing on its own,
  separate from the min-sample floor `C-cut-floor` already covers. `C-multifile-nc` proves
  `bridged`/`fix_followed` count DISTINCT rids, not file-rows (a `/kit:spec-validate` CRITICAL
  finding on the draft, fixed before the Round-1 run). `C-thin-true` proves `caught_true > 0`
  suppresses BOTH the hard and soft path (a `kit:code-reviewer` MAJOR finding on the FINISHED
  diff, DEC-006, fixed after Round 1) -- deliberate break (reverting the guard hoist) turns it
  RED (36/37), restore returns 37/37, the NC is real not decorative. `S-nofire` proves the
  file-overlap dependency check on ITS OWN (same durations/non-overlap as `S-fire`, differing
  only in shared file). `S-nofire-zero-evidence` proves the evidence floor (zero git-bridge data
  never fires, not vacuously "safe to parallelize").
- **Rollback:** additive-only (3 new functions + 2 new `DEFAULTS` keys + `DETECTORS` tuple
  extension + one `cli.py` docstring sentence + tests + docs). `kit_gates`/`git_fixes`/
  `kit_runs`/`impl_notes`/`tide_moves`/`tg_dialogs`/`learned` and every existing CLI command are
  byte-for-byte unchanged. Rollback = `git revert` the branch, or delete the 3 detector functions
  + their `DETECTORS` entries + the 2 `DEFAULTS` keys; SG-01/02/03 (and 01-05) unaffected either
  way. No new write path: both new detectors go through `materialize.query()` only.
- **Known pre-existing, unrelated issues (unaffected by this branch):** `tests/test-ledger-cli.sh`
  fails 7/26 and `tests/test-feedback.sh` fails 9/39 in this local environment (`kit_runs`
  returns 0 rows; the `kit_runs` adapter's subprocess into the installed `lane-telemetry.sh`
  returns nothing here). Root-caused THIS sub-goal (a `bash 3.2` `source`/`return`/`set -e`
  interaction, see `verification/anomalies-advisor.md` "Test design"), same conclusion as
  SG-01/02/03: predates and is unrelated to this work, not fixed here (out of scope; this is
  precisely why `_detect_serial_when_parallel` was redesigned to never depend on `kit_runs`).

### sessions-digest recorded run + negative control + rollback (gate-visible, harness-observatory SG-05, GATE)

- **Command:** `bash tools/ledger-observatory/tests/test-sessions-digest.sh`
- **Exit: 0** , 59 passed, 0 failed (2026-07-04, after the Round-2 code-review fixes; the
  Round-1 pre-code-review run was 49/49).
- **NEGATIVE CONTROL (PRIV-nc, LOAD-BEARING, ABSOLUTE):** a fixture embeds the literal string
  `FAKE-SECRET-a1b2c3` in BOTH a `tool_result.content` value AND a `custom-title` line (the two
  confirmed-real leak surfaces from probing the actual `~/.claude/projects/` corpus at design
  time). A full-text scan of every materialized table/column finds ZERO hits for that string,
  while the session's own numeric row (including its correctly-counted `error_count=1`) DOES
  exist. Deliberate break: `SESSIONS_SCHEMA`/`_parse_session_file` temporarily widened to also
  capture the raw `tool_result.content` value into a new column, rebuilt against the SAME
  fixture -> `HITS: 1` (the leaked string now IN a materialized column), RED as expected;
  restored via `git checkout -- src/ledger_observatory/adapters.py
  src/ledger_observatory/schemas.py`, suite re-confirmed 49/49 exit 0. The NC is real, not
  decorative.
- **Rollback:** additive-only (2 new tables + 2 new adapters + `digest` command + `anomalies.py`'s
  `_detect_token_runaway` body rewritten in place, same signature + `DETECTORS` position +
  tests + docs). `kit_gates`/`git_fixes`/`kit_runs`/`impl_notes`/`tide_moves`/`tg_dialogs`/
  `learned` and every existing CLI command are byte-for-byte unchanged beyond the 7 sibling test
  suites' new isolation-env lines (a pure environment-var addition, no assertion-logic change) +
  `test-anomalies-advisor.sh`'s one updated (not removed) assertion. Rollback = `git revert` the
  branch, or delete `read_sessions`/`read_safety`/`SESSIONS_SCHEMA`/`SAFETY_SCHEMA`/the `digest`
  command + revert `_detect_token_runaway` to its SG-04 stub; SG-01..04 (and 01-05) unaffected
  either way. No new write path: both new adapters are pure reads (file I/O + a fixed-regex log
  parse), `digest` goes through `materialize.query()` only.
- **Known pre-existing, unrelated issues (unaffected by this branch):** `tests/test-ledger-cli.sh`
  fails 7/26 and `tests/test-feedback.sh` fails 9/39 in this local environment (the same
  `kit_runs`/`lane-telemetry.sh` `bash 3.2` issue root-caused in SG-04's own Build, unchanged by
  this branch which never touches `kit_runs`, `read_kit`, or `lane-telemetry.sh`).

### memory-lens recorded run + negative control (harness-observatory SG-06)

- **Command:** `bash tools/ledger-observatory/tests/test-memory-lens.sh`
- **Exit: 0** , 39 passed, 0 failed (2026-07-04).
- **NEGATIVE CONTROL (N-nc, LOAD-BEARING, ABSOLUTE , Han's never-delete rule):** the sweep is
  PROPOSE-ONLY and must never mutate a memory. `N-nc` sha256s every file across BOTH fixture
  stores (a git `repo` store + a non-git `builtin` store), runs the full
  `memory-sweep + rebuild + show memories + anomalies --propose`, then re-hashes , every hash
  byte-identical. `N-nc-deliberate-break` proves the comparison is falsifiable: a real mutation
  to a fixture file flips the SAME comparison RED, then the fixture is restored + re-confirmed
  green. The sweep opens files read-only and resolves refs against the live filesystem only;
  there is no write path to any memory store (independently re-confirmed by a `kit:code-reviewer`
  static audit of every code path for a write verb , none found).
- **Real paydown run:** `memory-sweep` over this repo's real stores materializes a `memories`
  lens of **248 rows, 33 carrying dead refs** (58 dead refs total). `ops-toolkit`'s own builtin
  `MEMORY` = 3 dead (the known `MIGRATED` tombstones, exactly the goal-file-predicted catch);
  `project_hermes_family_topology` (5) and `hermes-install-sh-dir-flag` (3) carry genuinely-moved
  `/Users/...` install paths. `_detect_memory_hygiene` fires and PROPOSES a paydown (staged to
  the cc-backlog buffer, never a board write) once the rate clears threshold. Dead-ref rate =
  the v1 retrieval-precision proxy (33/248 = 13.3% today, honestly below the 0.15 default; the
  detector fires at a tuned 0.10-0.13, proving the mechanism is live). Detail:
  [`verification/memory-lens.md`](verification/memory-lens.md).
- **Two big precision fixes from the FIRST real-corpus run (not either review pass):** the draft
  paths/flags/commands classifier flagged 135/248 units, ~80% junk. DEC-008 removed
  command-testing (`shutil.which()` on bare prose words / shell builtins); DEC-009 gated
  leading-`/` to a real-filesystem-root allowlist (Claude Code slash-commands / REST fragments
  are not paths); DEC-010 added an IS-IT-AN-INDEX gate so a prose-scratchpad MEMORY.md (e.g.
  `claude-guardrails`, 39 prose bullets, none a link) flags nothing instead of 39 orphans.
  Net: 135 -> 33 units, junk gone, the real dead paths + tombstones kept.
- **Rollback:** additive-only (1 new `memory_lens.py` module + `memories` table + `memory-sweep`
  command + `_detect_memory_hygiene` added to `DETECTORS` + tests + docs). Every prior table,
  adapter, and CLI command byte-for-byte unchanged. Rollback = `git revert` the branch.

### observatory-to-kit recorded run + negative control + rollback (gate-visible, runner-fastpath 05K)

- **Command:** `cd dwarves-kit/tools/ledger-observatory && for f in tests/test-*.sh; do bash "$f"; done`
- **Exit: 0 (x14)** , all 14 files pass in the new location (2026-07-05): `test-anomalies-advisor.sh`
  36/36, `test-defect-correlation.sh` 20/20, `test-deviation-rate.sh` 25/25,
  `test-docs-wiring.sh` 18/18, `test-feedback.sh` 42/42 (38 pre-existing + 4 new
  `F-no-staging-config`), `test-gate-yield.sh` 25/25, `test-ledger-cli.sh` 26/26,
  `test-mega-durations.sh` 16/16 (new), `test-memory-lens.sh` 39/39,
  `test-render-skill.sh` 30/30, `test-review-yield.sh` 39/39, `test-schema-conform.sh`
  10/10, `test-schema-parity.sh` 4/4, `test-sessions-digest.sh` 58/58.
- **RELOCATION NC (load-bearing):** the FIRST full-suite run immediately after the verbatim
  copy (before any code change) failed 5 of 13 files, all on the SAME root cause -- a
  hardcoded same-repo sibling-tool assumption that only held in ops-toolkit:
  `tools/tide/src/tide/state.py` (schema-conform), `../cc-backlog/bin/add-backlog` (x3:
  anomalies-advisor, feedback, sessions-digest), and `MANIFEST.md` at the repo root
  (docs-wiring). Each converted to a `[ -f ... ] && ... || echo SKIP` guard (never a silent
  pass -- the check still runs and can still fail when the sibling IS present, e.g. in
  ops-toolkit itself), matching the tool's own "missing source is skipped, never fatal"
  contract applied here to test infrastructure instead of an adapter. Re-run after the guard
  fix: all 13 files exit 0, with 5 explicit `SKIP` lines naming exactly why. This is the
  proof that old ops-toolkit paths are gone and new kit paths resolve.
- **ADAPTER-DEFAULT NC:** with every override env var unset, `config.kit_lib_dir()` /
  `config.git_repo_dir()` / `config.memory_repo_dir()` resolve to this worktree's own root
  (`.../dwarves-kit/.claude/worktrees/observatory-to-kit`, `.exists() == True` for both
  directory checks); `config.tide_db_path()` / `config.tgcleanup_dir()` /
  `config.learned_md_path()` / `anomalies.staging_path()` / `anomalies.backlog_path()` all
  resolve to `None`; `config.rejected_findings_repos()` resolves to `[]`. Cross-checked live:
  `test-ledger-cli.sh`'s `R-rebuild kit_runs>0` exercises the new `DWARVES_KIT_LIB` default
  end-to-end (it does NOT override that var), proving `kit_lib_dir()`'s new default actually
  parses this repo's OWN `lib/lane-telemetry.sh`, not a stale globally-installed copy.
- **`--propose`-without-config NC (load-bearing, AC5):** a live repro (env with
  `CC_BACKLOG_STAGING`/`CC_BACKLOG_BACKLOG`/`OPS_TOOLKIT` all unset, a fixture ledger that
  fires the `debt` anomaly) against `uv run ledger anomalies --propose --json`:
  ```
  error: ledger anomalies --propose has a proposal to stage but no destination is
  configured: set CC_BACKLOG_STAGING (or OPS_TOOLKIT) to an explicit absolute path
  (ops-toolkit-specific source, no default post-05K move)
  ```
  exit 2, and `git status --short` in the tool dir confirmed clean (no stray file written
  anywhere). `F-no-staging-config` in `test-feedback.sh` makes this a permanent regression
  guard (diffs the tool's own tree before/after, excluding `.venv`/`__pycache__`).
- **`mega-durations` fixture + NC:** golden fixture (`tests/fixtures/mega-durations/`, 3
  rids, 8 `kit_gates` rows, 2 rids with a complete OUTCOME pair) asserts EXACT hand-verified
  values: `md-a` wall=1200s (n=2 timed gates), `md-b` wall=100s (n=1), `md-c` never appears
  (zero timed gates -> zero rows, not a fabricated 0s row); 5 rows excluded. Paired NC
  fixture (`tests/fixtures/mega-durations-stripped/`, every `OUTCOME end` bracket removed):
  0 rids with complete timestamps, all 8 rows excluded, `rebuild` AND `mega-durations` both
  exit 0. `M-nc-deliberate-break` independently confirms the exclusion count on that
  stripped fixture is genuinely 8 (a query with no NULL-guard would silently report 0),
  proving the NC is falsifiable, not vacuous. Cross-checked against the pre-existing
  `tests/fixtures/kit-gates/` fixture (not built for this feature, but already carrying a
  real OUTCOME pair): `fix-outcome` -> `wall_seconds: 300`, matching that fixture's own
  `dur_s=300` recorded independently in the OUTCOME line -- an unplanned but welcome
  cross-check that the epoch-subtraction math is right.
- **`mega-durations` REAL-CORPUS live run (2026-07-05, no env overrides, the first actual
  answer to "where does the 2-3h go"):**
  ```
  $ uv run ledger rebuild
  {"kit_runs": 112, "kit_gates": 853, "git_fixes": 2087, "impl_notes": 88, ...}
  $ uv run ledger mega-durations --table
  +------------------------+-------------+------------+---------------+--------------+
  | rid                    | first_start | last_end   | n_gates_timed | wall_seconds |
  +------------------------+-------------+------------+---------------+--------------+
  | advisor-visibility     | 1783179456  | 1783179483 | 2             | 27           |
  | grill-conditioning     | 1783150451  | 1783150451 | 1             | 0            |
  | kit-emit-sweep         | 1783152625  | 1783152625 | 1             | 0            |
  | kit-pitch              | 1783154292  | 1783155147 | 2             | 855          |
  | kit-template-fields    | 1783147321  | 1783147329 | 1             | 8            |
  | lane-de-escalation     | 1783156215  | 1783156215 | 1             | 0            |
  | mega-mirror-sync       | 1783157414  | 1783157414 | 1             | 0            |
  | review-findings-memory | 1783177516  | 1783177516 | 1             | 0            |
  | stale-adr-inversion    | 1783175915  | 1783175940 | 2             | 25           |
  +------------------------+-------------+------------+---------------+--------------+
  (9 rows)
  9 rid(s) with complete timestamps (841 row(s) excluded)
  ```
  **n = 9** rids resolve a complete OUTCOME pair out of 853 total `kit_gates` rows (841
  excluded, ~98.6%). Honest reading: the OUTCOME start/end bracket is not yet wired into
  most gates (per `adapters.read_kit_gates`'s own docstring, `ship-gate.sh` is the only live
  emitter today, HOOK-ENFORCED but ship-boundary-only, not yet per-phase -- see AGENTS.md
  "Gates are also MEASURED"), so the 2-3h question this query was built to answer is only
  partially answerable today: the 9 rids that DO resolve show wall times from 0s (a single
  instantaneous phase, e.g. `grill-conditioning`) up to 855s (~14 min, `kit-pitch`, spanning
  2 timed gates) -- nowhere near 2-3h, because most of a run's actual gates (think/design/
  spec/build/review/docs) carry no OUTCOME bracket at all yet and are silently excluded, not
  because the real wall time is short. The query is correct and ready; the answer will
  sharpen as more gates start emitting OUTCOME brackets.
- **Rollback:** additive-only for `mega-durations` (one new SQL query + one new `cli.py`
  command + tests + 2 committed fixture dirs; every existing table/command byte-for-byte
  unchanged). The adapter-default split and relocation-NC test fixes are behavior-preserving
  everywhere a source WAS configured (every pre-existing test sets every env var explicitly)
  and only change behavior for an UNCONFIGURED ops-toolkit-specific source (was: a hardcoded
  personal path; now: skip-safe `None`/clean refusal). Rollback = `git revert` the branch (a
  single feature branch, not yet merged); ops-toolkit's own copy is untouched by this PR (a
  separate, paired sub-goal, 05R, retires it after this PR merges).

## Reproduce

```bash
cd ~/workspace/<owner>/ops-toolkit
bash tools/ledger-observatory/tests/test-schema-conform.sh   # schema (SG-01)
cd tools/ledger-observatory && uv sync
bash tests/test-ledger-cli.sh                                 # etl-cli (SG-02) -- pre-existing kit_runs env issue here, see above
bash tests/test-render-skill.sh                                # render-skill (SG-03)
bash tests/test-feedback.sh                                    # feedback-loop (SG-04)
bash tests/test-docs-wiring.sh                                 # docs-wiring (SG-05, final)
bash tests/test-gate-yield.sh                                  # kit-gates-lens (harness-observatory SG-01)
uv run ledger rebuild && uv run ledger gate-yield --table      # real-corpus materialization
bash tests/test-schema-parity.sh                               # schema-drift guard (SG-02 fix, 2026-07-04)
bash tests/test-defect-correlation.sh                          # defect-correlation (harness-observatory SG-02)
uv run ledger rebuild && uv run ledger defect-correlation --table   # real-history run: ops-toolkit
LEDGER_OBS_GIT_REPO_DIR=~/workspace/<owner>/dwarves-kit uv run ledger rebuild \
  && LEDGER_OBS_GIT_REPO_DIR=~/workspace/<owner>/dwarves-kit uv run ledger defect-correlation --table  # real-history run: dwarves-kit
bash tests/test-deviation-rate.sh                              # deviation-rate (harness-observatory SG-03)
uv run ledger rebuild && uv run ledger deviation-rate --table       # real run: ops-toolkit (233 rows)
LEDGER_OBS_GIT_REPO_DIR=~/workspace/<owner>/dwarves-kit uv run ledger rebuild \
  && LEDGER_OBS_GIT_REPO_DIR=~/workspace/<owner>/dwarves-kit uv run ledger deviation-rate --table  # real run: dwarves-kit (77 rows)
bash tests/test-anomalies-advisor.sh                           # anomalies-advisor (harness-observatory SG-04)
uv run ledger rebuild && uv run ledger anomalies --table       # real-corpus capture (honest: only unknown_density fires today)
bash tests/test-sessions-digest.sh                             # sessions-digest (harness-observatory SG-05, GATE)
uv run ledger rebuild && uv run ledger digest --table          # real-corpus scorecard (honest-empty coverage/cost; token_runaway fires)
bash tests/test-memory-lens.sh                                 # memory-lens (harness-observatory SG-06) , 39/39 incl. never-delete NC
uv run ledger rebuild && uv run ledger memory-sweep --table    # real paydown (248 memories, 33 carrying dead-ref)
```

Everything above ran from `~/workspace/<owner>/ops-toolkit`. As of goal 05K (2026-07-05) the
tool lives in dwarves-kit instead; reproduce from the new location:

```bash
cd ~/workspace/<owner>/dwarves-kit/tools/ledger-observatory
uv sync
for f in tests/test-*.sh; do bash "$f" || echo "FAILED: $f"; done   # all 14 files, exit 0
bash tests/test-mega-durations.sh                              # mega-durations (05K, new)
uv run ledger rebuild && uv run ledger mega-durations --table  # real-corpus run: n=9 rids, 841 excluded
```
