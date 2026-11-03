# Verification -- wrap-ship-verb

`wrap ship` composes `start --carry`, a commit of the named paths, an explicit-only proof override and `land` in one call (spec: `docs/specs/SPEC-416-wrap-ship-verb.md`).

## Green run

The new suite, on the repo's harness (real git, gh stub, fixture git hooks), under bash 5 and bash 3.2:

```
Command: bash tests/test-wrap-ship.sh
Exit: 0
Output:
  test-wrap-ship: all 115 passed
Verdict: PASS
```

```
Command: /bin/bash tests/test-wrap-ship.sh
Exit: 0
Output:
  test-wrap-ship: all 115 passed
Verdict: PASS
```

The whole wrap family, since `ship` sources beside `start`, `land` and `adopt` and the shared harness line changed:

```
Command: bash tests/run-all.sh --only test-wrap
Exit: 0
Output:
  run-all: 18 suites, 4 at a time, 1 serial
  test-wrap-adopt ok, test-wrap-apply ok, test-wrap-carry ok, test-wrap-ci ok, test-wrap-cli ok,
  test-wrap-deploy ok, test-wrap-flick ok, test-wrap-land ok, test-wrap-log ok, test-wrap-merge-nopull ok,
  test-wrap-merge-stacked ok, test-wrap-merge ok, test-wrap-pull ok, test-wrap-rebase ok,
  test-wrap-report-lint ok, test-wrap-scan ok, test-wrap-ship ok, test-wrap-start ok
  run-all: all 18 suites passed, 0 skipped for missing tooling
Verdict: PASS (4m11s)
```

The real flow, run by hand in a scratch repo whose origin is a local bare repo (not GitHub, so `land` stops at its PR lookup, the first step that needs GitHub):

```
Command: KIT_LEDGER_DIR=<scratch> bin/wrap ship <repo> docs/real --carry real.md --message-file <msg> --proof-override "docs only, scratch repo"
Exit: 2
Output:
  carried: real.md
  ship: worktree <repo>/.claude/worktrees/real
  ship: committed 1b34db5 (1 files)
  proof-of-done override logged for slug 'real' in repo '<repo>' (trace: <scratch>/proof-overrides.log)
  ship: override logged (slug real)
  land docs/real -> main (<repo>/.claude/worktrees/real)
       PR REFUSED: open-PR lookup for docs/real failed
  LAND: refused (pr-lookup, exit 2)
  resume: wrap land <repo>/.claude/worktrees/real
  SHIP: refused (land:pr-lookup, exit 2) worktree=<repo>/.claude/worktrees/real
Verdict: PASS (carry, commit, override and the land hand-off ran for real; land's own refusal and exit code passed through)
```

## Negative control

Control 1: the override becomes unconditional (the explicit-only rule, AC-3 and AC-4). Run after the code was committed (`f448aa03`):

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-ship.sh" "perl -0pi -e 's/if \[ "\$reason_given" -eq 1 \]; then\n    _SHIP_STEP=override/if true; then\n    _SHIP_STEP=override/' lib/wrap/wrap-ship.sh"
Exit: 1 (under mutation, RED expected)
Output:
  test-wrap-ship: 103 passed, 12 FAILED of 115
  Restore: git checkout HEAD -- lib/wrap/wrap-ship.sh
  Exit: 0 (green after restore)
Verdict: PASS
```

Control 2: the HEAD-is-the-new-branch check and the default-branch name check both removed (AC-12):

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-ship.sh" "perl ... (replace the HEAD != branch condition with false and the default-name case arm with a never-matching one) lib/wrap/wrap-ship.sh"
Exit: 1 (under mutation, RED expected)
Output:
  test-wrap-ship: 113 passed, 2 FAILED of 115
  Restore: git checkout HEAD -- lib/wrap/wrap-ship.sh
  Exit: 0 (green after restore)
Verdict: PASS
```

Both mutations were restored; `git status` was clean afterwards.

## Not proven
- No run against real GitHub. The PR create, merge and tree-verify steps run against the repo's gh stub (as every other wrap suite does); the hand run above stops at `land`'s PR lookup. `land` itself is unchanged and covered by `tests/test-wrap-land.sh`.
- The real ship-gate is not exercised on `land`'s push; a fixture `pre-push` hook stands in for it (the spec's Grounding says so).
- Negative controls ran for the override rule and the default-branch rule only; the other refusals are asserted by their own cases and not mutated one by one.

## Rollback
The change is additive. Revert the feature commit (or delete `lib/wrap/wrap-ship.sh`, the `ship` arm, the `source` entry and the usage lines in `lib/wrap/wrap.sh`); no other verb reads it. The only state `ship` writes is what `start`, `git commit`, `proof-ledger.sh override` and `land` already write. A stray override line is append-only audit data and stays, scoped to its repo and slug.
