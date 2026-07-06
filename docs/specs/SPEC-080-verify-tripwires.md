# SPEC-080: verify-this delta + architecture tripwires (absorption pair)

Status: SHIPPED
Date: 2026-06-11
Lane: normal (classified: normal)
Type: spec-feature / behavioral (command-prose contracts + one README shape line)
Board: ID-077, ID-080
Source: docs/absorption/2026-06-11-pinned-kits.md #3 (cursor verify-this, MIT,
@74dd229) + #6 (cursor thermo-nuclear, 2 rules only)

## Decision

1. **verify-this delta (ID-077)**, three pieces into `/kit:verify`:
   (a) Step 5 gains a claim-restatement preamble , before measuring, restate
   what is being verified as condition + metric + threshold, so the verdict has
   something falsifiable to land on; (b) `INCONCLUSIVE` joins PASS/FAIL as a
   legal verdict , no valid baseline, noisy signal, or a confound means the
   honest answer is neither pass nor fail (today such runs get forced into a
   fake binary); (c) `docs/verification/README.md` run-record shape gains an
   OPTIONAL `Baseline:/Treatment:/Delta:/Threshold:` evidence line for
   comparative claims (perf/memory/UX). `lib/gate/proof-ledger.sh` DEVIATION (review HIGH): the
   absorption sketch said untouched, but a record with `Verdict: INCONCLUSIVE`
   plus `Exit: 0` satisfied the gate via the Exit alternative , the gate now
   carries an explicit INCONCLUSIVE rejection guard on both check paths, pinned
   behaviorally (synthetic INCONCLUSIVE record exits 1; same record with PASS
   exits 0).
2. **Two tripwires (ID-080)** appended to review-team Reviewer 2's prompt:
   (a) a PR must not push a file from under 1k lines to over 1k without a
   stated strong reason; (b) weird if-statements in random places = a design
   problem, not a nit (the spaghetti-growth rule). Two rules, not the upstream
   skill.

## Acceptance criteria

- AC1: verify.md carries the claim-restatement preamble + INCONCLUSIVE in the
  verdict line + its three named causes; meta pins, failing-first.
- AC2: verification README carries the optional comparative-evidence line; pin.
- AC3: review-team Reviewer 2 prompt carries both tripwires; pins.
- AC4: proof-ledger diff is EMPTY (INCONCLUSIVE never satisfies the gate); pin
  asserts proof-ledger does NOT mention INCONCLUSIVE.
- AC5: suites green; NC: prose revert flips pins RED.

## Verification

- Pins failing-first: 4 RED pre-edit -> green; the lens-2 wave added 4
  behavioral gate fixtures (INCONCLUSIVE blocks; PASS control; append-retry
  passes; latest-INCONCLUSIVE blocks). Suites: hooks 412/412, meta 454/454,
  e2e 20/20.
- NC: INCONCLUSIVE prose token reverted -> 1 RED -> restored.

## Review

Date: 2026-06-11. Two lenses (the proof-ledger touch invoked the lib escalation
mid-review). Lens 1 (consistency/fidelity 7/10): HIGH , a Verdict: INCONCLUSIVE
record with Exit: 0 SATISFIED the gate via the Exit alternative; the spec's
untouched-proof-ledger assumption was wrong, deviation recorded, rejection
guard added. Lens 2 (guard semantics 5/10): 2 HIGH , the whole-file/union scan
blocked the DOCUMENTED append-retry workflow (old INCONCLUSIVE + new PASS);
fixed with last-verdict-wins on both paths (+ sorted set-wise concat, ^ anchor,
4 behavioral fixtures incl. the reverse-order block). README verdict vocab +
verify next-action + SPEC-035 drift also fixed. Verdict: SHIP.
