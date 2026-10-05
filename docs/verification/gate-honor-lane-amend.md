# Verification -- gate-honor-lane-amend

Run id: `gate-honor-lane-amend`. Lane: normal.

`hooks/ship-gate.sh` read the lane from the spec's `Lane:` header only, so a ledger `START-AMEND lane=normal` left the push owing the full lane's gates. The hook now takes the last `START-AMEND` lane over the header. A plain `START` never overrides it.

| Claim | Case in `tests/test-ship-gate-fail-closed.sh` | Result |
|---|---|---|
| An amend to normal clears full-only gates | spec full, amend normal, normal gates recorded: push passes | green |
| No amend keeps the full lane | spec full, no amend, normal gates recorded: blocked | green |
| An amend to full raises a normal run | spec normal, amend full, normal gates recorded: blocked | green |
| A plain second `START` cannot lower the lane | spec full, `start normal`, normal gates recorded: blocked | green |

## Green run

```
Command: bash tests/test-ship-gate-fail-closed.sh
Output:  ok - spec full + amend normal + normal gates -> pass (amend clears full-only gates)
         ok - spec full + no amend + normal gates -> blocked (full kept)
         ok - spec normal + amend full + normal gates -> blocked (amend raises)
         ok - spec full + second plain START normal -> blocked (plain START never lowers)
         PASS=11 FAIL=0
Exit: 0
Verdict: PASS
```

## Negative control

| Step | Output |
|---|---|
| Revert `hooks/ship-gate.sh` to the parent commit | `NOT ok - amend to normal should clear full-only gates`, `NOT ok - amend to full should raise a normal run`, `PASS=9 FAIL=2` |
| Restore with `git checkout HEAD -- hooks/ship-gate.sh` | `PASS=11 FAIL=0` |

## Regression

```
Command: bash tests/run-all.sh --changed --time
Output:  run-all: 29 suites run, 0 skipped for missing tooling
Exit: 0 after regenerating docs/FEATURES.md (test-meta-docs-registry was the one red suite, 120/120 after)
Verdict: PASS
```

Also green: `test-ship-gate-impl-notes`, `test-ship-gate-profiles`, `test-lane-escalation`, `test-codex-hooks` (94/94, ship-gate pin refreshed with `lib/codex/repin.sh`).

## Trust note

`gate-ledger.sh start --amend` has no operator versus agent split: any process that can append to the run ledger can write a `START-AMEND`, and the hook honors it in both directions. The amend is append-only and shows in `gate-ledger.sh show`. The diff floor (`_floor_check`) is untouched, so a hard-path diff still owes the full lane's gates whatever the amend says.
