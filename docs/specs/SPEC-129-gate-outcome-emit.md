# Spec: Gate-outcome emit (`caught=` + `START`/`END` timing)

Generated: 2026-07-04
Status: VALIDATED
Lane: full (extends `lib/gate-ledger.sh` , the run-telemetry source of truth , plus a
live emit at `hooks/ship-gate.sh`'s gate boundary and a new additive-equivalence test;
the ADDITIVE property is correctness-critical for every existing reader, so it earns the
deep lane even though the diff is small).

## Problem

`gate-ledger.sh record <rid> <phase> <ran|skipped>` records that a gate RAN, not whether
it CAUGHT anything or how long it took (effectiveness-audit: "Gate run-ledger = CEREMONY
as built , 1 surviving record, blanket overrides"). The gate CATCHES are real but
UNMEASURED. Today the ledger answers "did the gate run?" but not the two questions that
make the gate layer measurable: "did it catch a defect?" and "how long did it take?".

The ledger already carries ADDITIVE markers beside the `| GATE |` line , `| TOKENS |`
(SPEC-110) and `| DEBT |` (ADR-0031/SPEC-123) , each an `ISO8601 | MARKER | k=v` line that
every existing reader IGNORES because they key on `$2=="GATE"` (or `START`/`START-AMEND`/
`ACTION`). That is the exact pattern to mirror: a third additive marker, ignored by
`check()`/`override()`/`descent()`/`_rows()`/the ship-gate, that carries the outcome +
timing.

## Solution

### Approaches considered

1. **A new additive `| OUTCOME |` marker in `gate-ledger.sh`, one verb (`outcome`) with a
   `start`/`end` timing bracket, `caught=` on the end line, duration derived from a
   machine-readable epoch carried on both lines. A reader helper (`outcome-read`) reads the
   bracket back. The live emit wraps `ship-gate.sh`'s `check` boundary (best-effort, writes
   only to the rid ledger, never touches the hook's exit/stdout/stderr).** REUSE: mirrors
   the `tokens()`/`debt()` additive-marker shape verbatim; no new file, no new convention.
   CHOSEN.

2. **A single `| OUTCOME |` line with `caught=` + `dur_ms=` computed by the caller.**
   Rejected: it pushes the timing responsibility onto every caller (each must capture its
   own start time), and it cannot bracket a gate whose duration is only known across two
   points in time. The start/end pair keeps the ledger the single timekeeper.

3. **Derive duration by parsing the two ISO8601 timestamps in field 1.** Rejected on
   PORTABILITY: parsing ISO8601 back to epoch portably is the `date -d` (GNU) vs `date -jf`
   (BSD) trap the kit's CI (ubuntu + macOS) fails on. Carrying an explicit `at=<epoch>`
   (via `date +%s`, identical on both platforms) makes duration pure integer subtraction.

### Chosen shape

`gate-ledger.sh` gains one verb (`outcome`) and one reader (`outcome-read`), plus a live
emit at the ship-gate boundary. Nothing about any existing reader changes; a ledger with
zero `| OUTCOME |` lines behaves byte-identically to today (this keeps every existing test
green), and a ledger WITH them is byte/row-identical through `check()`/`override()`/
`descent()`/`_rows()`/`_token_agg()`/the ship-gate (they all key on `$2`).

## Design

**Marker name:** `OUTCOME` (a third additive marker beside `TOKENS` + `DEBT`).

**Line layout** (mirrors the `| GATE |` field layout `TS | GATE | phase | state | reason`):

```
<ISO8601> | OUTCOME | <phase> | start | at=<epoch>
<ISO8601> | OUTCOME | <phase> | end   | at=<epoch> caught=<true|false> dur_s=<N>
```

- Field 2 is `OUTCOME`, so `check()`/`override()`/`descent()`/`_rows()`/`_token_agg()`/the
  ship-gate (all keyed on `$2=="GATE"|START|START-AMEND|TOKENS|ACTION|DEBT`) IGNORE it. This
  is the load-bearing ADDITIVE property.
- `at=<epoch>` is `date +%s` (portable macOS + ubuntu). Duration = end epoch , matching
  start epoch, pure integer subtraction, no `date -d`/`date -r`/`stat`.
- `caught=<true|false>`: open-fork 2 default , the gate's OWN recorded state decides it
  (non-pass / block / findings / non-zero -> `true`; clean pass -> `false`). Derived at the
  CALL SITE from the gate's state, not re-computed by the ledger. The verb validates the
  value is `true|false`; defaults to `false` when omitted (a clean pass is the safe default).
- The timing bracket is UNCONDITIONAL (every gate that emits gets a start + end).

**Verb:** `outcome <rid> <phase> <start|end> [caught=<true|false>]`
- `start`: appends the start line with `at=<now-epoch>`.
- `end`: looks back for THIS rid+phase's last `start` line, reads its `at=`, computes
  `dur_s = now-epoch , start-epoch` (0 if no start found, so an unbracketed `end` is still
  honest), appends the end line with `caught=` + `dur_s=`.

**Reader:** `outcome-read <rid> [phase]` , for each completed bracket (or the given phase),
prints `<phase> caught=<bool> dur_s=<N>` (last end line wins per phase). Missing end -> the
phase is reported as `incomplete`. This is the round-trip: emit -> read back outcome +
duration.

**Live emit (no-orphan / live invocation path):** `hooks/ship-gate.sh` wraps its
`check "$LANE" "$SLUG"` call:
- `outcome "$SLUG" ship start` before the check;
- on block (check fails, `exit 2`): `outcome "$SLUG" ship end caught=true` (it caught a
  missing-gate defect);
- on pass (`exit 0`): `outcome "$SLUG" ship end caught=false`.
The emit is best-effort (`2>/dev/null || true`) and writes ONLY to the rid ledger , it can
never change the hook's fail-open contract, exit code, or operator output.

## Scope

**In:** the `outcome` verb + `outcome-read` reader in `lib/gate-ledger.sh`; the live emit
at `hooks/ship-gate.sh`'s check boundary; the additive-equivalence test + round-trip test +
`caught=true`/`caught=false` cases + a coverage-delta row.

**Out:** 05's generator that CONSUMES this marker (it is the first consumer; reads it,
degrades gracefully when absent); 02/03/04; docs wiring (06).

**Not:** a new marker file or a second telemetry convention; changing any existing reader's
behavior; re-computing `caught` independently of the gate's recorded state; a full
timing/profiling subsystem.

## Verification

Run `bash tests/test-gate-outcome.sh` (added by this spec). It proves:

1. **Additive-equivalence:** build a ledger with a full run (START + GATE lines + TOKENS +
   DEBT), capture every existing reader's output (`show`, `check`, `override`-audit,
   `descent`, `_rows` via `lane-telemetry.sh`, `_token_agg`). Insert `| OUTCOME |` start/end
   lines. Re-capture. Assert byte-identical.
2. **Round-trip:** `outcome <rid> ship start`; sleep 1; `outcome <rid> ship end caught=true`;
   `outcome-read <rid> ship` returns `caught=true` and `dur_s>=1`.
3. **caught=true on a non-pass, caught=false on a clean pass** (both via the verb and via
   the reader).
4. **Cross-platform:** no `date -d`/`date -r`/`stat -f`/`sed -i ''`; duration is integer
   epoch subtraction; runs identically on ubuntu + macOS.

## After state

`gate-ledger.sh` records a gate's OUTCOME (caught + duration), not just ran/skipped. The
gate layer is MEASURABLE. Every existing reader is byte/row-identical. 05 can generate a
proof-table column from the `caught=` marker; it degrades gracefully when the marker is
absent (additive-tolerant).

## Test plan

See `## Verification`. Coverage matrix:

| Category | Case | Covered by |
|---|---|---|
| Happy path | emit start/end, read back caught+dur | round-trip test |
| Catch signal | caught=true on non-pass | caught-true test |
| Catch signal | caught=false on clean pass | caught-false test |
| Additive-equivalence | every reader byte-identical with marker present | equivalence test |
| Reader tolerance | `_rows`/`_token_agg` skip OUTCOME lines | equivalence test |
| Edge | `end` with no prior `start` -> dur_s=0, honest | round-trip test (unbracketed case) |
| Edge | bad `caught` value rejected | validation test |
| Portability | no BSD-only date/stat constructs | grep guard in test |
| Live path | ship-gate emits OUTCOME on block + pass | ship-gate emit test |

**Coverage-delta:** changed non-test lines (gate-ledger.sh verb+reader ~35, ship-gate.sh
emit ~6) are all exercised by added test lines (test-gate-outcome.sh). Covered: the verb,
the reader, both caught values, additive-equivalence across all readers, the live ship-gate
emit, portability. Uncovered: 05's consumption of the marker (out of scope, 05's own tests);
a concurrent multi-writer race on the SAME rid+phase bracket (the ledger is append-only and
last-end-wins, so a race produces an extra honest bracket, never corruption , not a defect
this marker owns).
