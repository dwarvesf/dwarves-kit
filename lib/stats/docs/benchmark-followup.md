# ledger-observatory , benchmark follow-up (gate-yield, defect-correlation, advisor)

**Status:** draft / follow-up (backlog ID-245). **Date:** 2026-07-04.

**Why this exists:** ledger-observatory shipped (PRs #672-676) as a generic read-only lens, but WITHOUT the control-arm benchmark queries that were its stated purpose , measure per-gate YIELD, not framework-vs-none. The run used the pre-benchmark scaffold; the `docs/megagoal-benchmark` branch that carried the benchmark scope never merged. This is the ADDITIVE spec to close the gap against the SHIPPED tool (no re-run of the mega-goal).

**Measurement principles:** every metric this doc adds follows counterfactual-in-same-row and honest-negative, `research/2026-07-04-scaling-the-harness-audit.md` §5.2.

## What shipped vs what's missing

| Capability | Shipped? | Where |
|---|---|---|
| read-only DuckDB lens, delete-and-rematerialize | yes | `materialize.py` |
| `show` / `query` / `rebuild` / `render` / `tables` | yes | `cli.py` |
| anomalies: unpaid-debt, cost-spike, misfire | yes | `anomalies.py` |
| kit `caught=` / START / END EMIT | yes (kit) | dwarves-kit #158 (`gate-ledger.sh`) |
| per-gate rows + `caught` in the tool's schema | NO | `schemas.py` reads per-RUN aggregates only |
| `gate-yield` (ceremony detector) | NO | , |
| `defect-correlation` (gate-coverage x later fix commits) | NO | , |
| ceremony / token-runaway anomalies + time-to-done advisor | NO | , |

**The load-bearing miss:** kit #158 emits `caught=`/START/END per gate, but `schemas.py` `KIT_SCHEMA` stores only `gates_ran` / `gates_skip` / `gates_ovr` as per-RUN counts. So the emit has no reader , the exact write-only-ledger problem this tool exists to kill, now reincarnated for the field the benchmark needs.

## The five additive changes (against the shipped code)

1. **`kit_gates` per-gate table** (`schemas.py` + `adapters.py` + `materialize.py`).
   `kit_runs` is one row per run (aggregates). Add a SECOND table `kit_gates`: one row per GATE line , `(rid, gate, outcome, caught, start_ts, end_ts)` , parsed from the per-gate `... | GATE | <name> | <ran|override|skipped> | ...` markers now carrying `caught=` + START/END (kit #158). Single-source the schema the way `schemas.py` already does (one `(name, type)` spec; DDL + column-names derived; `assert_parity` guards it). This table is the reader for the emit.

2. **`gate-yield` command** (`cli.py`).
   `ledger gate-yield [--json|--table]` , per gate: `ran`, `override`, `skipped`, `caught`, `override_pct`. The CEREMONY signal = high `ran` + zero `caught` over N runs. Materializes the first cut hand-computed 2026-07-04 (grill 82% skip, ui-design 100% skip, core gates 2-4% override). OVER-TEST: a golden-fixture assertion on a known rid set.

3. **`defect-correlation` command** (`cli.py` + a git-log adapter).
   `ledger defect-correlation` , JOIN each shipped sub-goal's gate-coverage (`kit_gates`) against its later `fix()` commits touching the same files. Needs a NEW git-sourced adapter (`git_fixes`: sha, files, ts) , the tool's first git adapter (read-only, same delete-and-rematerialize contract). A gate that passed but a fix followed on its files = a miss. This is the retrospective control arm , real data (merged PRs + git history), zero new runs. OVER-TEST + a false-positive NC (a clean sub-goal with no later fix is NOT flagged).

4. **ceremony + token-runaway anomalies + time-to-done advisor** (`anomalies.py`).
   Extend `DEFAULTS` + `detect()`, keeping the shipped PROPOSE-not-autofile contract (`--propose` stages into cc-backlog; `add-backlog` is the human gate):
   - **ceremony** , a gate high-ran + zero-caught over >= N runs proposes CUT/CONDITION (reads gate-yield). FP-NC is load-bearing: a correctly-skipped gate (e.g. `ui-design` on non-UI work) must NOT be proposed , gate on the `caught` signal or a zero fix-correlation, never a bare high skip-rate.
   - **token-runaway** , a worker over its per-sub-goal token budget (once token capture feeds a ledger the lens reads).
   - **time-to-done advisor** , over a run's duration + dep-graph: serial-when-parallel (dep-independent sub-goals that ran in separate waves proposes "collapse to one wave, ~X min saved"), slow-gate, kill-churn, discovery-heavy.

5. **deviation-rate lens** (ID-248; added 2026-07-04, from Thariq's "Finding Your Unknowns" absorption).
   An `impl_notes` adapter over the hook-enforced `docs/implementation-notes/<slug>.md` files
   (repo, slug, n_deviations, zero_marker, first/last_ts) + a `deviation-rate` CLI query JOINing
   `git_fixes` (change 3) , classes UNDER-SPECCED (>=3 deviations), CLEAN (0 + no later fixes),
   SUSPECT (zero_marker + later fix() on the same files) , + an `unknown-density` anomaly. This is
   the UPSTREAM half of the benchmark: unknowns discovered mid-flight, bridging spec quality to the
   downstream gate-yield/defect-correlation. NC: an honest zero_marker (no later fixes) is never
   flagged. Full design: `research/2026-07-04-fable-unknowns-absorption.md` Design 2. Sequence after
   change 3's git_fixes adapter (impl_notes itself is independent).

## Reuse (do not re-derive)

The original per-sub-goal specs live on `docs/megagoal-benchmark`; bring the intent forward and adapt to the SHIPPED module layout above (the branch specs predate the shipped code):
- `_meta/megagoals/ledger-observatory/goals/01-ledger-schema.md` , the `caught=`/START-END read-side + git-log adapter.
- `.../goals/02-etl-cli.md` , `gate-yield` + `defect-correlation` + `duration`.
- `.../goals/04-feedback-loop.md` , ceremony + token-runaway + the time-to-done advisor.

## Shape of the work

ADDITIVE , no mega-goal re-run needed. Either a small stacked PR set (schema+adapter -> gate-yield -> defect-correlation -> anomalies -> docs) or a focused mega-goal if you want the full lane/over-test rigor. The two flagship queries (`gate-yield`, `defect-correlation`) are the OVER-TEST targets , a wrong benchmark is worse than none. Proof lands in the tool's canonical `docs/proof-of-done.md` (table-first, per SPEC-016). This is what turns the shipped lens into the control arm the benchmark conversation asked for.
