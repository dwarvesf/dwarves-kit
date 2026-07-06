# Proof of done: sub-goal 01 gate-vocab-align (ID-091)

## Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | A command-driven full-lane run reaches ship-eligible with **zero hand-recorded gates** | PASS | AC4 run-table below: all 12 full-lane required names recorded using the exact literal strings the fixed commands now emit; `gate-ledger.sh check full <rid>` exits 0 |
| 2 | Negative control: removing one phase owner's record call re-blocks the gate | PASS | AC5 run-table below: same 12-gate run with only `build` omitted; `check full <rid>` exits non-zero and names `MISSING-GATE: build` |
| 3 | A test asserts every full-lane required name is recorded by some command (no silent orphan) | PASS | `tests/test-gate-vocab-recording.sh` AC2/AC3, static sweep, 12/12 owners found |
| 4 | Vocabulary itself is untouched (no rename/restructure) | PASS | `normalize_phase()` and `WORKFLOW.md`'s lane matrix are unmodified; only `record` calls were added to 3 command files + the doc note |

## Implementation

Three files gained a `gate-ledger.sh record` call for a name that was already in the full-lane
required-set but had no owner:

| Required name | File | Change |
|---|---|---|
| `build` | `commands/execute.md` | added `record <rid> build ran "..."` right after the Step 3 execution-summary block |
| `design-critique` | `commands/devs-team.md` | added `record <rid> design-critique ran "..."`, kept the existing `review ran` line too (additive) |
| `design-record` | `commands/spec-validate.md` | added `record <rid> design-record ran "..."` in Reviewer 6 (the Design Record Auditor), alongside its existing `Validate ran` line |

`WORKFLOW.md`'s "## Command emit coverage (SPEC-139)" section was updated: the old "Known
pre-existing gap, NOT closed by this pass" paragraph (which named exactly these two rows,
`Build` and `Design record`, as unrecorded) is replaced with a "Gate-recording gap CLOSED
(ID-091)" paragraph naming the fix. The stale cross-reference in the `visual-team.md` exemption
row (which claimed devs-team's `review` emit "already covers the design-critique lens") is also
corrected to point at the new `design-critique` emit.

New test: `tests/test-gate-vocab-recording.sh` (17 checks, Section A static sweep + Section B
dynamic proof against the real `gate-ledger.sh check` mechanism, isolated via
`DWARVES_KIT_LOG_DIR` so the real ledger corpus is never touched).

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| New test, full suite | `bash tests/test-gate-vocab-recording.sh` | **17/17 PASS**, exit 0 |
| AC4 positive: all 12 gates recorded -> ship-eligible | `gl check full demo-full-run` | exit **0** |
| AC5 negative control: `build` omitted -> re-blocked | `gl check full demo-missing-build` | exit **1**, `MISSING-GATE: build` |
| Regression: command-emit sweep | `bash tests/test-command-emit-sweep.sh` | 19/19 PASS, exit 0 |
| Regression: design-record wiring | `bash tests/test-design-record.sh` | 26/26 PASS, exit 0 |
| Regression: references-field | `bash tests/test-references-field.sh` | 15/15 PASS, exit 0 |
| Regression: gate-outcome | `bash tests/test-gate-outcome.sh` | 22/22 PASS, exit 0 |
| Regression: lane-escalation | `bash tests/test-lane-escalation.sh` | 22/22 PASS, exit 0 |
| Regression: meta (full kit self-test) | `bash tests/test-meta.sh` | 679/679 PASS, exit 0 |
| Regression: right-arm parity | `bash tests/test-right-arm-parity.sh` | 38/38 PASS, exit 0 |
| Regression: understanding-wiring | `bash tests/test-understanding-wiring.sh` | 17/17 PASS, exit 0 |

## Run detail

Captured output of `bash tests/test-gate-vocab-recording.sh` (this run's rid: `orchfin-01-gate-vocab`):

```
=== gate-vocab-recording (ID-091) ===
--- Section A: static sweep -- every full-lane required name has a real owner ---
=== AC1: full-lane required set is the expected 12 names (live from WORKFLOW.md) ===
  PASS required full = the 12 measure-twice matrix rows, normalized

=== AC2: each required name has a command that records it by its OWN literal name ===
  PASS 'design-record' is recorded by commands/spec-validate.md (literal 'design-record ran')
  PASS 'test-plan' is recorded by commands/test-plan.md (literal 'test-plan ran')
  PASS 'design-critique' is recorded by commands/devs-team.md (literal 'design-critique ran')
  PASS 'docs' is recorded by commands/docs.md (literal 'Docs ran')
  PASS 'validate' is recorded by commands/spec-validate.md (literal 'Validate ran')
  PASS 'reflect' is recorded by commands/retro.md (literal 'Reflect ran')
  PASS 'build' is recorded by commands/execute.md (literal 'build ran')
  PASS 'think' is recorded by commands/think.md (literal 'Think ran')
  PASS 'spec' is recorded by commands/spec.md (literal 'Spec ran')
  PASS 'review' is recorded by commands/review.md (literal 'review ran')
  PASS 'design' is recorded by commands/design.md (literal 'Design ran')
  PASS 'ship' is recorded by commands/ship.md (literal 'Ship ran')

=== AC3: no-orphan sweep -- every required name is recorded by SOME command, no exceptions ===
  PASS every full-lane required name has at least one command recording it (0 missing)

--- Section B: dynamic proof -- the real gate mechanism, not just text ---
=== AC4: a command-driven full-lane run (all 12 gates recorded by literal name) reaches ship ===
  PASS check full <rid> passes with all 12 gates recorded (exit 0)

=== AC5: NEGATIVE CONTROL -- drop just 'build' (execute.md's own gate), the same run re-blocks ===
  PASS check full <rid> FAILS when build is not recorded (exit != 0)
  PASS the check names 'build' as the missing gate

=== Summary: 17/17 passed ===
```

Gate-ledger entries recorded for this run (`rid=orchfin-01-gate-vocab`):

```
GATE | grill  | skipped | reason=operator-wave: sub-goal file (mega-goal ROADMAP) already fully scoped the task, no live grill session
GATE | build  | ran     | 3 command-file edits (execute.md/devs-team.md/spec-validate.md) + 1 WORKFLOW.md doc update + new test tests/test-gate-vocab-recording.sh, 17/17 checks pass
GATE | review | ran     | self-review: ran test-command-emit-sweep.sh (19/19), test-design-record.sh (26/26), test-references-field.sh (15/15), test-gate-outcome.sh (22/22) -- no regressions
GATE | docs   | ran     | WORKFLOW.md Command emit coverage section updated to reflect the gap CLOSED (was: known pre-existing gap)
```

## Reproduce

```bash
cd dwarves-kit   # this worktree
bash tests/test-gate-vocab-recording.sh     # 17/17, exit 0
bash tests/test-command-emit-sweep.sh       # 19/19, exit 0 (unaffected)
bash tests/test-design-record.sh            # 26/26, exit 0 (unaffected)
bash lib/gate/gate-ledger.sh required full  # -> think/design/design-critique/spec/validate/
                                             #    design-record/test-plan/build/review/docs/ship/reflect
```
