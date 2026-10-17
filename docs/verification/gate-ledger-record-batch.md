# Verification -- gate-ledger-record-batch

`gate-ledger.sh record-batch <rid> <lane> [--evidence-default "<text>"] <phase>=<ran|skipped|override>:<evidence> ...` records the named phases of a lane in one call (start or amend, record or override each, then `check`), for a build whose design phases ran elsewhere.

| Check | Command | Result |
|---|---|---|
| Suite | `bash tests/test-gate-ledger-plan-record.sh` | 67/67 (41 plan-record cases kept green, 26 new record-batch asserts RB1-RB7) |
| Changed-only regression | `bash tests/run-all.sh --changed --time` | 73/74 suites ok; the one red is a path artifact, see Not proven |
| Real flow | `record-batch demo-run full ...` on a temp ledger root | 13 gates written, check exit 0; amend path; two refusals exit 64 and write nothing |
| Negative control | `lib/gate/negctl.sh`, drop the unknown-phase refusal | RED 64/67 under mutation, green after restore |

## Green run
```
Command: bash tests/test-gate-ledger-plan-record.sh
Exit: 0
Output:
    PASS RB4 unknown state exits 64 and writes nothing
    PASS RB5 batch on an existing ledger exits 0
    PASS RB5 one START plus one START-AMEND
    PASS RB5 the amend moves the lane and keeps classified and type
    PASS RB5 a second call still adds no plain START
    PASS RB6 override items land as override lines
    PASS RB6 a shared override reason exits 65
    PASS RB6 the refused batch writes nothing, START included
    PASS RB7 unknown lane refuses and writes nothing
    PASS RB7 item without = exits 64
    PASS RB7 a phase given twice exits 64
  === 67/67 passed ===
Verdict: PASS
```

## Real primary flow

Against a temp ledger root (`DWARVES_KIT_LOG_DIR`), timestamps elided:
```
Command: gate-ledger.sh record-batch demo-run full --evidence-default "ran in design PR" grill=skipped:"reason=operator-wave: ..." think=ran design=ran design-critique=ran:"critique in design PR" spec=ran validate=ran:"APPROVED fresh agent=t" design-record=ran test-plan=ran build=ran:"branch built" review=ran:"review-team clean" docs=ran ship=ran:"pushed" reflect=override:"lead reflects at wrap"
Exit: 0
Output:
grill              skipped
think              ran
design             ran
design-critique    ran
spec               ran
validate           ran
design-record      ran
test-plan          ran
build              ran
review             ran
docs               ran
ship               ran
reflect            override
Verdict: PASS (13 GATE lines and one START; check full exits 0)
```

```
Command: gate-ledger.sh record-batch demo-run full think=ran:"re-recorded"   (ledger exists)
Exit: 0
Output:
TS | START | lane=full classified=full type=spec-feature repo=<worktree dir>
TS | START-AMEND | lane=full classified=full type=spec-feature repo=<worktree dir>
Verdict: PASS (amended once, no second plain START, classified and type carried over)
```

```
Command: gate-ledger.sh record-batch demo-two full nonsense=ran:x
Exit: 64
Output:
record-batch: 'nonsense' is not a phase of lane 'full' (plan: grill think design design-critique ui-design spec validate design-record test-plan build review docs ship reflect )
Verdict: PASS (refused; no ledger file created for demo-two)
```

```
Command: gate-ledger.sh record-batch demo-two full think=ran
Exit: 64
Output:
record-batch: 'think' has no evidence (give think=ran:<evidence> or --evidence-default)
Verdict: PASS (refused; still no ledger file for demo-two)
```

## Negative control

Run at commit `06a8eff1`, after the feature commit.
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-gate-ledger-plan-record.sh" "<perl one-liner turning the record-batch unknown-phase refusal into `*) ;;`>"
Exit: 1 (under mutation, RED expected)
Output:
  === 64/67 passed ===
Verdict: PASS (RED under mutation: the three RB3 asserts failed; green again after `git checkout HEAD -- lib/gate/gate-ledger.sh`, 67/67)
```

## Not proven
- `tests/test-meta-goal-ledger.sh` fails one pin ("zero gate-ledger rid call sites say spec-slug", got 14) in this worktree only. The pin greps absolute paths for the word `gate-ledger`, and this worktree's directory name contains it, so unrelated `spec-slug` lines match. The same grep with repo-relative paths returns 0. Not caused by this change.
- `record-batch` attests only the caller's evidence text. It reads no parent ledger and checks no PR, so it is weaker than `inherit` by design.
- The full `--all` suite was not run (about 25 minutes; nightly job owns it).
