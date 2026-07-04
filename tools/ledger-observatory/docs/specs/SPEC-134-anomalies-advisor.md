# Spec: ceremony + token-runaway + time-to-done advisor anomaly detectors (ledger-observatory mega-goal harness-observatory, SG-04)

**Design: obvious.** This extends an existing, already-shipped pattern
(`anomalies.py`'s `DEFAULTS` / `_detect_*` / `DETECTORS` / `detect()` shape, four
detectors already live: `debt`, `cost_spike`, `misfire`, `unknown_density`). No new
architecture, no new module, no new data path. Per the goal file
(`_meta/megagoals/harness-observatory/goals/04-anomalies-advisor.md`), the heavy
mermaid/3-approaches Design gate is not required; this spec is proportionate to that.

## Problem

`anomalies.py` reads three shipped lenses (`gate-yield`'s `kit_gates` aggregation,
`defect-correlation`'s git-bridge, `deviation-rate`'s `impl_notes`) but has no detector
over any of them yet. Three gaps, all named in `docs/benchmark-followup.md` change 4:

1. **Ceremony** -- a kit gate that runs constantly but never catches anything is
   ceremony (busywork), and nobody currently surfaces it. The obvious naive detector
   (bare skip-rate) is a KNOWN false-positive trap: `ui-design` skips ~86% of the time
   on the real corpus (1 ran / 6 skipped) for the entirely legitimate reason that most
   runs are not UI work -- a bare skip-rate detector would incorrectly propose cutting
   it.
2. **Token-runaway** -- a run that blows its token budget has no data source yet (no
   materialized table carries a per-run token/cost figure; that lands with the
   sessions table in sub-goal 05 of this mega-goal).
3. **Time-to-done advisor** -- dep-independent sub-goals executed in separate serial
   waves waste wall-clock time that could collapse to one wave; nothing surfaces this
   today.

## Solution

Three new `_detect_*` functions added to `anomalies.py`'s `DETECTORS` tuple, each
reading ONLY via `materialize.query()` (the one-data-path contract already in force):

1. **`_detect_ceremony`** -- reads `kit_gates` (gate-yield's own GROUP BY gate shape)
   joined to a per-gate generalization of `defect-correlation`'s rid-to-git bridge
   (SPEC-132 DEC-001's two-stage bridge: textual rid-in-subject match once, then
   genuine file-equality thereafter -- same technique, applied per-gate instead of
   only to `gate='ship'`). Two conditioning signals, in priority order, NEVER a bare
   skip-rate:
   - **Hard (`caught`):** when a gate has at least `ceremony_min_ran` runs carrying a
     KNOWN (non-NULL) `caught` value and none of them is true, propose **CUT**.
   - **Soft (fix-correlation proxy):** when `caught` is unknown/too-thin for that gate
     (`caught_known < ceremony_min_ran`), fall back to the git-bridge: if at least
     `ceremony_min_ran` of the gate's runs bridge to git AND none of the bridged files
     was later touched by a `fix()` commit, propose **CONDITION** (weaker confidence:
     absence of a later fix is a proxy, not proof).
   - Both paths gate on the RAN+OVERRIDE count (`ceremony_min_ran`), never on how often
     the gate was skipped. This is the FP-NC this spec is over-tested against.
2. **`_detect_token_runaway`** -- **NOT ARMED.** No materialized table carries a
   per-run token/cost figure (lands with 05's sessions table). Wired into `DETECTORS`
   now (so `detect()`'s shape + the `--propose` path are already exercised end-to-end
   once 05 lands, zero re-plumbing) but always returns `None` today. A graceful
   degrade, never a faked signal; the `anomalies` CLI command's own help text says so.
3. **`_detect_serial_when_parallel`** -- windows EVERY `kit_gates` rid by
   `MIN(ts)..MAX(ts)` across its OWN git-bridged commits (textual rid-in-subject match,
   same technique as `_detect_ceremony`'s bridge, but drawing from the FULL rid
   universe, not `gate='ship'` -- `kit_gates` has no per-run "did this ship" column to
   filter by for this purpose). A pair of rids is a candidate only when BOTH have >= 1
   bridged commit (an evidence floor enforced structurally by the query's INNER JOINs:
   a zero-evidence rid never enters the windowed CTE at all, so it can never pair).
   Among candidates, non-overlapping windows + zero shared touched file (the
   dependency-INDEPENDENCE proxy: ANY shared file = genuinely dependent, must stay
   serial) proposes collapsing to one wave with `min(duration_a, duration_b)` as the
   plausible minutes-saved estimate (parallel wall time is `max(dur_a, dur_b)`).
   - **DELIBERATELY never anchors on `kit_runs`.** Confirmed during this sub-goal's
     Build: `kit_runs` returns 0 rows in this local environment (the `kit_runs`
     adapter's own subprocess into the installed `lane-telemetry.sh` returns nothing
     here -- a pre-existing, out-of-scope issue, see
     `_meta/megagoals/harness-observatory/DECISIONS.md`, the SAME root cause behind
     `test-feedback.sh`'s 9 pre-existing failures). `git_fixes.ts` is the one reliable
     timestamp source (the HANDOFF windowing lesson); anchoring there also sidesteps
     `kit_gates.start_ts/end_ts`, 100% NULL on the real corpus.
   - Slow-gate ranking, kill-churn, and discovery-heavy (also named in the goal file's
     Outcome paragraph) need per-session data (05); left for then, not faked now. Only
     serial-when-parallel is implemented, matching the goal file's actual "how to
     close the loop" test plan (only this behavior has a concrete fixture requirement).

### Why not a new adapter/table

The one-data-path contract (`anomalies.py` imports only `materialize`, never
`adapters`) plus this sub-goal's scope fence (`anomalies.py` + its tests + proof docs
only; no CLI command changes beyond anomaly listing) rule out a new mega-goal
dependency-graph adapter. The git-bridge file-overlap technique is reused as a
same-data proxy for dependency-independence instead of a new read source.

## Technical Design

### New DEFAULTS keys

```python
"ceremony_min_ran": 5.0,           # min-sample floor: ran+override count AND the
                                    # evidence-sufficiency floor for caught_known/bridged
"serial_min_minutes_saved": 10.0,  # min plausible minutes-saved before proposing (a
                                    # 1-2 min saving is real-corpus noise, not worth a row)
```

Both overridable via the existing `--threshold KEY=VALUE` flag; both appear in
`ledger anomalies --help` automatically (the help text already lists
`sorted(anomalies_mod.DEFAULTS)`, no `cli.py` change needed for this).

### `_detect_ceremony(th)`

One SQL query (a `WITH` chain mirroring `defect-correlation`'s CTEs, generalized from
`gate='ship'` to every gate) returns, per gate: `ran`, `caught_true`, `caught_known`,
`bridged`, `fix_followed`. **`bridged`/`fix_followed` are `count(DISTINCT rid)`, NEVER
`count(*)`** -- `mention_files` is `(gate, rid, file)` grain, so a single rid whose
bridged commit touched N files must count as ONE sample of evidence, not N (a
spec-validate CRITICAL finding, fixed before Build closed: `count(*)` would let one
multi-file commit fake evidence-sufficiency for a gate with only one real invocation;
see DEC-004). Python iterates gates in alphabetical order (deterministic) and returns
the FIRST gate meeting either the hard or soft condition, or `None`.

### `_detect_serial_when_parallel(th)`

One SQL query: `candidates` (`SELECT DISTINCT rid FROM kit_gates`) bridged to
`git_fixes` by rid-in-subject match, windowed per rid by `MIN(ts)..MAX(ts)`, then a
self-join (`w1.rid < w2.rid` for determinism) restricted to non-overlapping windows,
with an `EXISTS` subquery checking file-overlap via the same bridge. The `bridge` and
`windows` CTEs are built with INNER JOINs only, so a rid with zero git correlation
never appears in `windows` and can never be paired (the evidence floor is structural,
not an extra `WHERE`). Python computes `min(dur_a, dur_b)` in minutes via a small
`_seconds_between` helper (parses the two ISO8601 window timestamps, returns `None` on
anything unparsable rather than raising).

### `_detect_token_runaway(th)`

Always returns `None`. No query. Docstring states the not-armed reason.

### `DETECTORS` tuple

```python
DETECTORS = (
    _detect_debt, _detect_cost_spike, _detect_misfire, _detect_unknown_density,
    _detect_ceremony, _detect_token_runaway, _detect_serial_when_parallel,
)
```

## After state

- `anomalies.py`: 3 new detector functions, 2 new `DEFAULTS` keys, `DETECTORS` tuple
  extended, `_FIX_SUBJECT_RE` module constant (mirrors `cli.py`'s private one; no
  shared module, deliberate small duplication over new cross-module coupling).
- `cli.py`: `anomalies()` command's own docstring gains one sentence noting
  token-runaway's not-armed state (the only touch; no new command, no signature
  change).
- `tests/test-anomalies-advisor.sh`: new suite, self-contained fixtures (kit run-log
  files + a generated git repo), covering fire/no-fire per detector + the ceremony
  FP-NC + its falsifiability proof.
- `docs/proof-of-done.md`: new feature row `anomalies-advisor`.
- `docs/verification/anomalies-advisor.md`: per-feature detail + real-corpus capture +
  coverage-delta row.

## Acceptance Criteria

1. `_detect_ceremony` fires CUT on a gate with >= `ceremony_min_ran` ran+override runs,
   >= `ceremony_min_ran` of them carrying a known `caught`, and zero true.
2. `_detect_ceremony` fires CONDITION on a gate with >= `ceremony_min_ran` runs, zero
   known `caught`, >= `ceremony_min_ran` git-bridged, and zero of those bridged files
   later fixed.
3. `_detect_ceremony` does NOT fire on a gate with high skip fraction but real
   `caught=true` evidence in its (few) ran runs (the FP-NC).
4. A hand-built "naive skip-rate" query (run inline, not part of the shipped code)
   WOULD flag the FP-NC's gate, proving the real detector's caught/fix-correlation
   conditioning is load-bearing, not decorative.
5. `_detect_ceremony` does NOT fire on a gate with >= `ceremony_min_ran` KNOWN `caught`
   samples where even ONE is true (proves the "NONE true" clause is load-bearing, not
   just the min-sample floor -- a distinct fixture from AC3/AC4, which use a THIN
   sample; a buggy "fires whenever caught_known >= floor, ignoring caught_true" would
   pass AC3/AC4 but must fail this one).
6. `_detect_ceremony` does NOT fire on a gate with only ONE real rid whose single
   bridged commit touches >= `ceremony_min_ran` files (proves `bridged`/`fix_followed`
   count DISTINCT rids, not file-rows -- a `count(*)` regression would fire here).
6a. `_detect_ceremony` does NOT fire on a gate with THIN (below-floor) `caught_known`
    that still contains a real `caught_true >= 1`, even when the SOFT path's own floor
    (`bridged >= ceremony_min_ran`, `fix_followed == 0`) is separately satisfied (DEC-006,
    found by `kit:code-reviewer` on the finished diff -- a distinct fixture from AC5,
    which uses evidence-sufficient `caught_known`).
7. `_detect_token_runaway` always returns `None` (asserted against at least one DB
   state that fires every OTHER detector, proving it never accidentally fires).
8. `_detect_serial_when_parallel` fires on two dep-independent (no shared bridged
   file, both with >= 1 bridged commit) rids whose git-observed windows do not
   overlap, with a plausible minutes-saved metric embedded in the proposal text.
9. `_detect_serial_when_parallel` does NOT fire on a genuinely dependent (shared
   bridged file) pair with the same non-overlapping windows, even though the
   durations alone would clear `serial_min_minutes_saved`.
10. `_detect_serial_when_parallel` does NOT fire on two rids with ZERO git
    correlation each (no anomaly, no crash -- proves the evidence floor, not just the
    non-overlap/file-overlap logic).
11. `--propose` stages each of the above into the cc-backlog staging buffer,
    duplicate-safe (idempotent re-run), same as the shipped detectors.
12. `ledger anomalies --help` lists `ceremony_min_ran` and `serial_min_minutes_saved`.
13. A real `uv run ledger rebuild` + `uv run ledger anomalies --table` capture is
    committed to the verification doc, honestly reporting what fired (or did not) on
    the real corpus.

## Verification

```bash
cd tools/ledger-observatory
bash tests/test-anomalies-advisor.sh
uv run ledger rebuild
uv run ledger anomalies --table
```

All test lines print `PASS`; the final line is `== N passed, 0 failed ==`.

## Edge Cases

- A gate with `ran >= ceremony_min_ran` but `caught_known` between 1 and
  `ceremony_min_ran - 1` (some known, but too thin to trust): neither the hard nor the
  soft path is evidence-sufficient; the gate produces no anomaly (proven on the real
  corpus's `ship` gate: `ran=62`, `caught_known=3` at the default threshold).
- A gate with `caught_known >= ceremony_min_ran` and even ONE `caught_true`: the hard
  path never fires (`caught_true > 0` short-circuits before the soft path is even
  considered) -- see AC5.
- A gate with zero `caught_known` and zero `bridged` (no git correlation data at all
  for that gate, true for most gates on the real corpus today): no anomaly, honestly
  (mirrors `unknown_density`'s SG-03 honest-empty precedent).
- A gate whose ONLY bridged rid has a single commit touching many files: `bridged`
  counts 1 (the rid), not the file count -- see AC6.
- Two rids whose windows OVERLAP (already ran in parallel): excluded by the
  non-overlap `WHERE` clause; never a serial-when-parallel candidate.
- Two rids with ZERO git-bridge evidence each: structurally excluded (the `bridge`/
  `windows` CTEs are INNER JOINs, so a zero-evidence rid never enters them) -- see
  AC10. No `WHERE bridged >= 1` guard needed; the join shape enforces it.
- A malformed/unparsable window timestamp: `_seconds_between` returns `None`, the
  pair is skipped, never raises.
- `ceremony`/`serial_when_parallel` each return at most ONE `Anomaly` per `detect()`
  call (first match in a deterministic order), same single-shot shape as the four
  shipped detectors -- multiple simultaneous ceremony gates are a future extension,
  not required here.

## Failure modes

- A future kit gate-ledger emitter change that reuses an existing gate name for a
  structurally different check would silently blend old/new `caught` semantics under
  one gate key; out of scope to guard against here (same limitation `gate-yield`
  already has).

## Out of Scope

- The sessions adapter/table (sub-goal 05); `_detect_token_runaway` stays not-armed
  until then.
- Any CLI command beyond `anomalies`'s own docstring.
- Auto-filing, a scheduler, or cutting any real gate -- the detectors PROPOSE only;
  a human decides via `add-backlog`.
- Slow-gate ranking, kill-churn, discovery-heavy (need session data; not implemented).

## Touches

- `tools/ledger-observatory/src/ledger_observatory/anomalies.py`
- `tools/ledger-observatory/src/ledger_observatory/cli.py` (docstring only)
- `tools/ledger-observatory/tests/test-anomalies-advisor.sh` (new)
- `tools/ledger-observatory/docs/proof-of-done.md`
- `tools/ledger-observatory/docs/verification/anomalies-advisor.md` (new)

## Decision Log

- **DEC-001 (ceremony conditioning):** never a bare skip-rate. `caught` (hard) when
  evidence-sufficient, else the git-bridge fix-correlation proxy (soft, CONDITION not
  CUT). Rationale: the real corpus's `ui-design` gate (1 ran / 6 skipped, 86% skip)
  would be a false positive under any skip-rate rule, for the entirely legitimate
  reason that most runs are not UI work.
- **DEC-002 (dependency-independence proxy):** no new dep-graph adapter; reuse the
  git-bridge file-overlap as the proxy (two runs sharing zero bridged files = safe to
  parallelize). A real dep-graph read (mega-goal ROADMAP `Depends on:` fields) would
  need a new adapter, out of the one-data-path contract's + this sub-goal's scope.
- **DEC-003 (token-runaway not-armed, not faked):** wired into `DETECTORS` now so the
  shape is exercised end-to-end (returns `None`, participates in `detect()`'s loop,
  would be staged correctly once real once armed) without inventing a fake signal.
- **DEC-004 (ceremony's bridge evidence counts DISTINCT rids, not file-rows):**
  `mention_files` is `(gate, rid, file)` grain (one row per file a rid's bridged
  commit touched); `bridged`/`fix_followed` use `count(DISTINCT rid)` so a single
  multi-file commit is one sample, never N. Found by `/kit:spec-validate` as a
  CRITICAL finding on the draft design (a `count(*)` version would let one real
  invocation fake evidence-sufficiency for a `ceremony_min_ran`-sized floor); fixed
  before Build closed, proven by AC6/the `C-multifile-nc` fixture.
- **DEC-005 (serial_when_parallel abandons `kit_runs` for `git_fixes` windowing):**
  the original design (per the goal file's own wording, "over a run's duration")
  pointed at `kit_runs.first_ts/last_ts`. Confirmed during Build that `kit_runs`
  returns 0 rows in this local environment (the `kit_runs` adapter's subprocess into
  `lane-telemetry.sh` returns nothing -- a pre-existing, out-of-scope issue,
  `_meta/megagoals/harness-observatory/DECISIONS.md`), so `kit_runs`-anchored
  fixtures could never be verified end-to-end here. Redesigned to window every
  `kit_gates` rid by its OWN git-bridged commits' `MIN(ts)..MAX(ts)`, per HANDOFF's
  standing windowing lesson (`git_fixes.ts` is the one reliable timestamp). Also
  addresses a `/kit:spec-validate` MAJOR finding (the original `kit_runs`-only design
  had no evidence floor: two runs with zero bridge data each would vacuously pass the
  "no shared file" check and fire on zero real evidence) -- the git-bridge-first
  redesign closes this floor structurally (INNER JOINs), not as an added `WHERE`.
- **DEC-006 (caught_true>0 suppresses BOTH the hard and soft path, unconditionally):**
  found by `kit:code-reviewer` on the finished diff (Round 2, not the draft-stage
  spec-validate pass). The original placement of `if caught_true > 0: continue` lived
  inside the `if caught_known >= min_ran:` branch, so a gate with THIN caught data that
  still contained a real catch (`caught_known` below the floor, `caught_true >= 1`) left
  the soft path free to fire CONDITION on the SAME gate the hard-path guard was
  supposed to protect. Hoisted the guard to run first, unconditionally. Proven
  falsifiable: `tests/test-anomalies-advisor.sh`'s new `C-thin-true` fixture goes RED
  when the guard is reverted to its original (buggy) position, green when restored.

## Review

**Round 1 (`/kit:spec-validate` on the draft design).** Dispatched on the initial draft
(kit_runs-anchored advisor, raw `count(*)` bridge evidence): verdict NEEDS-REVISION, 2
CRITICAL + 3 MAJOR findings (the count-inflation bug, the missing mixed-caught AC, the
zero-evidence advisor gap, the ambiguous ship-filter inheritance, the too-low
minutes-saved floor). All addressed before Build closed: DEC-004/DEC-005 above,
`serial_min_minutes_saved` raised 1.0 -> 10.0, and 3 new fixtures (`C-mixed`,
`C-multifile-nc`, `S-nofire-zero-evidence`) added to `tests/test-anomalies-advisor.sh`,
all green (36/36).

**Round 2 (`kit:code-reviewer` on the finished diff).** A fresh-context reviewer ran
against the actual committed code (not the draft), confirmed both Round-1 CRITICALs
genuinely fixed (traced `count(DISTINCT rid)` end to end; confirmed the evidence floor
is structural via the INNER JOINs, not a runtime check), and found ONE NEW MAJOR: the
`caught_true > 0: continue` guard only lived inside the `if caught_known >= min_ran:`
branch, so a gate with THIN (below-floor) but REAL caught data (e.g. `caught_known=2,
caught_true=1`) left the soft/fix-correlation path free to fire CONDITION anyway,
directly contradicting the module's own "NONE of them true" claim. Fixed by hoisting
`if caught_true > 0: continue` to run BEFORE the `caught_known >= min_ran` branch, so
it applies unconditionally to both the hard and soft paths (DEC-006). Falsifiability
proven: reverting the hoist turns the new `C-thin-true` fixture RED (36/37), restoring
it returns 37/37. `_detect_serial_when_parallel`'s structural evidence floor and
`_detect_token_runaway`'s always-`None` contract were both independently re-confirmed,
no further changes needed there.

## Open questions

None blocking. A future sub-goal may want `_detect_ceremony` to report ALL firing
gates in one anomaly (not just the first), once real ceremony data accrues.
