# Proof of done: ledger-observatory feature `sessions-digest` (harness-observatory mega-goal, SG-05)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `sessions-digest` feature
> detail.

> **GATE (Han's review point before merge):** the extracted-field whitelist enforced by this
> feature (verbatim in `_meta/megagoals/harness-observatory/DECISIONS.md`) IS the privacy
> boundary. Nothing here should be treated as "done" until that whitelist is reviewed against
> what actually leaves this repo's private transcript store.

| | |
|---|---|
| **Profile** | data/CLI tool (behavioral, read-only) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Spec** | [`../specs/SPEC-135-sessions-digest.md`](../specs/SPEC-135-sessions-digest.md) |

## Test design

`tests/test-sessions-digest.sh` builds session transcript `*.jsonl` fixtures directly (plain
heredocs, one JSON object per line -- the real shape confirmed by probing this machine's own
`~/.claude/projects/` corpus before writing `adapters.py`), a fixture secret-guard log (the same
bracket-shape confirmed against the real `~/.cache/claude-secret-guard.log`), and (for the
digest bridge test) a `kit_gates` run-ledger + a generated git repo, same precedent as
`test-defect-correlation.sh`/`test-deviation-rate.sh`/`test-anomalies-advisor.sh`
(SPEC-132 DEC-005).

**A real Build-time bug was found and fixed, not anticipated by the spec's own field
whitelist** (SPEC-135 DEC-007): the first pass only scanned `content[]` on `type=="assistant"`
lines, so `error_count` silently stayed 0 across the ENTIRE real corpus -- confirmed via a real
smoke run (`total_errors: 0` over 6706 sessions), despite an earlier design-time probe of one
file alone finding 37 `is_error: true` blocks. Root-caused: Claude Code synthesizes the tool
result back to the model as the NEXT turn, `type=="user"`, not a continuation of the assistant
turn that emitted the matching `tool_use`. Fixed: `_parse_session_file` now ALSO scans
`type=="user"` lines, but strictly ONLY for `content[].type=="tool_result"`/`.is_error` -- a
user line's own `text` (Han's raw prompt) is never read, a STRICTER rule than the assistant-text
case (which is at least read transiently for the canary check). No new field joined the
whitelist; the same two already-whitelisted fields are read from one more line-type than
originally planned.

**A real cross-suite regression was found and fixed during Build**: every EXISTING suite's
`ledger rebuild` call defaulted `read_sessions`/`read_safety` to the REAL
`~/.claude/projects/` (2.1GB across 8179 files) and the real secret-guard log the instant this
sub-goal's adapters landed, since none of those suites isolated the two new env knobs.
`test-anomalies-advisor.sh` timed out entirely (15+ `rebuild()` calls x ~25s of real-corpus
scanning each, well past the harness's 2-minute cap). Fixed by adding
`LEDGER_OBS_SESSIONS_DIR`/`LEDGER_OBS_SECRET_GUARD_LOG` isolation (pointed at a nonexistent
fixture path) to all 7 affected suites, the SAME class of fix SG-03 already applied for
`LEDGER_OBS_GIT_REPO_DIR`. `test-anomalies-advisor.sh` ALSO needed one assertion update: its own
`T-not-armed` check asserted the literal string `"NOT ARMED"` in `anomalies.py`'s docstring --
now stale, since arming `_detect_token_runaway` against the new `sessions` table is this
sub-goal's own explicit scope. Updated (`T-armed`) to test the armed detector's honest-empty
abstention on that suite's own isolated (empty) sessions table instead.

## Fixtures

### Sessions golden (12 assertions, exact values)

One fixture file (`proj-golden/golden-session.jsonl`) with hand-computed KNOWN values across 8
lines: 2 `tool_use` calls (input/output/cache sums accumulate across both), 1 `tool_result`
`is_error=true` (on a separate `type=="user"` line, per DEC-007 above), 1 `compact_boundary`
system line, 2 terminal assistant turns (one WITHOUT the canary marker -> 1 drop, one WITH it ->
not counted). Every column in `SESSIONS_SCHEMA` (session_id, project_slug, first_ts, last_ts,
duration_s, input/output/cache_read/cache_creation tokens, tool_call_count, error_count,
compaction_count, canary_drop_count) is asserted to its exact expected value.

### Safety golden (8 assertions)

A fixture secret-guard log (5 lines: 2 `BLOCK`/`B1`, 1 `BYPASS` with no rule code, 1
`WARN`/`B9`, 1 `BYPASS` with a real file-path in its message) asserts exact per-status and
per-rule counts, PLUS a negative assertion that the free-text path (`/tmp/pt-fixture-path.json`,
`/some/real/fixture/secret-guard.sh`) never lands in the `session`/`tool` columns.

### PRIV-nc (LOAD-BEARING, absolute -- 4 assertions + the falsifiability run below)

| Fixture | Shape | Expected |
|---|---|---|
| `PRIV-nc-positive-control` | the raw fixture file, grepped directly (no adapter involved) | the string `FAKE-SECRET-a1b2c3` IS present (proves the fixture is a real test, not vacuous) |
| `PRIV-nc numeric row exists` | `sessions` table, filtered on the fixture's `session_id` | 1 row (the session was COUNTED, never silently dropped) |
| `PRIV-nc error_count` | same row | `1` (the numeric SIGNAL the leaky content carried is still captured correctly) |
| `PRIV-nc full-text scan` | every materialized table, every column, via `materialize.table_names()` + `materialize.show()` (the SAME read path `show`/`query` use, iterated in Python) | ZERO hits for the string, across EVERY table |

The fixture embeds `FAKE-SECRET-a1b2c3` in BOTH confirmed-real leak surfaces named in SPEC-135's
Problem section: a `tool_result.content` value AND a `custom-title` line.

### Over-test (10 assertions)

Malformed/truncated jsonl (a garbage line + a file with no trailing newline on its last line),
an empty session (zero timestamped lines -> no row, never a fabricated zero-duration row), a
multi-compaction session (3 `compact_boundary` lines -> `compaction_count=3`, not just 0-or-1),
`read_sessions`/`read_safety` skip-safe on a missing source, and a re-confirmation that the
safety golden's path-bearing message never lands in ANY safety column (not just `session`/
`tool`).

### Token-runaway armed (5 assertions)

Fires under a deliberately low `--threshold token_budget_max=100` (well below the golden
fixture's 494-token total), does NOT fire under the loose default (50M), and does NOT fire when
`sessions` is empty (the same honest-empty convention every other detector in `anomalies.py`
follows). `--help` lists the new `token_budget_max` key.

### Digest bridge (9 assertions)

Two `kit_gates` `ship`/`ran` rids, each bridged to git the same rid-in-subject way
`defect-correlation`/`ceremony`/`serial_when_parallel` already bridge: `digest-rid-1`'s commit
lands inside a fixture session's `[first_ts, last_ts]` window (time-containment); `digest-rid-2`'s
commit lands nowhere any fixture session covers (the honest-empty half). Asserts EXACT
`shipped_rids=2`, `bridged_rids=1`, `coverage_pct=50.0`,
`cost_per_verified_outcome_tokens=1650.0` (the bridged session's own token sum, 1 bridged rid),
`avg_time_to_done_min=5.0` (5 minutes from the session's start to the ship commit's timestamp). A
SECOND digest run (kit_gates cleared, sessions untouched) asserts the fully honest-empty case:
`shipped_rids=0`, `coverage_pct`/`cost_per_verified_outcome_tokens` both `null`, never a crash.

### Propose folding (3 assertions)

`ledger digest --propose` stages the SAME count as `ledger anomalies --propose` on the identical
lens state (one detection path, never a second), and the staged `token_runaway` proposal is
visible to the real `add-backlog` command.

## Confirmation run (recorded)

Command: `bash tests/test-sessions-digest.sh` -- 59/59 passed, 0 failed, exit 0 (2026-07-04, after the Round-2 code-review fixes above; the Round-1 pre-code-review run was 49/49).

```
== golden: a session file with KNOWN token/tool-call/error/compaction/canary counts ==
PASS  golden session_id
PASS  golden first_ts
PASS  golden last_ts
PASS  golden duration_s
PASS  golden input_tokens
PASS  golden output_tokens
PASS  golden cache_read_tokens
PASS  golden cache_creation_tokens
PASS  golden tool_call_count
PASS  golden error_count
PASS  golden compaction_count
PASS  golden canary_drop_count
== safety golden: a fixture secret-guard log with KNOWN per-status/per-rule counts ==
PASS  safety total rows
PASS  safety BLOCK count
PASS  safety BYPASS count
PASS  safety WARN count
PASS  safety B1 rule count
PASS  safety B9 rule count
PASS  safety NULL-rule count (BYPASS lines carry no rule code)
PASS  safety free-text path never captured into session/tool columns
== PRIV-nc (LOAD-BEARING, absolute): FAKE-SECRET-a1b2c3 in tool_result.content AND
PASS  PRIV-nc-positive-control: the raw fixture file DOES contain the secret (not vacuous)
PASS  PRIV-nc numeric row exists (session counted)
PASS  PRIV-nc error_count still correctly counted despite is_error's leaky content
PASS  PRIV-nc full-text scan across EVERY materialized table/column: ZERO hits
== over-test: malformed/truncated jsonl line does not crash the parse; valid lines
PASS  O-malformed still produces a row (valid lines survive a bad line)
PASS  O-malformed input_tokens only from the valid assistant line
PASS  O-malformed first_ts from the valid user line
== over-test: an empty session (zero timestamped lines) produces NO row ==
PASS  O-empty no row for a zero-timestamped-line file
== over-test: a multi-compaction session (3 compact_boundary lines) counts all 3 ==
PASS  O-multicompact compaction_count=3
== over-test (CRITICAL regression, SPEC-135 DEC-008): a usage field that is valid JSON
PASS  O-badtype rebuild exits 0 (no uncaught exception)
PASS  O-badtype planted string never appears in the rebuild output/traceback
PASS  O-badtype row still exists (bad field coerced to 0, row not dropped)
PASS  O-badtype input_tokens=30 (bad string field counted as 0, only the valid line contributed)
PASS  O-badtype full-text scan: the bad usage string is in ZERO materialized columns
== over-test (MINOR, SPEC-135 DEC-009): a non-ISO8601 timestamp string is dropped (that
PASS  O-badts first_ts is the VALID iso line, never the junk string
PASS  O-badts the junk timestamp string is nowhere in first_ts/last_ts
== over-test: read_sessions/read_safety are skip-safe on a missing source ==
PASS  O-missing sessions-dir skip-safe
PASS  O-missing safety-log skip-safe
== over-test: a safety-log line with no rule code AND a path-bearing message is never
PASS  O-path-message never lands in ts/status either
== token_runaway: ARMED against sessions, fires over a low --threshold, not over the
PASS  T-default no fire under the loose default budget (494 total tokens)
PASS  T-low-threshold fires when --threshold token_budget_max=100 (below the 494 total)
PASS  T-low-threshold names the right session
PASS  T-empty no fire when sessions table is empty
PASS  H-help lists token_budget_max
== digest: sessions x kit_gates JOIN (time-containment bridge), coverage + cost +
PASS  D-shipped_rids
PASS  D-bridged_rids
PASS  D-coverage_pct
PASS  D-cost_per_verified_outcome_tokens (1650 total tokens / 1 bridged rid)
PASS  D-avg_time_to_done_min (5 min: session start 12:00 -> ship commit 12:05)
PASS  D-digest also folds in anomalies (unknown_density or another real signal may fire; the
== digest overlap (MAJOR regression, SPEC-135 DEC-010): TWO sessions both containing one
PASS  D-overlap bridged_rids=1 (one rid, one session, not two)
PASS  D-overlap cost=500 (ONLY the closest-preceding session B, NOT 1500 = A+B double-count)
PASS  D-overlap time-to-done=5.0 (from session B's OWN start 12:00, the SAME session as the cost)
== digest honest-empty: zero shipped rids -> NULL coverage/cost, never a crash ==
PASS  D-empty coverage_pct is null
PASS  D-empty cost_per_verified_outcome_tokens is null
PASS  D-empty shipped_rids=0
== digest --propose: stages via the SAME anomalies_mod.stage_proposals() path ==
PASS  P-digest-propose stages the SAME count as anomalies --propose (one path, not two)
PASS  P-digest-propose stages token_runaway
PASS  P-digest-propose add-backlog sees the staged proposal
== 59 passed, 0 failed ==
```

**PRIV-nc falsifiability (the load-bearing deliberate break, per this tool's established
convention of a manual patch-run-restore step, SPEC-131/132/133/134 precedent):** temporarily
widened `SESSIONS_SCHEMA` (a new `debug_leak_scratch VARCHAR` column) and `_parse_session_file`
(stashing the raw `tool_result.content` string of any `is_error` block into that column),
rebuilt against the SAME privacy fixture, and re-ran the full-text scan directly:

```
HITS: 1
('sessions', 'String to replace not found in file.\nString: FAKE-SECRET-a1b2c3 embedded in file text')
```

RED as expected -- the leaked text now appears in a materialized column, proving the NC is
load-bearing, not vacuous. Restored via `git checkout -- src/ledger_observatory/adapters.py
src/ledger_observatory/schemas.py`; `bash tests/test-sessions-digest.sh` re-confirmed the suite green,
exit 0 immediately after.

**Regression:** full suite re-run after all fixes, 230/230 total:
`test-schema-parity.sh` (4/4), `test-schema-conform.sh` (11/11), `test-gate-yield.sh` (25/25),
`test-defect-correlation.sh` (20/20), `test-deviation-rate.sh` (25/25),
`test-anomalies-advisor.sh` (37/37, after the `T-armed` update above),
`test-render-skill.sh` (30/30), `test-docs-wiring.sh` (19/19),
`test-sessions-digest.sh` (59/59). `test-ledger-cli.sh` (19/26) and `test-feedback.sh` (30/39)
reproduce the EXACT same documented pre-existing failure counts (`kit_runs`/`lane-telemetry`
bash-3.2 environment issue, see DECISIONS.md); this branch does not touch `kit_runs`,
`read_kit`, or `lane-telemetry.sh` at all.

## Real-corpus capture

Command: `uv run ledger rebuild && uv run ledger digest --table` against the live
`~/.claude/projects/` corpus (6706 sessions, all env knobs unset/defaulted) and the live
`~/.cache/claude-secret-guard.log` (5302 matched rows of 5339 total lines -- the ~0.7% gap is
lines that don't match the bracket-prefix shape at all, e.g. a stray blank line), 2026-07-04.

```
{
  "kit_runs": 0,
  "kit_gates": 727,
  "git_fixes": 9636,
  "impl_notes": 233,
  "tide_moves": 0,
  "tide_tier_b_calls": 0,
  "tg_dialogs": 625,
  "learned": 58,
  "sessions": 6706,
  "safety": 5302
}

== north-star scorecard ==
+----------------+--------------------+---------------------+-------------------------+-----------------------------+------------------+--------------+-------------------+--------------------+--------------+--------------+--------------+----------------------------------+----------------------+
| total_sessions | total_input_tokens | total_output_tokens | total_cache_read_tokens | total_cache_creation_tokens | total_tool_calls | total_errors | total_compactions | total_canary_drops | shipped_rids | bridged_rids | coverage_pct | cost_per_verified_outcome_tokens | avg_time_to_done_min |
+----------------+--------------------+---------------------+-------------------------+-----------------------------+------------------+--------------+-------------------+--------------------+--------------+--------------+--------------+----------------------------------+----------------------+
| 6706           | 131036410          | 207838607           | 44180754449             | 1392293605                  | 60960            | 4262         | 58                | 3816               | 65           | 0            | 0.0          |                                  |                      |
+----------------+--------------------+---------------------+-------------------------+-----------------------------+------------------+--------------+-------------------+--------------------+--------------+--------------+--------------+----------------------------------+----------------------+
(1 row)

== anomalies ==
+-----------------+-----------------------------------------------------------------+-----------------------------------------------------------------------------------------------------------------------------------+
| key             | title                                                           | metric                                                                                                                            |
+-----------------+-----------------------------------------------------------------+-----------------------------------------------------------------------------------------------------------------------------------+
| unknown_density | Feedback: implementation-notes deviation density over threshold | median=5 window=5                                                                                                                 |
| token_runaway   | Feedback: a session's token footprint over budget               | session_id=8ae69411-07d1-474e-a33d-64b1531ce251 project_slug=-Users-tieubao-workspace-tieubao-ops-toolkit total_tokens=2115144012 |
+-----------------+-----------------------------------------------------------------+-----------------------------------------------------------------------------------------------------------------------------------+
(2 rows)
```

**Honest yield note:** `coverage_pct`/`cost_per_verified_outcome_tokens`/`avg_time_to_done_min`
are all NULL/0.0 on the real corpus -- the SAME honest-empty finding SG-02/03/04 already
documented for this exact bridge (`defect-correlation` itself already returns 0 rows on this real
corpus; no real `kit_gates` rid's substring appears in any commit subject here today), now
reconfirmed a fourth time via a DIFFERENT bridge dimension (time-containment vs. file-equality).
`token_runaway` DOES fire (a real session used ~2.1 billion total tokens, dominated by
cache-read re-reads across a very long-running session, matching the module docstring's own
noted risk that cache-read is billed per-turn, not once) -- proving the armed detector is a real,
working signal on real data, not a fixture-only construct.

## COVERAGE-DELTA

| Covered | Uncovered (named, not hidden) |
|---|---|
| Every column of `SESSIONS_SCHEMA`/`SAFETY_SCHEMA`, exact-value asserted | Per-tool-name or per-model token breakdowns (explicit Out of Scope, SPEC-135) |
| The PRIVACY negative control across BOTH confirmed leak surfaces (`tool_result.content`, `custom-title`) + its falsifiability proof (a real schema/parser widen turning it RED, restored) | A leak surface this sub-goal did NOT probe for (e.g. a future transcript field not yet documented); named as an accepted limitation in SPEC-135's Failure modes |
| Malformed/truncated jsonl, empty session, multi-compaction, missing-source skip-safety, a valid-JSON-but-non-numeric usage field (`O-badtype`, the DEC-008 content-leak NC), a non-ISO8601 timestamp (`O-badts`, DEC-009) | A session file so large it slows `rebuild()` materially (named, not built, in SPEC-135's Failure modes) |
| `token_runaway` armed: fire / no-fire (default) / no-fire (empty table) | A per-rid token budget (DEC-004: deliberately a flat per-session check, not a bridged one) |
| `digest`'s time-containment bridge: exact bridged-rid values + the fully honest-empty case + the MULTI-session overlap dedup (`D-overlap`, DEC-010: closest-preceding session wins, cost NOT double-counted) | A three-way overlap resolution beyond the closest-preceding heuristic (e.g. proportional split); the heuristic is documented, not silently taken |
| `--propose` folding, proven identical to the direct `anomalies --propose` path | A combined single-DB-state test firing digest's anomalies AND the JOIN simultaneously (each already covered independently) |
| A real cross-suite regression found + fixed (7 suites isolated, 1 stale assertion updated); a Round-2 finished-diff code review that found 3 real issues (1 CRITICAL, 1 MAJOR, 1 MINOR), all fixed with falsifiable fixtures | -- |
| Real-corpus capture, honestly reporting the scorecard + why the JOIN is empty | -- |

## Reproduce

```bash
cd tools/ledger-observatory
bash tests/test-sessions-digest.sh
uv run ledger rebuild
uv run ledger digest --table
uv run ledger digest --propose --table   # stages any real anomaly into the staging buffer
```
