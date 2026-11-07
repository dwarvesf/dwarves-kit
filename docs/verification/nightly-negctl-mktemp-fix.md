# Verification -- nightly regression: negctl case 56 and the mktemp guard

Two suites failed every night on the Mini's `mini.kit-nightly-regression`, which runs `tests/run-all.sh --all` on a fresh clone of `master`.

| Suite | First red | Cause | Side that was wrong |
|---|---|---|---|
| `test-proof-negctl` case 56 | 2026-11-03 (first nightly after #1084) | The case asserted no `''` disposition in `trap -p INT TERM`. The nightly launcher backgrounds the run with `&`, so SIGINT arrives ignored, and a non-interactive shell cannot un-ignore it. Cases 31/32/45 already detect that; case 56 did not. | The test. `negctl.sh` resets what its own `restore()` ignored, which is all #1084 promised. |
| `test-mktemp-template-guard` G1 | 2026-11-06 (first nightly after #1090) | `tests/test-install-mods.sh:23` assigned `tmp="$(mktemp ...)"` with no `|| return 1`, which rule R3 requires. | The violating file. The guard is untouched. |

Case 42 is not involved; it passes in every logged run.

## Green run
```
Command: bash tests/test-proof-negctl.sh                      (foreground)
Exit: 0
Output: test-proof-negctl: all 57 passed
Command: bash -c 'bash tests/test-proof-negctl.sh & wait $!'   (backgrounded, SIGINT inherited ignored, as the nightly runs it)
Exit: 0
Output: [56] ok: no test run saw INT/TERM ignored beyond the inherited baseline
        test-proof-negctl: all 57 passed
Command: bash tests/test-mktemp-template-guard.sh
Exit: 0
Output: === 11 passed, 0 failed ===
Command: bash tests/test-install-mods.sh
Exit: 0
Output: PASS=55 FAIL=0
Command: bash tests/run-all.sh --only <each of the three suites>   (backgrounded)
Exit: 0
Output: run-all: all 1 suites passed, 0 skipped for missing tooling   (three times)
Verdict: PASS
```
Before the fix the backgrounded run reproduced the nightly exactly: `[56] FAIL: rc=0 siglog=run ... trap -- '' SIGINT` and `test-proof-negctl: 56 passed, 1 FAILED`. The mktemp guard reproduced as `R3 tests/test-install-mods.sh:23` and `10 passed, 1 failed`.

## Negative control
Case 56 must still catch the bug #1084 fixed. Mutation: delete `trap - INT TERM HUP;` from `run_test` in `lib/gate/negctl.sh`.
```
Command: sed -i 's/run_test() { (trap - INT TERM HUP; cd/run_test() { (cd/' lib/gate/negctl.sh && bash tests/test-proof-negctl.sh
Exit: 1 (foreground, RED expected)
Output: FAIL: rc=0 base= extra=trap -- '' SIGINT
        test-proof-negctl: 56 passed, 1 FAILED
Command: same mutation, suite backgrounded (SIGINT already ignored)
Exit: 1 (RED expected)
Output: FAIL: rc=0 base=trap -- '' SIGINT extra=trap -- '' SIGTERM
        test-proof-negctl: 56 passed, 1 FAILED
Restore: git checkout -- lib/gate/negctl.sh   (tree clean, suite green again)
Verdict: PASS
```
The relaxed assertion still fails when negctl adds an ignore, in both launch modes; it only stops blaming an ignore negctl did not add.

Mktemp guard control: removing `|| return 1` from `tests/test-install-mods.sh:23` brings back `R3 tests/test-install-mods.sh:23` and `10 passed, 1 failed`; restoring the suffix returns `11 passed, 0 failed`.
```
Verdict: PASS
```

## How the nightly picks it up
`tools/kit-nightly-regression/deploy/macos/kit-nightly-regression` in ops-toolkit shallow-clones `dwarvesf/dwarves-kit` `master` into a temp dir on every run. Merging this PR is the whole deploy; the 04:00 +07 run after the merge tests it. No pull or kickstart.
