# SPEC-063: Run legibility: plan, progress, trace + a recordable grill

Status: SHIPPED
Date: 2026-06-10
Lane: normal (classified: normal)
Type: spec-feature / behavioral

## Problem

Four operator observations after the telemetry waves (SPEC-060..062):

1. The grill never visibly fired during the waves. The skips were legitimate (the question
   banks were resolved in conversation) but UNRECORDED, so process adherence was invisible,
   exactly the class of gap the telemetry exists to catch.
2. The run ledger holds the full journey but only in raw pipe lines; there is no formatted
   "full log, xem lại được" view of one run.
3. On entering a lane, nothing announces the steps the run will walk.
4. While walking, nothing shows "đang ở bước nào, mấy trên mấy".

## Decision

All read-side or one-line-record; no new state, no new store:

1. **`gate-ledger.sh plan <lane>`**: the lane's ordered phase checklist, derived from the
   WORKFLOW lane×phase matrix (skip cells omitted; measure-twice = required, run-lite =
   lite), with `grill` prepended as the universal intake phase (SPEC-058; tiny exempt).
   `/kit:assign` prints it right after the lane is committed.
2. **`gate-ledger.sh progress <rid> <lane>`**: plan ∩ ledger. A phase counts disposed when
   the ledger carries ANY entry for it (ran / skipped-with-reason / override); the current
   step is the first phase without one. Output: `<rid> · <lane> · step k/n (<phase>)` +
   a `✓/▶/·` checklist line. AGENTS.md carries the standing rule: print it at each phase
   entry.
3. **`lane-telemetry.sh trace <rid>`**: one run's ledger rendered as a story: routing header
   (lane/type chosen-vs-classified with `<< LANE MISFIRE` / `<< TYPE MISFIRE` flags, time
   window), then the humanized timeline (gates with state + full reason, actions, with
   `escaped-from` indictments called out).
4. **The grill records itself**: `/kit:grill` exits with
   `record <slug> grill ran "<N> questions, <M> contradictions>"`; a conversation-resolved
   skip records `grill skipped "<why>"` (AGENTS.md task loop). A skip without a reason is
   invisible to telemetry, which defeats the point.

## Acceptance criteria

- AC1: `plan normal` lists the matrix phases in order with required/lite marks and a grill
  intake row; `plan tiny` has no grill row.
- AC2: `progress` points ▶ at the first undisposed phase, prints `step k/n`, counts a
  skipped-with-reason phase as disposed, and prints `complete (n/n)` when done.
- AC3: `trace` flags lane/type misfires in the header and calls out escaped-from actions.
- AC4: wiring: assign prints plan; AGENTS carries show-the-road + grill-disposition rules;
  grill.md records itself.
- AC5: no new files under logs/; everything derives from existing ledgers + the matrix.

## Test plan

13 fixture tests (plan rows + tiny exemption, progress pointer + skip-advance + bare-skip
stays a gap, trace flags + indictment callout + multi-START first-wins) + 1 meta wiring pin.
Negative control: remove a recorded phase line from the fixture ledger -> the ▶ pointer
moves BACK to that phase.

## Verification

- `tests/test-hooks.sh`: 262/262 (249 + 13, incl. the record-removal negative control).
- `tests/test-meta.sh`: 421/421 (+1 wiring pin).
- Live dogfood: this run (rid spec-063) recorded `grill skipped` with the conversation
  reason, and `progress spec-063 normal` printed `step 3/8 (spec)` with
  `✓grill ✓think ▶spec ...` while this spec was being written; `trace spec-062` renders
  yesterday's real misfire run with the `<< LANE MISFIRE` flag.

## Review

Date: 2026-06-10. Adversarial pass (probes run, not eyeballed: normalize_phase collisions,
double-digit steps, set-e safety, unicode marks under BRE, ship-gate untouched). Verdict:
**SHIP 8/10**, 1 MEDIUM + 3 LOW:

1. MEDIUM, a bare `skipped` (no reason) disposed the phase, diverging from the
   skipped-with-reason spec text. Fixed spec-faithfully: the awk now requires a non-empty
   reason for skips; 2 companion tests.
2. LOW, multi-START ledgers let the LAST start win, losing the original misfire flag.
   Fixed: first START wins + a `<< MULTI-START (n=N; first wins)` header advisory; 2 tests.
3. LOW, ACTION lines with ` | ` truncated in trace. Fixed: re-join like the GATE handler.
4. LOW (by design), ✓ marks can appear past the ▶ pointer (the ledger is the truth).
   Dispositioned as BACKLOG row ID-050 per the retro contract.

Cleared: no normalize_phase collisions across all 13 matrix phases; numbering continuous;
steps 10+ parse; plan/progress side-effect-free on check(); grill absent from ship-gate
required; unicode checklist marks BRE-safe. Post-fix: hooks 262/262, meta 421/421.
