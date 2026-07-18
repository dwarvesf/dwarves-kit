# Proof of done: ledger-observatory feature `kit-gates-lens` (harness-observatory mega-goal, SG-01)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `kit-gates-lens` feature detail.

| | |
|---|---|
| **Profile** | data/CLI tool (behavioral, read-only) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Spec** | [`../specs/SPEC-131-kit-gates-lens.md`](../specs/SPEC-131-kit-gates-lens.md) |

## Test design

`tests/test-gate-yield.sh` points the kit source at a COMMITTED fixture ledger dir
(`tests/fixtures/kit-gates/runs/*.log`, 4 files, known rids) instead of the mktemp-per-run
pattern the other suites use, per the goal file's "golden fixture" requirement. It asserts EXACT
per-row values (`show kit_gates --json`) and EXACT per-gate aggregation (`gate-yield --json`)
against hand-verified numbers, then the load-bearing FP negative control, then a
`/kit:test-plan`-shaped over-test pass targeting parser edge cases the fixture files don't reach
(missing runs dir, a noise-only file, an unclosed OUTCOME bracket), then the standard
delete-and-rematerialize + read-only negative controls every suite in this tool already runs.

### Golden fixture (`tests/fixtures/kit-gates/runs/`)

| File (rid) | Contents |
|---|---|
| `fix-happy.log` | one `GATE` line each for `grill`(skipped, w/ reason), `spec`(ran), `build`(ran), `ship`(override) |
| `fix-outcome.log` | `spec`(ran, no bracket) + `build`(ran) paired to a completed `OUTCOME` start/end bracket, `caught=true` |
| `fix-legit-skip.log` | `ui-design` skipped TWICE, zero `OUTCOME` bracket anywhere for it -- the FP-NC target |
| `fix-malformed.log` | `grill` with a 4-field GATE line (no reason); a non-pipe noise line; `spec` recorded TWICE (duplicate gate name in one rid) with one malformed `OUTCOME` bracket (`at=notanumber` on start, `caught=maybe` on end) |

## Confirmation run (recorded)

Command: `bash tests/test-gate-yield.sh` , 2026-07-04 (UTC clock), exit 0.

```
== G-rebuild: kit_gates materializes, one row per GATE line across the fixture set ==
PASS  G-rebuild kit_gates=11
== G-rows: exact per-row values (rid, gate, outcome, caught, reason, start_ts, end_ts) ==
PASS  G-rows fix-happy grill skipped, reason present
PASS  G-rows fix-happy ship override
PASS  G-rows fix-outcome build caught=true w/ start_ts/end_ts
PASS  G-rows fix-malformed grill missing-reason (reason=null, no crash)
PASS  G-rows fix-malformed spec#1 malformed at= kept raw, caught=null
PASS  G-rows fix-malformed spec#2 duplicate gate, no bracket left
PASS  G-rows fix-malformed contributes exactly 3 rows (grill + 2x spec, malformed line adds none)
PASS  G-rows exactly 11 rows total (one per GATE line, none dropped)
== G-yield: exact gate-yield aggregation per gate (hand-verified against the fixture) ==
PASS  G-yield build: ran=2 / caught=1 total=2 override_pct=0.0
PASS  G-yield grill: ran=0 override=0 skipped=2
PASS  G-yield ship: override=1 override_pct=100.0
PASS  G-yield spec: ran=4 caught=0
PASS  G-yield ui-design: ran=0 skipped=2 caught=0
== F-nc: FALSE-POSITIVE negative control (load-bearing) ==
PASS  F-nc ui-design present with its real skip count / caught=0 / not ran/override
PASS  F-nc ui-design reported honestly: skipped=2, caught=0, not dropped, not mislabeled
== F-nc-deliberate-break: prove the FP-NC is falsifiable, not vacuous ==
PASS  F-nc-deliberate-break a ran-only GROUP BY drops ui-design (the bug the real query avoids)
== O-plan: /kit:test-plan-shaped over-test pass (parser edge cases beyond the golden fixture) ==
PASS  O1-missing-dir OK (empty columns+rows, no exception)
PASS  O2-zero-valid-lines OK (noise-only file yields zero rows, no crash)
PASS  O3-unclosed-bracket OK (no matching end -> caught/start_ts/end_ts stay NULL, no fake pairing)
== G-remat: delete-and-rematerialize is byte-identical (fixture files canonical) ==
PASS  G-remat identical output
== G-nc: read-only negative control (fixture files are never mutated) ==
PASS  G-nc fixture ledger files byte-identical after rebuild+queries

== 25 passed, 0 failed ==
```

## FP negative control -- proven load-bearing (deliberate break)

`adapters.read_kit_gates`'s final assembly line was patched to `caught = True` unconditionally
(ignoring whether a paired `OUTCOME` bracket actually existed), simulating exactly the bug class
this table exists to prevent: a gate with no real catch signal reported as if it had one. Re-run:
**15 passed, 10 failed** -- the FP-NC assertion (`ui-design caught=0`) and every other
`caught`-bearing assertion in the golden-fixture section went RED as expected. Restored (`git
checkout -- src/ledger_observatory/adapters.py`) -> back to 25/25, exit 0. The NC is real, not
decorative.

## Real-corpus materialization (2026-07-04)

Rebuilt against the live `~/.local/state/dwarves-kit/logs/runs/` corpus (no env override):

```
$ uv run ledger rebuild
{ "kit_runs": 0, "kit_gates": 621, "tide_moves": 0, "tide_tier_b_calls": 0,
  "tg_dialogs": 625, "learned": 58 }

$ uv run ledger gate-yield --table
+-----------------+-----+----------+---------+--------+-------+--------------+
| gate            | ran | override | skipped | caught | total | override_pct |
+-----------------+-----+----------+---------+--------+-------+--------------+
| build           | 69  | 1        | 0       | 0      | 70    | 1.4          |
| design          | 18  | 8        | 2       | 0      | 28    | 28.6         |
| docs            | 44  | 3        | 5       | 0      | 52    | 5.8          |
| grill           | 10  | 0        | 38      | 0      | 48    | 0.0          |
| review          | 57  | 1        | 2       | 0      | 60    | 1.7          |
| ship            | 55  | 1        | 0       | 0      | 56    | 1.8          |
| spec            | 70  | 2        | 0       | 0      | 72    | 2.8          |
| test-plan       | 43  | 3        | 3       | 0      | 49    | 6.1          |
| think           | 29  | 7        | 6       | 0      | 42    | 16.7         |
| ui-design       | 0   | 1        | 6       | 0      | 7     | 14.3         |
| validate        | 33  | 3        | 0       | 0      | 36    | 8.3          |
+-----------------+-----+----------+---------+--------+-------+--------------+
(21 rows total; showing gates referenced by the 2026-07-04 hand probe -- full table has debug,
decision, design-critique, design-record, execute, integration, reflect, spec-validate, test, verify)
```

Every row's `caught` column is 0: verified 2026-07-04 by scanning all files under
`~/.local/state/dwarves-kit/logs/runs/*.log` for a literal `| OUTCOME |` marker line -- **zero**
exist yet (the emitter lands via the kit-absorptions mega, per SPEC-131 DEC-003). This is the
expected, correct state, not a bug: the FP-NC above proves the reader does not fabricate a caught
signal that isn't there.

**Drift vs. the 2026-07-04 hand probe** (`docs/benchmark-followup.md`):

| Gate | Hand probe | This run | Drift |
|---|---|---|---|
| `grill` skip rate | ~82% | 38/48 = 79.2% | -2.8pp -- 4 more `grill` runs recorded since the hand probe (corpus grows continuously; see `kit_gates` count 611->621 between two captures 30 minutes apart during this PR) |
| `ui-design` skip rate | ~100% | 6/7 = 85.7% (+1 override) | The hand probe missed (or the corpus gained) one `override` row; not a parser bug -- verified the raw line exists in `~/.local/state/dwarves-kit/logs/runs/` (`\| GATE \| ui-design \| override \|`) |
| core gates override | 2-4% | build 1.4%, review 1.7%, ship 1.8%, spec 2.8% | build slightly under range; all four in the same low-single-digit band the hand probe described |

The drift is corpus growth + probe imprecision, not a reader defect: every number above is a direct
`count(*)` over real `\| GATE \|` lines, reproducible via `bash tests/fixtures` inspection or
`uv run ledger show kit_gates`.

## COVERAGE-DELTA

Baseline (a happy-path-only test) would cover: one `GATE` line per outcome value (ran/skipped/
override), rebuild + show + gate-yield aggregation. This sub-goal's over-test pass ADDS: (1) a GATE
line with a missing reason field (4 cols), (2) a non-pipe noise line mixed into a real file, (3) a
malformed `at=`/`caught=` token on an `OUTCOME` bracket, (4) a duplicate gate name within one rid
(never deduped, FIFO-paired), (5) a completed `OUTCOME` bracket correctly pairing `caught=true` +
real epoch strings onto its `GATE` row, (6) a MISSING runs directory entirely (`read_kit_gates`
returns empty, no exception), (7) a file with ZERO valid `GATE`/`OUTCOME` lines, (8) an UNCLOSED
`OUTCOME` start bracket (phase never ends) proving no fake pairing occurs. Covered: all 8 above,
plus the FP-NC (a legitimate skip is never dropped/mislabeled) proven load-bearing by a deliberate
break. Not covered: kit-absorptions' real emitter wiring into `outcome start`/`outcome end` at an
actual phase boundary (that lands in a different repo, out of this sub-goal's scope per SPEC-131);
concurrent-write truncation of a log file mid-append (the malformed-line tolerance covers the same
failure shape a truncated line would produce, but was not exercised via an actual concurrent writer).

## Reproduce

```bash
cd ~/workspace/<owner>/ops-toolkit/tools/ledger-observatory
uv sync
bash tests/test-gate-yield.sh                    # golden fixture + FP-NC + over-test (25/25)
bash tests/test-schema-parity.sh                 # regression: unaffected (4/4)
uv run ledger rebuild && uv run ledger gate-yield --table   # real-corpus materialization
```
