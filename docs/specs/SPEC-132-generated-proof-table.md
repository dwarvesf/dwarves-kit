# Spec: Generated proof-of-done confirmation table

Generated: 2026-07-04
Status: VALIDATED
Lane: normal (a generator + tests over a known ledger schema; no new subsystem, no
correctness-critical concurrency, mostly execution against SPEC-016 + gate-ledger's
already-fixed shapes).

## Problem

A proof-of-done's confirmation run-table is typed by hand today (`docs/verification/*` /
`tools/*/docs/proof-of-done.md`), while the gate/run ledger that could back it
(`lib/gate-ledger.sh`'s `logs/runs/<rid>.log`) is written on every gated run and never read
back into a proof. The ledger is CEREMONY as built: it proves a gate ran, but nothing turns
that record into the human-facing evidence table a proof-of-done needs. This is the same
"single-source, generated, never hand-typed" gap `lib/verif-counts.sh` already closed for
suite pass-counts (`docs/verification/COUNTS.md`); the confirmation table is the same idea
one layer up.

Sub-goal 01 (`gate-outcome-emit`, parallel, not required to be merged first) adds a
`caught=`/timing marker to the ledger so a gate's OUTCOME (did it catch anything, how long
did it take) becomes machine-readable. This spec's generator must surface that column WHEN
IT EXISTS and degrade gracefully when it does not, since 01 has no code dependency here
(mega-goal ROADMAP `## Assumptions`: "05 reads whatever markers exist; degrades
gracefully").

## Solution

### Approaches considered

1. **A Python generator (`lib/proof-table-gen.py`) behind a thin bash launcher
   (`lib/proof-table-gen.sh`), mirroring `lib/handoff-gen` -> `lib/handoff/handoff_gen.py`.**
   The parsing + conditional-column table rendering is naturally a dict/list problem;
   `lib/orchestrate.sh` and friends are explicitly bash-3.2-safe (no `declare -A`, the macOS
   CI runner's default `/bin/bash`), so reaching for associative arrays in bash would fight
   the kit's own portability contract. Python3 is already a first-class dependency here
   (`lib/verif-counts.sh`'s inline python3 substitution, `lib/handoff-gen`, `lib/orchestrate.sh`
   itself shells out to it, `tests/test-hooks.sh`, `tests/test-token-capture.sh`). CHOSEN.
2. **Pure bash + awk, parallel indexed arrays instead of a map.** Doable (gate-ledger.sh
   itself is bash+awk throughout) but the ledger has three line shapes to correlate
   (START/GATE/OUTCOME) into one ordered, presence-gated table; the awk-only version was a
   worse fit for the CAUGHT/DURATION additive-tolerance branch (needs a phase -> outcome
   lookup with a "not present" case, which is exactly what an assoc array is for and bash
   3.2 does not have). Rejected: fights the portability constraint that route-suggest.sh's
   `declare -A` already violates elsewhere; do not add a second violation.
3. **Extend `lib/verif-counts.sh` to also emit the proof table.** Rejected: verif-counts.sh's
   job is "run these fixed suites, transcribe pass/total"; the proof-table generator's job is
   "read one rid's ledger, render a per-phase table". Different input, different output
   shape, different caller (`<rid>`-scoped vs. whole-kit); folding them would make one script
   answer two unrelated questions.

### Chosen shape

`lib/proof-table-gen.sh <rid> [out-path]` resolves the kit's durable log dir the exact way
`lib/gate-ledger.sh` does (sources `lib/kit-log-dir.sh`, calls `kit_migrate_log_dir`, reads
`kit_resolve_log_dir`) so there is one resolver, not two, then execs
`lib/proof-table-gen.py "$@"` with `KIT_ROOT` / `KIT_LOG_DIR` exported. The Python module:

- Reads `$KIT_LOG_DIR/runs/<rid>.log` (the exact ledger `gate-ledger.sh record/start/show`
  write/read) if present; an absent ledger renders an empty-but-valid table, never a crash.
- Parses three line shapes (space-pipe-split, same convention `gate-ledger.sh`'s own awk
  uses): `START`/`START-AMEND` (for `lane=`), `GATE` (phase/state/reason), and the ASSUMED
  01 marker `OUTCOME` (phase/caught/dur_ms -- see "Assumed 01 marker shape" below).
- Reuses `lib/gate-ledger.sh required <lane>` and `lib/gate-ledger.sh check <lane> <rid>`
  as subprocesses for the coverage-delta and acceptance-status rows -- the required-gate
  list and the pass/fail verdict are NOT re-derived by hand; they call the exact same
  logic `hooks/ship-gate.sh` enforces.
- Refuses (exit 1) to write to any `out-path` whose basename is literally `proof-of-done.md`
  -- a hard, code-level backstop for SPEC-016's "generators write run ledgers, never the
  canonical" rule, not just a convention followed by discipline. Default out-path is
  `docs/runs/<rid>.md`.

### Assumed 01 marker shape (not merged; additive-tolerant either way)

Sub-goal 01 is building in parallel. Per the mega-goal ROADMAP's fork note #2 ("`caught=true`
when the gate's own recorded state is a non-pass ... the timing bracket is unconditional")
and "REUSE gate-ledger.sh (a new additive marker beside TOKENS + DEBT)", this spec ASSUMES 01
lands a new marker verb, phase-scoped (mirroring `GATE`'s `TS | GATE | phase | state | reason`
shape, since a gate's outcome is inherently per-phase, unlike TOKENS/DEBT which are rid-level):

```
2026-07-04T10:00:00Z | OUTCOME | <phase> | caught=<true|false> start=<ISO8601> end=<ISO8601> dur_ms=<N>
```

Ignored by `gate-ledger.sh check()/override()/descent()` (they key on `$2=="GATE"`), same
additive guarantee TOKENS/DEBT already rely on. The generator's OUTCOME parsing looks for
`caught=` and `dur_ms=` anywhere in the marker's trailing fields via regex, tolerant of extra
or reordered `k=v` pairs, so a real 01 implementation that differs in field order (or adds
more fields) still parses. If 01's actual shape differs in VERB NAME or field NAMES, the
conductor reconciles at TIER-4 (named in this worker's final report); the additive-tolerance
property (graceful degrade when the marker is entirely absent) holds regardless of the exact
shape, since it is proven by the "no OUTCOME lines at all" test case independent of the
present-case's exact field names.

## Design

### Table layout (adapted SPEC-016 shape)

The literal SPEC-016 "Confirmation (runs)" table (`Run | When | Command | Exit | Verdict`)
describes ad-hoc command executions; the gate/run ledger instead records PHASE dispositions
(`ran` / `skipped` / `override`), which have no "exit code" notion. This generator keeps the
SPEC-016 table-first SKELETON (acceptance -> confirmation -> reproduce, plus a coverage-delta
section this sub-goal specifically owes) but renames the confirmation columns to what the
ledger actually carries: `Phase | When (ISO8601) | State | Reason`, with `Caught | Duration
(ms)` appended ONLY when at least one OUTCOME line exists anywhere in the rid's ledger
(additive-tolerance at the whole-table grain); within a table that has those columns, a
phase with no OUTCOME line of its own still renders `n/a` in those two cells (additive-
tolerance at the per-row grain too -- both grains are proven in the test plan).

The generated file is a companion the human-authored canonical `proof-of-done.md` can point
at (`docs/verification/README.md`: "Generators write run ledgers, never the canonical"); it
does not replace the canonical's hand-authored acceptance/reproduce prose (out of scope,
per the sub-goal's contract).

### Output shape

```markdown
# Generated proof-table: <rid>

> GENERATED by `lib/proof-table-gen.sh` ... Do NOT hand-edit.

Lane: <lane-or-"n/a (no START line)">

## 1. Acceptance criteria
| # | Criterion | Status | Evidence |

## 2. Confirmation (gate runs)
| # | Phase | When (ISO8601) | State | Reason | [Caught | Duration (ms)] |

## 3. Coverage-delta
- Covered: <phases with a ran/override GATE entry>
- Uncovered: <required(lane) - covered, or "n/a (lane unknown)">

## 4. Reproduce
`bash lib/proof-table-gen.sh <rid>`
```

## Acceptance criteria

1. Given a rid with a populated ledger, `bash lib/proof-table-gen.sh <rid>` writes a
   SPEC-016 table-first proof-table under `docs/runs/<rid>.md` with all four sections above.
2. **Round-trip:** for a fixture ledger with known GATE lines, the Confirmation table's
   phase/state/reason rows match the ledger's GATE lines exactly, in ledger order.
3. **Additive-tolerance, present:** with OUTCOME lines (the assumed 01 marker shape) present
   for some phases, the Confirmation table gains Caught + Duration columns, populated for
   those phases and `n/a` for phases with no OUTCOME line.
4. **Additive-tolerance, absent:** with zero OUTCOME lines anywhere in the ledger, the
   Confirmation table has no Caught/Duration columns at all (not "n/a" columns -- physically
   fewer columns), and the generator does not crash or error.
5. **Never overwrites the canonical:** invoking the generator with an explicit out-path whose
   basename is `proof-of-done.md` refuses (non-zero exit, no file written/modified); the
   default out-path is always under `docs/runs/`.
6. **Coverage-delta:** the generated file names covered phases (ran/override in the ledger)
   vs. uncovered (required-by-lane minus covered) when the lane is known from a START line,
   and degrades to an explicit "lane unknown" line (no crash) when it is not.

## Verification

```
bash tests/test-proof-table-gen.sh
```

## Test plan

| # | Category | Case | Asserts |
|---|---|---|---|
| T1 | Round-trip | fixture ledger, 3 GATE lines, no OUTCOME | table rows == ledger rows, in order (AC2) |
| T2 | Additive-tolerance (present) | fixture with OUTCOME lines for 2 of 3 phases | Caught/Duration columns present; populated for 2, `n/a` for 1 (AC3) |
| T3 | Additive-tolerance (absent) | same fixture, OUTCOME lines stripped | Caught/Duration columns entirely absent; exit 0 (AC4) |
| T4 | Not-canonical (hard block) | explicit out-path `.../proof-of-done.md` | non-zero exit; file not written | (AC5) |
| T5 | Not-canonical (default path) | default invocation | out-path is under `docs/runs/` | (AC5) |
| T6 | Coverage-delta, lane known | fixture with a START line (`lane=normal`), 2/3 required gates ran | Covered names the 2; Uncovered names the missing 1 | (AC6) |
| T7 | Coverage-delta, lane unknown | fixture with no START line | "lane unknown" line, no crash | (AC6) |
| T8 | Empty ledger | rid with no ledger file at all | valid empty-but-well-formed table, exit 0 | (robustness, not a numbered AC but load-bearing for "degrades gracefully") |

COVERAGE-DELTA (this sub-goal's own, per the mega-goal quality bar): covered = T1-T8 above
(round-trip, both additive-tolerance directions at whole-table and per-row grain, the
not-canonical hard block at both the explicit and default path, coverage-delta both lane-known
and lane-unknown, and the fully-empty-ledger edge case). Uncovered: a REAL 01 ledger line
(01 is unmerged; T2/T3 use the ASSUMED marker shape, reconciled by the conductor at TIER-4
once 01's actual shape is known) and CI itself running the new test on both `ubuntu-latest`
and `macos-latest` (asserted structurally here by wiring `tests/test-proof-table-gen.sh` into
`.github/workflows/test.yml`, not independently re-run inside this worker's own sandbox).

## Out of scope

- Sub-goal 01's actual emit implementation (05 only consumes whatever marker exists).
- The canonical `proof-of-done.md` authoring workflow / its hand-authored acceptance and
  reproduce prose (this generator produces a companion table, not a canonical replacement).
- Sub-goal 06's docs-wiring (this spec's own wiring into `docs/verification/README.md` is
  in-scope for THIS generator's existence; cross-linking it into AGENTS.md/WORKFLOW.md is
  06's job).
- A new proof-of-done format (reuses the SPEC-016 table-first skeleton, adapted columns only).
