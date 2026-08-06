# Proof of done: ledger-observatory feature `review-yield-lens` (gate-review-absorptions mega-goal, SG-04)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `review-yield-lens` feature detail.

| | |
|---|---|
| **Profile** | data/CLI tool (behavioral, read-only) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Spec** | [`../specs/SPEC-137-review-yield-lens.md`](../specs/SPEC-137-review-yield-lens.md) |

## Test design

`tests/test-review-yield.sh` points `LEDGER_OBS_REPOS` at a COMMITTED fixture tree
(`tests/fixtures/review-yield/{repo-a,repo-b,repo-empty}/docs/verification/rejected-findings.md`)
and `DWARVES_KIT_LOG_DIR` at a COMMITTED review-gate fixture ledger dir
(`tests/fixtures/review-yield/runs/*.log`), same golden-fixture precedent `test-gate-yield.sh`
set. It asserts EXACT per-(repo, lens) `rejected_findings` values, EXACT `review-yield` numbers
(hand-verified), the honest-negative "rate exceeds 1.0, reported plainly" case, the
`suppressed=` exclusion, the `--min-n` tunable, the division-by-zero guard (a second
zero-review-activity state), the load-bearing honest-zero negative control (a LITERAL source
edit + restore, red -> green), the new `review_fp` anomaly detector (fires + propose-only), and
an over-test pass targeting `read_rejected_findings()` directly, before the standard
delete-and-rematerialize + read-only negative controls every suite in this tool already runs.

### Golden fixture (`tests/fixtures/review-yield/`)

| Path | Contents |
|---|---|
| `repo-a/docs/verification/rejected-findings.md` | `security` (2 rejected), `architecture` (1 rejected), `test-coverage` (6 rejected, the HIGH-N lens), plus a 3-cell malformed row and a non-`rejected`-verdict row (both skipped+counted); a `## Format` template row that must never be read as data |
| `repo-b/docs/verification/rejected-findings.md` | `security` (1 rejected) |
| `repo-empty/docs/verification/rejected-findings.md` | a real file, `## Rows` heading present, zero rows -- contributes nothing |
| (a 4th repo path in `LEDGER_OBS_REPOS` that does not exist on disk at all) | proves the "repo absent from `docs/verification/` entirely" skip-safe path |
| `runs/fx-review-1.log` | `review` ran, `findings=3 rejected=1` |
| `runs/fx-review-2.log` | `review` override, `findings=2 rejected=0 suppressed=1` (the `suppressed=` MUST NOT enter `raised`) |
| `runs/fx-review-3.log` | `review` **skipped** (excluded from the `ran`/`override` denominator entirely) |
| `runs/fx-review-4.log` | `review` ran, old-style `SHIP findings=0 (...)` (no `rejected=` token) + a completed `OUTCOME` bracket, `caught=true` |
| `runs/fx-review-5.log` | gate=`build` (a non-review gate; must never leak into `review-yield`) |

Hand-computed: `sum_findings = 3+2+0 = 5`, `sum_rejected = 1+0 = 1` (fx-review-4's absent
token contributes 0, never a cast error), `raised = 6`; `review_ran = 3` (fx-review-1/2/4;
fx-review-3's `skipped` outcome is excluded), `review_caught = 1` (fx-review-4's bracket).

## Confirmation run (recorded)

Command: `bash tests/test-review-yield.sh`, 2026-07-04 (UTC clock), exit 0.

```
== P-rebuild: rejected_findings materializes (repo-a x3 lenses + repo-b x1 lens; repo-empty/repo-missing-entirely contribute zero) ==
PASS  P-rebuild rejected_findings=4
PASS  P-rebuild kit_gates=5
== P-skip-warning: the 2 malformed rows in repo-a (too-few-cells, non-rejected verdict) are counted, not silent ==
PASS  P-skip-warning names a count
== P-rows: exact per-(repo, lens) rejected_findings values ==
PASS  P-rows repo-a/security n=2 first=2026-01-01 last=2026-01-05
PASS  P-rows repo-a/architecture n=1 (malformed+non-rejected rows never counted)
PASS  P-rows repo-a/test-coverage n=6 (high-n lens, the accepted-verdict row on 01-12 excluded)
PASS  P-rows repo-b/security n=1
PASS  P-rows repo-empty contributes NO row (file exists, zero real rows)
PASS  P-rows exactly 4 (repo, lens) rows total
== Y-yield: exact review-yield numbers (hand-verified against the fixture) ==
PASS  Y-yield repo-a/security: raised=6 fp_rate=0.333 low_n=true (n_rejected=2<5)
PASS  Y-yield repo-a/architecture: fp_rate=0.167 low_n=true
PASS  Y-yield repo-a/architecture fp_rate value
PASS  Y-yield repo-a/test-coverage: HIGH-N row, fp_rate=1.0 low_n=FALSE (both floors clear: n_rejected=6>=5, raised=6>=5)
PASS  Y-yield repo-b/security: fp_rate=0.167 low_n=true
PASS  Y-yield exactly 4 rows (one per (repo,lens); repo-empty absent)
== Y-honest-negative: test-coverage's fp_rate=1.0 is reported EXACTLY (never filtered/clamped) ==
PASS  Y-honest-negative a lens whose rejects equal the whole raised total still reports plainly
== Y-suppressed-excluded: suppressed=1 on fx-review-2 never contributes to raised ==
PASS  Y-suppressed-excluded raised is never 7
== D-min-n: --min-n lets the operator move the low_n floor (named tunable, not buried) ==
PASS  D-min-n with --min-n 10, even the high-n test-coverage row is now low_n=true (n_rejected=6<10)
== Z-div-by-zero: raised=0 (no review kit_gates activity at all) -> fp_rate_approx NULL for every row, never 0.0 ==
PASS  Z-div-by-zero no row fabricates fp_rate_approx=0.0
PASS  Z-div-by-zero every row shows raised=0
PASS  Z-div-by-zero fp_rate_approx is null
PASS  Z-div-by-zero every row is low_n (raised=0 < 5)
== H-nc: HONEST-ZERO negative control (load-bearing) ==
PASS  H-nc zero ledger files + zero review activity -> zero rows, exit 0, no crash, no fabricated rate
== H-nc-deliberate-break: prove H-nc is falsifiable, not vacuous (literal source edit, red -> green) ==
PASS  H-nc-deliberate-break RED: the broken query fabricates a 0.0-rate row from zero real data
PASS  H-nc-deliberate-break GREEN: restored source returns zero rows again
PASS  H-nc-deliberate-break source is byte-identical to pre-break (clean restore)
== O-anomaly: review_fp anomaly detector fires on the high-n lens, propose-never-autofile ==
PASS  O-anomaly review_fp fires (repo-a/test-coverage: fp_rate=1.0 >= 0.5 threshold, both floors clear)
PASS  O-anomaly names the exact lens
PASS  O-anomaly --propose stages review_fp
PASS  O-anomaly staged into the cc-backlog staging buffer (never the board)
PASS  O-anomaly the board file was NEVER written (propose-never-autofile)
== T-nonfinite: --threshold review_fp_min_n=nan/inf is rejected (kit:code-reviewer LOW finding, SPEC-137) ==
PASS  T-nonfinite nan rejected with a clean CLI error, never spliced into SQL
PASS  T-nonfinite inf rejected with a clean CLI error
PASS  T-nonfinite a real finite override still parses fine (the guard is non-finite-only)
== O-plan: over-test pass targeting read_rejected_findings() directly ==
PASS  O1-missing-file OK (no exception, zero rows)
PASS  O2-zero-rows-file OK (a real file with zero rows contributes nothing)
PASS  O3-format-template-row-ignored OK (the ## Format section is never read as data)
== G-remat: delete-and-rematerialize is byte-identical (fixture files canonical) ==
PASS  G-remat identical output
== G-nc: read-only negative control (fixture files are never mutated) ==
PASS  G-nc fixture ledger files byte-identical after rebuild+queries

== 39 passed, 0 failed ==
```

Full suite regression check (all 13 `tests/test-*.sh` files, incl. this new one): all green,
zero regressions (`test-schema-parity.sh` 4/4, `test-gate-yield.sh` 25/25, `test-ledger-cli.sh`
26/26, `test-defect-correlation.sh` 20/20, `test-deviation-rate.sh` 25/25,
`test-anomalies-advisor.sh` 37/37, `test-sessions-digest.sh` 59/59, `test-memory-lens.sh` 39/39,
`test-schema-conform.sh` 11/11, `test-docs-wiring.sh` 19/19, `test-feedback.sh` 39/39,
`test-render-skill.sh` 30/30, this suite 39/39).

## Honest-zero negative control -- proven load-bearing (literal deliberate break)

`cli.py`'s `review-yield` SQL was patched two ways simultaneously, simulating exactly the bug
class this test guards against: (1) the join direction was reversed from
`FROM rejected_findings rf CROSS JOIN review_agg ra` to
`FROM review_agg ra LEFT JOIN rejected_findings rf ON true` -- since `review_agg` is an
aggregate-with-`COALESCE` that ALWAYS returns exactly one row, driving the query from it instead
of from `rejected_findings` produces a row even when `rejected_findings` is completely empty;
(2) the empty-denominator branch was changed from `ELSE NULL` to `ELSE 0.0`. Re-run against the
SAME zero-ledger-files, zero-review-activity fixture state the honest-zero NC uses:

```json
[
  {
    "repo": null, "lens": null, "n_rejected": null, "first_ts": null, "last_ts": null,
    "review_ran": 0, "review_caught": 0, "raised": 0, "approx": true,
    "fp_rate_approx": 0.0, "low_n": true
  }
]
```

A single fabricated, all-`NULL`/`0.0` row from zero real data -- exactly the failure mode the
goal file names ("make the query fabricate a 0.0 row from no data"). Restored (`cp` back the
pre-break backup, confirmed `diff -q` byte-identical) -> back to `[]`, exit 0. The NC is real,
not decorative.

## Real-corpus materialization (2026-07-04)

Rebuilt against the live corpus (no env override): `LEDGER_OBS_REPOS` defaults to
`~/workspace/<owner>/ops-toolkit,~/workspace/<owner>/dwarves-kit`.

```
$ uv run ledger rebuild
{ ..., "rejected_findings": 1 }

$ uv run ledger show rejected_findings --table
+-------------+--------------+------------+------------+------------+
| repo        | lens         | n_rejected | first_ts   | last_ts    |
+-------------+--------------+------------+------------+------------+
| dwarves-kit | architecture | 1          | 2026-07-04 | 2026-07-04 |
+-------------+--------------+------------+------------+------------+
(1 row)

$ uv run ledger review-yield --table
+-------------+--------------+------------+------------+------------+------------+---------------+--------+--------+----------------+-------+
| repo        | lens         | n_rejected | first_ts   | last_ts    | review_ran | review_caught | raised | approx | fp_rate_approx | low_n |
+-------------+--------------+------------+------------+------------+------------+---------------+--------+--------+----------------+-------+
| dwarves-kit | architecture | 1          | 2026-07-04 | 2026-07-04 | 73         | 0             | 4      | True   | 0.25           | True  |
+-------------+--------------+------------+------------+------------+------------+---------------+--------+--------+----------------+-------+
(1 row)
```

**Honest reading, low-n named explicitly**: `ops-toolkit` contributes ZERO rows (its own
`docs/verification/rejected-findings.md` does not exist yet as of this writing -- no operator
has rejected a review finding in this repo yet; it is organically created on first use per the
02 sub-goal's scope edges). `dwarves-kit/architecture` is the only row, `n_rejected=1` (a single
row logged 2026-07-04) and `raised=4` (only 2 of the 105 real `kit_gates` review lines carry
the 02 grammar's `findings=`/`rejected=` tokens at all -- the grammar shipped the same day this
run was captured, so the overwhelming majority of the real corpus predates it). `low_n=true` on
BOTH floors (1<5 and 4<5): this single real row is exactly the low-n case the design exists to
label honestly rather than hide or dress up as a confident rate. `review_ran=73` (the
`gate-yield`-style existing catch data for `gate='review'`, unaffected by the grammar's youth)
confirms `review-yield`'s SQL correctly counts ALL `ran`/`override` review rows for that column
even though only 2 of them carry the new KV grammar for the `raised` sum.

`ledger anomalies --json` on this same real state correctly does NOT fire `review_fp`
(`n_rejected=1 < review_fp_min_n=5`, the dual floor abstains on thin data, same discipline as
`_detect_ceremony`/`_detect_memory_hygiene`).

## COVERAGE-DELTA

Baseline (a happy-path-only test) would cover: one repo with one rejected row, one review gate
line carrying `findings=`/`rejected=`, the aggregation + division. This sub-goal's over-test
pass ADDS: (1) a malformed `## Rows` row (too few cells), (2) a row with a non-`rejected`
verdict, (3) a `## Format` section's template row that must never be read as data (a DIFFERENT
heading than `## Rows`), (4) a repo whose ledger file exists but has zero real rows, (5) a repo
path that does not exist on disk AT ALL (not even the directory), (6) a `skipped`-outcome
review row correctly EXCLUDED from the `ran`/`override` denominator, (7) a `suppressed=` token
correctly excluded from `raised` (a different axis, SPEC-137 DEC-003), (8) an old-style review
line with no `findings=`/`rejected=` token at all (regex returns NULL, COALESCEd to 0, never a
cast error), (9) a non-review `gate=build` row that must never leak into the `review-yield`
denominator, (10) a division-by-zero state (`raised=0` -> every `fp_rate_approx` is `NULL`,
never `0.0`), (11) the honest-zero state (`rejected_findings` itself has zero rows -> the query
returns zero rows, never a fabricated placeholder), (12) the honest-negative case (a lens's rate
exceeding `1.0`, reported exactly, never clamped), (13) the `--min-n` tunable actually moving the
`low_n` boundary, (14) the new `review_fp` anomaly detector firing on real threshold-crossing
data AND staging via `--propose` into the buffer ONLY, never the board; (15, added post-review)
a non-finite `--threshold review_fp_min_n=nan`/`=inf` override is rejected with a clean CLI
error rather than reaching `_detect_review_fp`'s f-string SQL. Covered: all 15 above, plus the
honest-zero NC proven load-bearing by a literal source-edit deliberate break (not just an inline
alternate query). Not covered: a real per-lens emit inside `kit_gates.reason` (the goal file's
named follow-on, does not exist yet); a `docs/verification/rejected-findings.md` whose `## Rows`
table has a row with EXTRA columns beyond 5 (the parser only ever reads the first 5 cells
positionally, so an extra trailing cell is silently ignored rather than flagged -- a real but
low-severity gap, since the ledger file format itself is append-only and human-authored per
SPEC-144, not machine-generated).

## Review

`kit:code-reviewer` dispatched on the FINISHED diff (security + architecture/correctness lens,
independent of the draft-stage spec-validate pass, same "different bug classes" precedent
harness-observatory SG-04's DECISIONS.md established). Verdict: 9/10, no CRITICAL/MAJOR
findings. Two LOW items: (1) `parse_thresholds` accepted non-finite (`nan`/`inf`) values, which
`_detect_review_fp` -- the first detector to interpolate a threshold VALUE (not a Typer-`int`
CLI option) directly into SQL text -- would then splice into its query, producing a confusing
DuckDB error instead of a clean CLI rejection; fixed with a `math.isfinite` guard in
`parse_thresholds` (applies to every threshold key, not only the new one) plus 3 new assertions
(`T-nonfinite`). (2) an informational note that no test exercised a malformed `--min-n` directly
(confirmed structurally safe already: Typer's `int`-typed CLI option rejects it before the
command body runs), no fix needed. Confirmed clean: no SQL-injection surface anywhere in the
diff (every value that reaches an f-string is a Python-native `int`/`float`-cast boundary first,
matching the established `defect-correlation --window-days`/`deviation-rate
--under-specced-min` convention; row DATA from the untrusted markdown file is loaded via
parameterized `executemany` INSERTs, never string-concatenated into SQL), no path-traversal
surface via `LEDGER_OBS_REPOS` (operator-controlled config, a fixed relative suffix, read-only),
and the markdown parser's heading-scope isolation / honest-zero / skip-and-count contracts all
verified against their docstrings with no off-by-one found.

## Reproduce

```bash
cd ~/workspace/<owner>/ops-toolkit/tools/ledger-observatory
uv sync
bash tests/test-review-yield.sh           # golden fixture + honest-zero NC + over-test (39/39)
bash tests/test-schema-parity.sh          # regression: unaffected (4/4)
bash tests/test-gate-yield.sh             # regression: unaffected (25/25)
uv run ledger rebuild && uv run ledger review-yield --table   # real 2-repo materialization
```
