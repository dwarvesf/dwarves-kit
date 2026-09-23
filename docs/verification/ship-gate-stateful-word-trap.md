# Verification: ship-gate subject-word trap

Proof class: behavioral. The change narrows one input to `classify()` in `lib/gate/proof-ledger.sh`; it holds no state and needs no rollback beyond a revert.

## Bug

`classify()` grepped the changed paths AND the commit subjects for stateful keywords. A tests-only branch whose negative-control commit said "restore" classified stateful, and the ship-gate demanded a rollback section that described nothing.

## Change

Subjects are read only when some non-doc changed path is outside the test-path pattern. Paths are matched in every case. Reasoning: `docs/implementation-notes/ship-gate-stateful-word-trap.md`.

## Cases

| Case | Diff | Subject | Old lib | New lib |
|---|---|---|---|---|
| (a) the bug | `tests/test-helper.sh` | "put the probe back: restore the helper" | stateful | behavioral |
| (b) real migration | `db/migrations/002.sql` + test | "migrate the orders table" | stateful | stateful |
| (b2) mixed code+test | `lib/y.sh` + test | "add the nightly backup" | stateful | stateful |
| (b3) mixed, large diff | `lib/y.sh` + 4000 test paths | "add the nightly backup" | stateful | stateful |
| (c) stateful path | `lib/deploy.sh` | "tweak the helper" | stateful | stateful |
| md-only (existing) | `docs/x.md` | "migrate eval + tool dialects" | inert | inert |

## Green run

```
Command: bash tests/test-classify-md-inert.sh
PASS md-only 'migrate' diff -> inert
PASS code+'migrate' diff -> stateful (preserved)
PASS code-only diff -> behavioral
PASS inert-FIRST-stripped lib classifies md-only 'migrate' as stateful (the bug; fix is load-bearing)
PASS tests-only 'restore' diff -> behavioral
PASS migration+test 'migrate' diff -> stateful (preserved)
PASS code+test 'backup' diff -> stateful (preserved)
PASS code+4000 tests 'backup' diff -> stateful (large diff)
PASS lib/deploy.sh, neutral subject -> stateful (unchanged)
PASS guard-stripped lib classifies tests-only 'restore' as stateful (the bug; guard is load-bearing)
---
ALL PASS (10/10)
Exit: 0
```

```
Command: bash tests/run-all.sh --changed
run-all: --changed against 75a2c5c: 5 changed files -> 26 suites (21 named, the rest always-on)
run-all: all 26 suites passed, 0 skipped for missing tooling
Exit: 0
```

## NEGATIVE CONTROL

Taken after the final fix was committed (6536c9e), against `origin/master` (a572bab, whose `proof-ledger.sh` equals the branch base 75a2c5c).

```
## Negative control (negctl, base-ref mode)
Base ref: origin/master
Command: PROOF_LEDGER_LIB=$PWD/lib/gate/proof-ledger.sh bash <worktree>/tests/test-classify-md-inert.sh
Exit: 1 (base ref, RED expected)
Verdict: PASS
```

Per-case output of the same suite against the old lib shows which case goes red:

```
Command: PROOF_LEDGER_LIB=<origin/master extract>/lib/gate/proof-ledger.sh bash tests/test-classify-md-inert.sh
PASS md-only 'migrate' diff -> inert
PASS code+'migrate' diff -> stateful (preserved)
PASS code-only diff -> behavioral
[NO EXECUTABLE CHECK: could not strip the inert-FIRST block]
FAIL tests-only 'restore' should be behavioral, got stateful
PASS migration+test 'migrate' diff -> stateful (preserved)
PASS code+test 'backup' diff -> stateful (preserved)
PASS code+4000 tests 'backup' diff -> stateful (large diff)
PASS lib/deploy.sh, neutral subject -> stateful (unchanged)
PASS guard-stripped lib classifies tests-only 'restore' as stateful (the bug; guard is load-bearing)
---
FAILS: 2
```

Case (a) is the load-bearing red: the old lib reads the tests-only "restore" diff as stateful. Cases (b), (b2), (b3) and (c) pass on both libs, so their verdicts are unchanged. The `NO EXECUTABLE CHECK` line is expected: the old lib has no guard for the md-only control's strip anchor to find. The suite also carries its own history-independent control (the guard-stripped lib), green above.

## Review round

A code-reviewer lens found the first draft's guard piped into `grep -qv` under `pipefail`. On a large diff the early exit SIGPIPEd the upstream grep and the guard skipped the subjects, failing open. Case (b3) reproduced it before the fix:

```
Command: bash tests/test-classify-md-inert.sh   (on the first draft)
FAIL large code+test 'backup' should be stateful, got behavioral
FAILS: 1
```

The guard now captures the filtered list, and (b3) passes. The lens also flagged `spec/` as a production-contract collision; the pattern dropped `spec`.

Verdict: PASS
