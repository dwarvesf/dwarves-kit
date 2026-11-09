# Delta: override source tag, latest-row coverage, rejected in the readers

Decisions the brief left open.

## Override source tag

**Where the tag rides.** A GATE row ends in a free-text reason that may hold ` | `, so the tag is a sixth field: `ts | GATE | phase | override | reason | via=<source>`. Readers that take field 5 never see it. Readers that join fields 5 to the end strip a trailing ` | via=<token>`. The OUTCOME `caught=` token has its own field position; GATE has no spare one, so the tail is the only place that breaks no reader.

**Writers.** `override()` stays the public verb and stamps `hand`. Bulk writers call `_override_via <source>`. plan-record and record-batch set `_pr_via` before the shared replay. A trailing `| via=` typed into a reason is dropped, so a hand row cannot claim another source.

**Duplicate-reason guard.** It compares the reason without the tag, so a row from before the tag and a row after it still collide.

**Alert metric.** `hand_override_rate` is hand overrides on required phases over all gate records in the window, the same denominator `override_rate` uses. `override_rate` stays for custom alert files. A run with no lane has no required set, so it adds nothing to the numerator. The `override-rate` alert id and the 0.15 threshold stay. Required phases come from `expected_plan()`, which reads `gate-ledger.sh plan`, which reads `lane-data.sh`; nothing is re-declared.

**Old rows.** No tag reads as hand. The alert rate falls only as tagged bulk rows accumulate; history is not rewritten.

**proof-table-gen.py.** It strips the tag from the reason cell in the same commit, because a ` | via=` inside a markdown table cell splits the column.

**Open.** The stats `kit_gates` table keeps field 5 as the reason, so it carries no source column. A `via` column there is a separate change.

## rejected in the readers

**mega-report.** A rejected gate draws `✗`, the mark `lib/bench/report.py` uses; the legend line names it. The cell reads the last row per gate, as before.

**Stats.** A `rejected` row is a gate that ran and failed, so it is active like ran and override, and it counts as a catch. That is a reading, not a given: the brief said "count it like the fail-type state it is". A column alone would let a gate with rejections still look like ceremony (ran, zero caught) and draw a false CUT. Touched: `gate-yield` (new last column `rejected`, `caught` includes rejections), the ceremony lens (`records.rejected`, active and catches), and the `_detect_ceremony` anomaly SQL. Other `kit_gates` queries (ship bridge, review false-positive rate) are untouched.

**kit-uml.html.** The embedded source carries the same GATE table text as `docs/SYSTEM-DESIGN.md`: `rejected` in the status values, plus `via` as an optional last column. Not re-rendered.
