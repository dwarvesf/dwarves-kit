# Proof of done: ledger-observatory feature `anomalies-advisor` (harness-observatory mega-goal, SG-04)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `anomalies-advisor` feature
> detail.

| | |
|---|---|
| **Profile** | data/CLI tool (behavioral, read-only) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Spec** | [`../specs/SPEC-134-anomalies-advisor.md`](../specs/SPEC-134-anomalies-advisor.md) |

## Test design

`tests/test-anomalies-advisor.sh` builds its git-history fixture at test time (`git init` in
`mktemp -d` + commits at controlled `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE`), the same precedent
as `test-defect-correlation.sh`/`test-deviation-rate.sh` (SPEC-132 DEC-005). `kit_gates` rows
come from plain run-ledger log files (`gate_row` helper), the SAME grammar `read_kit_gates`
parses -- no committed fixture dir, no `kit_runs` dependency anywhere.

**A real regression was found and fixed during this sub-goal's Build, not anticipated in the
goal file**: the original design pointed `_detect_serial_when_parallel` at `kit_runs.first_ts/
last_ts` (per the goal file's own "over a run's duration" wording). Confirmed empirically that
`kit_runs` returns 0 rows in this local environment -- the `kit_runs` adapter's own subprocess
into the installed `~/.claude/dwarves-kit/lib/lane-telemetry.sh` returns nothing here, root-
caused to a `bash 3.2` (`source`/`return`/`set -e` interaction) quirk, reproduced identically via
`bash tests/test-feedback.sh` (its debt/misfire fixtures, which also depend on `kit_runs`,
currently fail 9/39 for the SAME reason -- a pre-existing, out-of-scope issue, see
`_meta/megagoals/harness-observatory/DECISIONS.md`). Redesigned before any fixture was written to
window every `kit_gates` rid by `MIN(ts)..MAX(ts)` across its OWN git-bridged commits instead
(SPEC-134 DEC-005) -- `git_fixes.ts` is the one reliable timestamp source per HANDOFF's standing
windowing lesson. `_detect_serial_when_parallel` never touches `kit_runs`.

**`/kit:spec-validate` was dispatched on the initial draft (Round 1)** (the `kit_runs`-anchored
advisor, `count(*)` bridge evidence) and returned NEEDS-REVISION: 2 CRITICAL findings (the
count-inflation bug counting file-rows as samples, and a missing AC for "evidence-sufficient AND
has a real catch" firing) + 3 MAJOR findings (the advisor's missing evidence floor, ambiguous
ship-filter inheritance, a too-low minutes-saved threshold). All fixed before Build closed;
SPEC-134 DEC-004/DEC-005 record the fixes, and 3 new fixtures below (`C-mixed`, `C-multifile-nc`,
`S-nofire-zero-evidence`) prove them mechanically.

**`kit:code-reviewer` was dispatched on the FINISHED diff (Round 2)**, independent of Round 1 (it
reviewed the actual committed code, not the draft). It confirmed both Round-1 CRITICALs genuinely
fixed, and found ONE NEW MAJOR: the `caught_true > 0` guard only lived inside the
`caught_known >= ceremony_min_ran` branch, so a gate with THIN (below-floor) caught data
containing a REAL catch could still fire CONDITION via the soft path -- contradicting the
module's own "NONE of them true" claim. Fixed (DEC-006) by hoisting the guard to run
unconditionally before either path is considered; the `C-thin-true` fixture below proves it,
falsifiably (reverting the hoist turns it RED).

## Fixtures

### Ceremony (8 fixtures + 1 falsifiability check)

| Fixture | Shape | Expected |
|---|---|---|
| `C-cut` | gate `grill`, 5 ran rows, ALL `caught=false` | CUT (hard signal, evidence-sufficient) |
| `C-cut-floor` | gate `grill`, only 4 `caught=false` rows | no fire (< `ceremony_min_ran`) |
| `C-mixed` | gate `mixed`, 5 ran rows, 4 `caught=false` + 1 `caught=true` | no fire (proves "NONE true" is load-bearing, not just the floor -- distinct from `C-cut-floor`) |
| `C-condition` | gate `audit`, 5 ran rows, NO caught data, 5 distinct rids each bridged to ONE commit/ONE file, never fixed | CONDITION (soft/fix-correlation signal) |
| `C-condition-nofire` | same shape as `C-condition`, but ONE bridged file gets a later `fix()` | no fire (not ALL clean) |
| `C-multifile-nc` | gate `multigate`, ONE real rid whose single commit touches 5 files | no fire (`bridged` must count 1 rid, not 5 files -- the count-inflation regression test) |
| `C-thin-true` | gate `thintrue`, 5 ran rows: 1 `caught=true`, 1 `caught=false`, 3 no OUTCOME bracket (`caught_known=2 < floor`); ALSO 5 distinct bridged rids, never fixed (soft path's OWN floor separately satisfied) | no fire (DEC-006: `caught_true>0` must suppress the soft path too, not just the hard path) |
| `C-fp-nc` | gate `ui-design`, 5 ran rows all `caught=true`, PLUS 20 skipped rows (`reason=not-applicable: non-ui-run`, ~80% skip) | no fire (the load-bearing FP-NC) |
| `C-fp-nc-deliberate-break` | inline `count(*) FILTER (WHERE outcome='skipped')/count(*) > 0.5` query, run directly against the SAME lens, no shipped code involved | WOULD flag `ui-design` -- proves the real detector's caught-conditioning is load-bearing |

### Serial-when-parallel (3 fixtures)

| Fixture | Shape | Expected |
|---|---|---|
| `S-fire` | `sg-01-alpha` (window 00:00-00:10, files alpha1/alpha2.py), `sg-02-beta` (window 00:10-00:25, files beta1/beta2.py) -- non-overlapping, disjoint files | fires, `minutes_saved=10.0` (min of 10,15) |
| `S-nofire` | same non-overlapping windows/durations as `S-fire`, but BOTH rids' commits touch `shared.py` | no fire (genuinely dependent -- proves the file-overlap check, not just the floor) |
| `S-nofire-zero-evidence` | two rids in `kit_gates` with ZERO git-bridge commits at all | no fire (the evidence-floor test; structurally enforced by the query's INNER JOINs, no extra `WHERE` needed) |

### Token-runaway (static + live)

Asserted absent (`token_runaway` key) even on a lens state where ceremony fires; `DETECTORS`
contains `_detect_token_runaway`; its docstring states NOT ARMED.

### Propose path (2 fixtures)

`P-propose`/`P-dedup` (ceremony CUT) and `S-propose` (serial_when_parallel) both stage via the
SAME generic `stage_proposals` path the 4 shipped detectors already use; board byte-identical,
`add-backlog` lists the proposal, a second `--propose` marks duplicate.

## Confirmation run (recorded)

Command: `bash tests/test-anomalies-advisor.sh` -- 2026-07-04T08:55Z (UTC clock), exit 0.
(Round 1, pre-code-review, was 36/36 at 08:39Z; `C-thin-true` added after the DEC-006 fix.)

```
== C-cut: 5 'grill' ran rows, all caught=false (>= ceremony_min_ran) -> CUT ==
PASS  C-cut fires ceremony
PASS  C-cut action=CUT
PASS  C-cut names gate grill
PASS  C-cut no token_runaway (never armed, even while ceremony fires)
== C-cut-floor: only 4 caught=false rows (< ceremony_min_ran=5) does NOT fire ==
PASS  C-cut-floor no ceremony (thin caught evidence)
== C-mixed: 5 'mixed' ran rows, 4 caught=false + 1 caught=true -> must NOT fire ==
PASS  C-mixed no ceremony (one real catch among enough known samples)
== C-condition: 5 'audit' ran rows, no caught data, git-bridged, never fixed -> CONDITION ==
PASS  C-condition fires ceremony
PASS  C-condition action=CONDITION
PASS  C-condition names gate audit
== C-condition-nofire: same shape, but ONE bridged file gets a later fix() -> no fire ==
PASS  C-condition-nofire no ceremony (one later fix breaks the zero-fix-followed claim)
== C-multifile-nc: ONE real rid, its bridged commit touches 5 files -> bridged MUST count as 1 ==
PASS  C-multifile-nc no ceremony (1 real rid, not 5, despite 5 touched files)
== C-thin-true: thin caught data (2<floor) with one real catch, soft path's own floor also met ==
PASS  C-thin-true no ceremony (a THIN but REAL catch must suppress the soft/CONDITION path too)
== C-fp-nc: 'ui-design' skipped ~80% for a LEGITIMATE reason; caught=true in its few ran rows ==
PASS  C-fp-nc ceremony does NOT fire on ui-design (real caught=true evidence)
== C-fp-nc-deliberate-break: prove a bare skip-rate query WOULD flag ui-design ==
PASS  C-fp-nc-deliberate-break a bare skip-rate query WOULD flag ui-design (the bug the real detector avoids)
== S-fire: two dep-independent rids (git-windowed, NOT kit_runs) ran back-to-back ==
PASS  S-fire fires serial_when_parallel
PASS  S-fire names both rids
PASS  S-fire minutes_saved=10.0 (min of 10,15)
== S-nofire: a genuinely dependent pair (shares one bridged file) -> must NOT fire ==
PASS  S-nofire no serial_when_parallel (genuinely dependent, shares shared.py)
== S-nofire-zero-evidence: two rids with ZERO git correlation at all -> never a candidate ==
PASS  S-nofire-zero-evidence no serial_when_parallel (no bridge evidence for either rid)
== T-not-armed: token_runaway NEVER fires, on ANY DB state (static + a live check) ==
PASS  T-not-armed absent even on the zero-evidence lens
PASS  T-not-armed detector present in DETECTORS
PASS  T-not-armed docstring states NOT ARMED
== P-propose: ceremony CUT stages, board byte-identical, add-backlog sees it, idempotent ==
PASS  P-propose reports staged
PASS  P-propose one staged block
PASS  P-propose staged block in buffer
PASS  P-propose board BYTE-IDENTICAL (not auto-filed)
PASS  P-propose add-backlog lists the proposal
PASS  P-dedup second run marks duplicate
PASS  P-dedup still exactly one block
== S-propose: serial_when_parallel ALSO stages via the same generic path ==
PASS  S-propose stages serial_when_parallel
PASS  S-propose one staged block
== H-help: both new thresholds are listed in --help ==
PASS  H-help lists ceremony_min_ran
PASS  H-help lists serial_min_minutes_saved
== O-one-path: detection reads via SG-02 materialize only (static, unchanged contract) ==
PASS  O-one-path imports materialize
PASS  O-one-path no direct duckdb import
PASS  O-one-path no adapters bypass
PASS  O-one-path no raw-ledger reader bypass

== 37 passed, 0 failed ==
```

**DEC-006 falsifiability (deliberate break):** reverting the `caught_true > 0` guard hoist back
to its original position (inside the `caught_known >= ceremony_min_ran` branch only) turns
`C-thin-true` RED (36/37, exit 1); restoring the hoist returns 37/37 exit 0. Not decorative.

**Regression:** `test-gate-yield.sh` (25/25), `test-defect-correlation.sh` (20/20),
`test-deviation-rate.sh` (25/25), `test-schema-parity.sh` (4/4), `test-docs-wiring.sh` (19/19),
`test-render-skill.sh` (30/30), `test-schema-conform.sh` (11/11) all re-run unchanged.
`test-feedback.sh` (30/39) and `test-ledger-cli.sh` (19/26) reproduce the EXACT same documented
pre-existing failure counts (`kit_runs`/`lane-telemetry` environment issue, see DECISIONS.md);
this branch does not touch `kit_runs`, `adapters.py`, or `materialize.py` at all.

## Real-corpus capture

Command: `uv run ledger rebuild && uv run ledger anomalies --table` against the live ops-toolkit
repo (default `LEDGER_OBS_GIT_REPO_DIR`), 2026-07-04.

```
{
  "kit_runs": 0,
  "kit_gates": 695,
  "git_fixes": 9626,
  "impl_notes": 233,
  ...
}
+-----------------+-----------------------------------------------------------------+-------------------+-----------------------------------------------------------------------------------------------------------------------------------------------+
| key             | title                                                            | metric             | intent                                                                                                                                          |
+-----------------+-----------------------------------------------------------------+-------------------+-----------------------------------------------------------------------------------------------------------------------------------------------+
| unknown_density | Feedback: implementation-notes deviation density over threshold | median=5 window=5 | Condition grill ON for ops-toolkit: the rolling median deviation count over the last 5 implementation-notes files is 5, over the 2 threshold. |
+-----------------+-----------------------------------------------------------------+-------------------+-----------------------------------------------------------------------------------------------------------------------------------------------+
(1 row)
```

**Honest yield note:** `ceremony`, `token_runaway`, and `serial_when_parallel` all fire NOTHING
on the real corpus today. This is the expected, correct state, not a broken detector:
`defect-correlation` itself already reports 0 rows on this real corpus (verified directly,
`uv run ledger defect-correlation --json` returns `[]`) -- no real `kit_gates` rid's substring
appears in any commit subject on this repo today, so the git-bridge both detectors depend on has
zero real matches to work with. `ceremony`'s hard path also finds only 3 `caught_known` rows
total (all under the `ship` gate, all `caught=false`), below the `ceremony_min_ran=5` floor, so
it correctly abstains rather than drawing a conclusion from 3 samples. This mirrors
`unknown_density`'s own SG-03 honest-empty precedent: the classifier is proven correct against
the fixtures above (including the false-positive negative control); the real corpus simply has
not yet produced a `ceremony`/`serial_when_parallel`-shaped case.

## COVERAGE-DELTA

| Covered | Uncovered (named, not hidden) |
|---|---|
| Ceremony CUT (hard, caught-based) + CONDITION (soft, fix-correlation proxy), both directions, both floors (ran count + evidence-sufficiency) | Multiple simultaneous firing gates in one `detect()` call (returns only the first, alphabetical) |
| The false-positive negative control (legitimate high-skip gate) + its falsifiability proof | A gate whose `caught` evidence is thin on ONE run but the soft path's `bridged` evidence is ALSO thin (both paths simultaneously starved) -- covered structurally (neither condition met, no fire) but not asserted as a distinct named fixture |
| The count-inflation regression (multi-file single commit) | N-file, N-rid combinations beyond 1-rid/5-file and 5-rid/1-file-each |
| Serial-when-parallel fire / dependent-no-fire / zero-evidence-no-fire | Slow-gate ranking, kill-churn, discovery-heavy (need session data, sub-goal 05; explicitly out of scope) |
| Token-runaway wired but not-armed, proven never to fire | The actual armed behavior (needs 05's sessions table) |
| `--propose` staging + dedup for BOTH new detector shapes | A combined single-DB-state test firing ceremony + serial_when_parallel + debt/cost/misfire simultaneously (each detector's own fixture already isolates cleanly; not additionally combined) |
| `--help` lists both new threshold keys | -- |
| Real-corpus capture, honestly reporting the honest-empty result + why | -- |

## Reproduce

```bash
cd tools/ledger-observatory
bash tests/test-anomalies-advisor.sh
uv run ledger rebuild
uv run ledger anomalies --table
uv run ledger anomalies --propose --table   # stages any real anomaly into the staging buffer
```
