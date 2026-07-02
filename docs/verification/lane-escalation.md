# Proof of done: lane mid-flight escalation (SPEC-094, ADR-0028 pt 4, kit-hardening SG-06)

Verdict: PASS

## Acceptance criteria -> confirmation

| AC | Criterion | How proven | Result |
|----|-----------|------------|--------|
| AC1 | `escalate <current-lane> <spec-file>` exists, dispatches, classifies the spec's own text | `lib/lane-classify.sh` `escalate()` + `main()` case; usage string | PASS |
| AC2 [up-only] | a `tiny` current lane + a spec whose text carries auth/data-model/migration scope escalates to `full` | `escalate tiny tests/fixtures/lane-escalation/heavy-scope-spec.md` -> `ESCALATE tiny -> full` | PASS |
| AC3 [downgrade guard, NEGATIVE CONTROL] | a `full` current lane + a trivial spec never downgrades | `escalate full tests/fixtures/lane-escalation/trivial-spec.md` -> `HOLD full`, never `ESCALATE`; same-rank case also HOLDs; the pre-existing `check` guard still fires unmodified | PASS |
| AC4 [re-plan] | `start` then `start --amend` at a heavier lane re-plans the ledger up-only | `required full` (11 gates) > `required tiny` (0 gates); last `START-AMEND` line carries `lane=full`; both `START` and `START-AMEND` lines persist (append-only) | PASS |
| AC5 [advisory + recorded] | `escalate` always exits 0; the wiring documents advisory, never a hard block | exit 0 on both ESCALATE and HOLD; `commands/execute.md` contains "advisory", "not a hard block", the `escalate` call, `start --amend`, and the up-only `Lane:` header rule | PASS |
| AC6 [scope edges] | classify-time triggers + the pre-existing downgrade guard are unchanged | `classify "add jwt authentication and a data-model migration"` still returns `full`; `check tiny "...jwt sessions..."` still prints `LANE-DOWNGRADE` | PASS |

## Implementation

- `lib/lane-classify.sh` -- new `escalate()` function (re-classifies the SPEC file's
  own text via the existing `classify_core`, compares `lane_rank` against the current
  lane, prints `ESCALATE <cur> -> <heavier>` or `HOLD <cur>`, exits 0 always); wired
  into `main()`'s case statement and the usage string. Pure, side-effect-free -- it
  does not touch the gate-ledger or any spec file.
- `commands/execute.md` -- new "Spec->build lane re-check (SPEC-094, ADR-0028
  refinement point 4)" subsection in Prerequisites, right after the spec-status check
  and before Step 1 dispatches any task. On `ESCALATE`: (1) `gate-ledger.sh start
  --amend` re-plans the ledger's effective lane up, (2) the spec's `Lane:` header is
  bumped up (never down) so `hooks/ship-gate.sh:140` enforces the heavier required-gate
  set, (3) `gate-ledger.sh action` records the escalation. On `HOLD`: no action. All
  advisory (exit 0 always); a missed re-check does not stop `/kit:execute` (ADR-0024).
- `tests/fixtures/lane-escalation/heavy-scope-spec.md` -- a spec whose text carries
  auth + data-model + migration language, for the positive case.
- `tests/fixtures/lane-escalation/trivial-spec.md` -- a purely cosmetic spec, for the
  downgrade-guard negative control.
- `tests/test-lane-escalation.sh` -- 22 assertions across AC1-AC6.
- `docs/implementation-notes/lane-escalation.md` -- deltas (boundary-hook placement,
  whole-file classification, pure-function/caller-mutates split, `lane_rank` reuse).

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-lane-escalation.sh` | 0 | 22/22 passed |
| `bash tests/test-meta.sh` | 0 | 576/576 passed |
| `bash tests/test-hooks.sh` | 0 | 438/438 passed |

## Run detail

```
=== lane-escalation (SPEC-094 AC1-AC6) ===
  PASS AC1: lane-classify.sh dispatches 'escalate'
  PASS AC1: usage string documents the escalate signature

=== POSITIVE: tiny + emergent-scope spec escalates to full ===
  PASS AC2: escalate tiny+heavy-scope-spec prints ESCALATE tiny -> full
  PASS AC2: escalate exits 0 on ESCALATE

=== DOWNGRADE GUARD [NEGATIVE CONTROL]: full + trivial spec never downgrades ===
  PASS AC3 [NEGATIVE CONTROL]: escalate full+trivial-spec HOLDs at full (never downgrades)
  PASS AC3 [NEGATIVE CONTROL]: no ESCALATE line ever appears for a lighter re-class
  PASS AC3: escalate exits 0 on HOLD too
  PASS AC3: same-rank re-class also HOLDs (bug vs bug-ranked text)
  PASS AC6: the pre-existing 'check' downgrade guard still fires (untouched)

=== GATE-LEDGER RE-PLAN: start --amend re-plans up-only ===
  PASS AC4: required(full) has strictly more gates than required(tiny)
  PASS AC4: last START-AMEND wins -- ledger's effective lane is now full
  PASS AC4: the amend line is recorded as START-AMEND, not a second plain START
  PASS AC4: append-only stands (2 lines: START then START-AMEND, neither overwritten)

=== ADVISORY + RECORDED: escalate never halts; the wiring says so ===
  PASS AC5: escalate exits 0 on ESCALATE (advisory, never blocks)
  PASS AC5: escalate exits 0 on HOLD (advisory, never blocks)
  PASS AC5: commands/execute.md wiring documents advisory
  PASS AC5: commands/execute.md wiring documents 'not a hard block'
  PASS AC5: commands/execute.md wires the escalate call
  PASS AC5: commands/execute.md wires the up-only start --amend re-plan
  PASS AC5: commands/execute.md documents bumping the spec Lane: header
  PASS AC5: commands/execute.md states the header bump is up-only (never down)

=== SCOPE EDGES: classify-time triggers untouched ===
  PASS AC6: classify-time trigger (task text) still lands on full unchanged

=== 22/22 passed, 0 failed ===
```

## NEGATIVE CONTROL (the downgrade guard is load-bearing)

The dangerous direction ADR-0028 pt 4 explicitly rules out is escalation sliding into a
downgrade mechanism. The control: `escalate full tests/fixtures/lane-escalation/trivial-spec.md`
re-classifies a purely cosmetic spec (matches the `tiny` rule -- "pure cosmetic") against
a `full` current lane. `lane_rank(tiny)=1 < lane_rank(full)=3`, so the comparator
(`sr -gt cr`) is false and the function prints `HOLD full`, never `ESCALATE full ->
tiny`. A second assertion greps the raw output for any `^ESCALATE` line and fails the
suite if one is found. A third control confirms a SAME-rank re-class (`bug` vs.
bug-ranked text) also HOLDs -- "only heavier escalates" covers both the lighter and
the equal case. If a future edit flipped the comparator to `-ge` or `-lt`, this test
would go from HOLD to a false ESCALATE and the suite would fail red. The pre-existing
`lane_check`/`check` downgrade guard (a different call site, same `lane_rank` function)
is asserted unmodified in the same run, so a regression in the shared `lane_rank`
would fail both guards together, not just this new one.

## Reproduce

```
cd dwarves-kit
bash tests/test-lane-escalation.sh   # 22/22, exit 0
bash tests/test-meta.sh              # 576/576, exit 0
bash tests/test-hooks.sh             # 438/438, exit 0
```
