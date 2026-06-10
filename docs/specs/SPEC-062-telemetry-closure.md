# SPEC-062: Telemetry closure: type misroutes, escaped defects, operator scenarios

Status: SHIPPED
Date: 2026-06-10
Lane: normal (chosen; classifier said bug, the escaped-defect/debug vocabulary tripped it;
the pair is recorded in this run's own START line as a live misfire fixture)
Type: spec-feature / behavioral

## Problem

SPEC-061 measures lane routing but the operator's evaluation goal is wider: "after a few days
of kit runs, have the data to judge (a) classification AND routing accuracy, (b) mid-process
adherence, (c) whether the test scenarios we design are any good." Three holes:

1. **Type misroutes invisible.** START records one `type=`; there is no chosen-vs-classified
   pair for the TYPE axis, so the absorb->eval class of error (a wrong proof DIALECT, the
   harmful kind) never reaches the report.
2. **Test-design quality has no metric.** Nothing links a bug-lane run back to the shipped
   spec whose test plan should have caught it; /kit:test-plan-review-team scores five lenses
   but writes them only into the spec, never the ledger, so nothing aggregates.
3. **The operator contract is unwritten.** WHAT report Han sees and WHEN it triggers existed
   only in conversation.

## Decision

1. **`gate-ledger.sh start`** gains an optional 5th arg: `start <rid> <chosen-lane>
   <classified-lane> <chosen-type> [classified-type] [repo]`. The START line carries
   `ctype=<classified-type>` when given. Backward compatible: a 5-arg call where arg5 is a
   repo name still works for old callers only if they pass 4+repo; the assign wiring is
   updated to pass both. (PR #40 is unmerged; the verb is hours old, no install base.)
2. **`lane-telemetry.sh`**: headline gains `type-misrouted: N`; `misfires` lists type pairs
   (`type=eval chosen-type=spec-feature`) alongside lane pairs; new **escaped defects**
   report section aggregating `escaped-from=<spec>` markers from ACTION lines
   (`<spec> <- <bug-rid>` per defect).
3. **`/kit:debug`** ledger-open step asks: does this defect trace to a SHIPPED spec whose
   tests should have caught it? If yes:
   `bash lib/gate-ledger.sh action <bug-slug> "escaped-from=<spec-slug>"`. One line; skip
   when the defect predates the kit or traces nowhere.
4. **`/kit:test-plan`** + **`/kit:test-plan-review-team`** record their outcome:
   `gate-ledger.sh record <rid> test-plan ran "<verdict/coverage> findings=<K>"`.
5. **WORKFLOW "How lanes are judged"** gains the operator scenarios: a sample report block
   and a WHEN table (S1 session-open nudge via /kit:start; S2 full sweep at /kit:retro,
   recommended after 3-5 days of runs; S3 escaped-defect recorded at debug time, surfaced at
   S1/S2). This is the written answer to "what will I see and when".

## Acceptance criteria

- AC1: fixture with a type-misroute START -> `report` headline counts it; `misfires` names
  the type pair.
- AC2: fixture with an `escaped-from=` ACTION -> `report` prints the escaped-defects section
  naming spec and bug rid.
- AC3: `start` with 5th arg writes `ctype=`; 4-arg calls still work (backward compat).
- AC4: debug/test-plan/test-plan-review-team/assign wiring lines present.
- AC5: WORKFLOW carries the sample report + WHEN table (S1/S2/S3).

## Test plan

Extend the SPEC-061 fixture block: a type-misroute run + an escaped-from ACTION; assert
headline, misfire type pair, escapes section. Backward-compat pin: 4-arg start still writes a
well-formed line. Negative control: strip the `ctype=` KV -> type-misroute count drops to 0.
Meta pins: WORKFLOW scenarios block + debug/test-plan wiring.

## Verification

- `tests/test-hooks.sh`: 249/249 (243 baseline, net +6: type-misroute headline + misfire pair, escaped
  defect named, 5-arg ctype round-trip, 4-arg backward compat, ctype-strip negative control;
  SPEC-061 headline assertions updated to the new format).
- `tests/test-meta.sh`: 420/420 (SPEC-062 wiring pin; SPEC-061 start-usage pin updated).
- Live fixture smoke in the PR body; this run's own ledger (rid spec-062) carries a real
  chosen=normal / classified=bug misfire, visible in `lane-telemetry.sh misfires`.

## Review

Date: 2026-06-10. Adversarial pass (fixture-probed: column shifts, escapes regex edges,
3 start-arity shapes, sample-vs-actual report diff). Verdict: **SHIP 8/10**, 3 LOW, all
fixed in-branch:

1. LOW, a space inside type/ctype/lane values corrupted the space-split KV blob. Fixed:
   all START values sanitized space->`-` at write (repo already was).
2. LOW, the Verification baseline accounting was wrong (242+7 vs the real 243 net +6). Fixed.
3. LOW, SPEC-061 still documented the old start signature. Fixed with a superseded-by note.

Cleared: all three _rows consumers on the 15-col layout (no off-by-one), _escapes handles
multiple markers / EOL / dotted slugs, 4/5/6-arg start all well-formed, no old-shape callers
anywhere, ctype-strip negative control genuinely flips, WORKFLOW sample matches actual output
shape. Post-fix: hooks 249/249, meta 420/420.
