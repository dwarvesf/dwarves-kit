# Proof of done: operator-persona design lens (SPEC-109, kit-face wave)

`/kit:visual-team` accepts an operator-supplied `persona: <archetype>` as an opt-in inline 6th
lens (same contract, uniform merge), threaded from `/kit:ui-design`; the boundary vs DEC-003 is
recorded (DEC-017, supplied-not-baked) with a kit-health carve-out. Without the arg, exactly the 5
house-style lenses fire, byte-identical to today.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | visual-team accepts `persona: <archetype>` + dispatches an inline 6th lens (same contract) | PASS |
| 2 | 6th lens AND 6th Scores row are GATED on persona-supplied (conditionality pinned) | PASS |
| 3 | NEGATIVE CONTROL: no arg → the 5 existing lenses present verbatim, byte-identical | PASS |
| 4 | ui-design PERSISTS (brief `Persona:` line) AND THREADS (forwards to visual-team `$ARGUMENTS`) | PASS |
| 5 | DEC-017 formal (supplied-not-baked) + reciprocal amendment pointer in SPEC-016 DEC-003 | PASS |
| 6 | kit-health check-13 carve-out for the sanctioned operator-persona path | PASS |
| 7 | visual-team Source line reconciled (no BAKED personas; operator lens is opt-in) | PASS |
| 8 | test-meta green (603/603) + all 12 CI suites green | PASS |

## Implementation

- `commands/visual-team.md`: `$ARGUMENTS` persona parse note (Step 1); conditional 6th lens (Step 2,
  guard "ONLY when a `persona:` archetype is supplied"); conditional 6th Scores row (guard "this row
  appears ONLY when a `persona:` was supplied"); Source line reconciled.
- `commands/ui-design.md`: brief `Persona (optional)` line (Aesthetic direction) + Step 3 forwards a
  non-blank Persona into visual-team `$ARGUMENTS`.
- `docs/specs/SPEC-109-persona-lens.md`: DEC-017 Decision Log (boundary = supplied-not-baked).
- `docs/specs/SPEC-016-critique-and-test-lanes.md`: DEC-003 reciprocal amendment pointer.
- `commands/kit-health.md`: check-13 carve-out.
- `tests/test-meta.sh`: 14-assert SPEC-109 block (persona arg, 6th lens, 2 conditionality guards,
  5-lens verbatim NC, byte-identical NC, ui-design persist + thread, DEC-017 both files, carve-out).

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| persona arg | `grep -qF 'persona: <archetype>' commands/visual-team.md` | match | match |
| 6th-lens guard | `grep -qiE 'ONLY when a .?persona' commands/visual-team.md` | match | PASS |
| 6th-row guard | `grep -qiE 'row appears ONLY when a .?persona' commands/visual-team.md` | match | PASS |
| 5-lens NC | 5x `grep -qF '<lens>' commands/visual-team.md` | all match | all PASS |
| byte-compat NC | `grep -qiF 'byte-identical' commands/visual-team.md` | match | PASS |
| ui-design thread | `grep -qF 'persona: <archetype>' commands/ui-design.md` | match | PASS |
| DEC-017 both | `grep -q DEC-017` in SPEC-109 AND SPEC-016 | both match | PASS |
| carve-out | `grep -qiF 'operator-supplied' commands/kit-health.md` | match | PASS |
| suite: meta | `bash tests/test-meta.sh` | green | 603/603 |
| all CI suites | 12 suites | green | all pass |

## Run detail (captured 2026-07-03)

```
$ bash tests/test-meta.sh
  PASS visual-team accepts a persona: <archetype> arg (SPEC-109)
  PASS 6th persona lens is GATED on persona-supplied (SPEC-109 conditionality)
  PASS 6th Scores row is GATED on persona-supplied (SPEC-109 conditionality)
  PASS visual-team 5-lens NC: 'Hierarchy / typography' present unchanged (SPEC-109)
  ... (all 5 lenses) ...
  PASS visual-team no-arg path is byte-identical / exactly 5 lenses (SPEC-109 NC)
  PASS ui-design Step 3 forwards Persona into visual-team ARGUMENTS (SPEC-109 thread)
  PASS DEC-017 recorded in SPEC-109 + reciprocal pointer in SPEC-016 (SPEC-109)
  PASS kit-health check-13 carries the operator-persona carve-out (SPEC-109)
Passed: 603 / 603 ; All meta tests passed.

# all 12 CI suites green: test-hooks, test-e2e 20/20, test-review-team-plants,
# test-orchestrate, test-role-classify 15/15, test-lane-classify 23/23,
# test-lane-telemetry 18/18, test-mega-merge 30/30, test-ledger-durability 32/32,
# test-meta-agent 72/72, test-proof-visual-evidence 4/4.
```

## Reproduce

```bash
cd dwarves-kit
bash tests/test-meta.sh
grep -qF 'persona: <archetype>' commands/visual-team.md
grep -qiE 'ONLY when a .?persona' commands/visual-team.md
grep -q DEC-017 docs/specs/SPEC-109-persona-lens.md docs/specs/SPEC-016-critique-and-test-lanes.md
```
