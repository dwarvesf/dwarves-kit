# Proof of done cc-hyg-09: override CI/IaC guard + non-vacuous debounce test

VERDICT: PASS

Follow-up fixes from the cc-hygiene sub-goal 09 review round (findings against the
merged sub-goal 04, df2315e).

## Acceptance criteria

1. (Security MAJOR) The proof-ledger override source-remainder guard also treats CI
   workflow yaml (`.github/**/*.yml`), IaC (`.tf/.tfvars`), and build files
   (Makefile/Dockerfile/Justfile) as source, so a blanket override cannot pass them
   unproven, closing the same bypass class as rtk-611 for these file types.
2. (Test-coverage HIGH) The session-state debounce test asserts the real SIDE EFFECT
   (no archive rotation on a skip), not just the DEBUG log string, so a refactor that
   keeps the log line but drops the `exit 0` is caught.

## Implementation

- `lib/proof-ledger.sh` `check()` override block: added `tf|tfvars` to the source-ext
  regex; a `case` for `.github/workflows|actions/*.y{,a}ml`; and Makefile/Dockerfile/
  Containerfile/Justfile to the extensionless-source case.
- `tests/test-hooks.sh`: debounce test now uses an archive-count oracle (skip → 0
  rotations); added override tests for CI-yaml / .tf / Makefile (REJECTED) + a
  plain config.yaml/json control (still PASSES, not over-blocked).

Recorded run: `Command:` bash tests/test-hooks.sh `Exit:` 0 (455/455).
Rollback: this is a pure library + test change with no state/data migration; rollback is `git revert` of the commit (no restore/rollback procedure needed). [UNAVAILABLE: no stateful rollback flow , not a deploy/data change.]

## Confirmation run-table (2026-07-02)

| # | Command | Exit | Output |
|---|---------|------|--------|
| 1 | `bash tests/test-hooks.sh` | 0 | `Passed: 455 / 455` |
| 2 | all 11 CI suites (ubuntu-sim `GIT_CONFIG_GLOBAL=/dev/null`) | 0 | 0 failures |
| 3 | override on `.github/workflows/ci.yml` | (rejected) | `ledger: override on .github/workflows/*.yml -> REJECTED` |
| 4 | override on `main.tf` | (rejected) | `ledger: override on .tf IaC -> REJECTED` |
| 5 | override on `Makefile` | (rejected) | `ledger: override on Makefile -> REJECTED` |
| 6 | override on plain `config.yaml`+`data.json` | (pass) | `-> PASS (not over-blocked)` |

## NEGATIVE CONTROL

Both fixes are falsifiable, mutation-verified:

- **Debounce oracle bites:** mutating `session-state-save.sh` to keep the "skipping"
  log line but drop the `exit 0` (so it rewrites on every Stop) makes the new
  side-effect assertion FAIL: `session-state: debounce did NOT rotate last-state.md
  (side-effect oracle) (expected exit 0, got 1)`. The old log-string-only test passed
  that mutation; the new one catches it.
- **Override guard bites:** the CI-yaml / .tf / Makefile override tests each expect
  exit 1 (rejected); disabling the new detection flips them to exit 0 (pass), failing
  the tests. The plain-config control (exit 0) ensures the guard does not over-block
  inert config/docs.

## Reproduce

```
cd <dwarves-kit>/.claude/worktrees/cc-hyg-09-fix   # or merged master
GIT_CONFIG_GLOBAL=/dev/null bash tests/test-hooks.sh   # 455/455
```
