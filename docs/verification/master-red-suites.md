# master-red-suites: proof of done

Change: eight red or timed-out suites from a full `tests/run-all.sh --all` on a shallow `file://` clone of master (c8ba04ae), fixed at the root cause. Branch `fix/master-red-suites`, tested at e02a635c.

## Root causes

| Suite | Cause | Kind | Fix |
|---|---|---|---|
| test-install-contract | install mock never linked `kit.toml`; gate-ledger reads lane data from it since 148c6923. Control "adopt must fail without contract symlinks" obsolete since ca34e023 (adopt writes a self-contained pointer) | stale test | mock links `kit.toml`; NC drops `kit.toml`; adopt control now asserts the pointer lands byte-identical |
| test-no-personal-paths | `docs/verification/reminders-timeout.md` (ffc0936f) quoted the operator workspace path | real leak | path replaced by a placeholder |
| test-proof-dir-layout | operator overlay `[gate] negative_control = "full"` (read since 90818cf6) waived the control the fixture asserts | test not isolated | pin `KIT_CONFIG_OPERATOR` to `tests/fixtures/gates-on` |
| test-proof-verdict-hint | same overlay leak (cases 2a, 5, 6) | test not isolated | same pin |
| test-registry-verbs | `flick` verb in FEATURES.md had no line in workflow-paths.md | real doc gap | line added |
| test-research-arch-contract | row 7 pinned the old "Step 2: Research (if brownfield)" heading; renamed by d6dfb6de | stale test | pins the depth-gated heading, the routing sentence and the `research-repo` wants call |
| test-run-all-time | whole-second `date +%s` ticks: a `sleep 2` fixture reads 3s under load; passes alone | flaky timing, not a slowdown | accept [sleep, sleep+1] |
| test-meta | ~130s alone, over 300s at 4 suites in parallel; also red on a stale `docs/FEATURES.md` | budget + stale generated doc | per-suite ceiling table (test-meta 900s) in run-all; FEATURES.md regenerated |

None of these depended on the clone being shallow: all reproduced in the worktree except the load-dependent test-run-all-time and test-meta timeout. The shallow clone is green too (below).

## NEGATIVE CONTROL

NC1: removed the `test-meta) echo 900 ;;` arm of `suite_timeout()` in `tests/run-all.sh`, ran `tests/test-run-all-timeout.sh`, restored the file.

Command: `bash tests/test-run-all-timeout.sh` (table arm removed)
Exit: 1
Result: RED as expected
Excerpt: `FAIL: test-meta=300 allgood=300 meta+env=7 allgood+env=7` then `test-run-all-timeout: 6 passed, 1 FAILED`

NC2: removed the `export KIT_CONFIG_OPERATOR=` pin from `tests/test-proof-dir-layout.sh` on this host (its overlay sets `negative_control = "full"`), restored the file.

Command: `bash tests/test-proof-dir-layout.sh` (pin removed)
Exit: 1
Result: RED as expected
Excerpt: `FAILS: 1` (green-only should BLOCK but the gate passed)

## Green runs, worktree (each suite alone)

| Suite | Exit | Tail |
|---|---|---|
| test-install-contract | 0 | `PASS=4 FAIL=0` |
| test-no-personal-paths | 0 | `Passed: 3 / 3` |
| test-proof-dir-layout | 0 | `ALL PASS (3/3)` |
| test-proof-verdict-hint | 0 | `ALL PASS (10/10)` |
| test-registry-verbs | 0 | `PASS=7 FAIL=0` |
| test-research-arch-contract | 0 | `Passed: 28 / 28` |
| test-run-all-time | 0 | `test-run-all-time: all 4 passed` (3 repeats) |
| test-run-all-timeout | 0 | `test-run-all-timeout: all 7 passed` |
| test-meta | 0 | `Passed: 902 / 902`, 130s |

## Green runs, shallow clone

`git clone --depth 1 --no-single-branch file://<worktree>`, `git rev-parse --is-shallow-repository` = true, HEAD e02a635c, `origin/master` present.

| Suite | Exit | Tail |
|---|---|---|
| test-install-contract | 0 | `PASS=4 FAIL=0` |
| test-no-personal-paths | 0 | `All no-personal-paths tests passed.` |
| test-proof-dir-layout | 0 | `ALL PASS (3/3)` |
| test-proof-verdict-hint | 0 | `ALL PASS (10/10)` |
| test-registry-verbs | 0 | `PASS=7 FAIL=0` |
| test-research-arch-contract | 0 | `All research-architecture contract tests passed.` |
| test-run-all-time | 0 | `test-run-all-time: all 4 passed` |
| test-run-all-timeout | 0 | `test-run-all-timeout: all 7 passed` |
| test-meta | 0 | `Passed: 902 / 902`, 153s |

Verdict: PASS
