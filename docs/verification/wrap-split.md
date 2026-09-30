# Proof of done: wrap.sh and test-wrap.sh split (SPEC-374)

Verdict: PASS

Baseline = pre-split monolith (`tests/test-wrap.sh`, 5,987 lines, 1,581 asserts). The two baseline FAILs are wording asserts that predate the split: "step 10 re-sizes the real diff before landing" and "commands/wrap.md classifies each candidate's lane".

## T1 code split

| Check | Command | Result |
|-------|---------|--------|
| Function count | `cat lib/wrap/wrap*.sh \| grep -cE '^[A-Za-z_][A-Za-z0-9_]*\(\) *\{'` | 98, `uniq -d` empty |
| Byte rebuild | concatenate modules in original order, `diff` vs origin wrap.sh | empty (3,616 lines) |
| Top-level statements | spec awk, sorted diff vs origin | only the added source loop |
| No set/exit/shebang | `grep -nE '^(set \|exit\|#!)' lib/wrap/wrap-*.sh` | no output, exit 1 |
| Guards kept | spec guard grep over ci, carry, merge | `guard ci`, `guard carry`, `guard merge` |
| `bash -n` | all 13 files | ok |
| `--help` | diff vs `origin/master` `bin/wrap --help` | byte-identical |
| Unknown verb | diff vs `origin/master` `bin/wrap zzznope`, output plus exit code | byte-identical |
| Hooks untouched | `git diff $(git merge-base HEAD origin/master) HEAD -- hooks/` | empty |
| `wrap.sh` mode | `git ls-files -s lib/wrap/wrap.sh` | 755 (bit restored in a follow-up commit) |

## T2 test split

| Check | Result |
|-------|--------|
| Monolith baseline | `test-wrap: 1579 passed, 2 FAILED of 1581` |
| Runner after split (`bash tests/test-wrap.sh`) | `test-wrap: 1579 passed, 2 FAILED of 1581`, 590 s (host load average about 236) |
| Sorted assert-line diff, runner vs baseline | empty (1,581 lines each side) |
| Every suite's assert list vs baseline | `comm -23` subset, no extra line |
| `tests/run-all.sh` | skips files carrying the `# runner:` header, so CI runs each suite once |
| Monolith wall time, idle machine | about 8 minutes |
| `bash tests/test-meta.sh` | `Passed: 887 / 887`, 180 s |
| Other guards | `test-bin-forwarders.sh` 48/48, `test-gitattributes-union.sh` 27/27 |
| Registry | `feature-registry.sh check --fix docs/FEATURES.md`: fresh, no change |

## Per-suite standalone results

| Suite | Passed | Total | Timing | Note |
|-------|--------|-------|--------|------|
| test-wrap-scan | 41 | 41 | n/a | |
| test-wrap-apply | 242 | 242 | n/a | runs serial under run-all |
| test-wrap-pull | 120 | 120 | n/a | |
| test-wrap-carry | 135 | 135 | n/a | |
| test-wrap-merge | 212 | 212 | n/a | |
| test-wrap-ci | 127 | 127 | 85 s | loaded machine |
| test-wrap-land | 126 | 126 | 102 s | loaded machine |
| test-wrap-start | 59 | 59 | 22 s | loaded machine |
| test-wrap-log | 114 | 114 | n/a | |
| test-wrap-deploy | 145 | 146 | n/a | 1 FAIL, baseline wording red |
| test-wrap-rebase | 102 | 102 | 91 s | loaded machine |
| test-wrap-report-lint | 134 | 135 | n/a | 1 FAIL, baseline wording red |
| test-wrap-cli | 22 | 22 | n/a | |
| Total | 1,579 | 1,581 | | only the two baseline reds |

## Vacuous-pass red proofs

Each suite was shown able to fail: a temporary break in the module under test, then `git checkout --` restore. `git status --short lib/` was empty afterward.

| Suite | Temporary break | Assert that went red | Result |
|-------|-----------------|----------------------|--------|
| scan | `echo "plain-dir"` in `cmd_scan` | under: the plain directory is skipped silently | 40 + 1F of 41 |
| apply | `echo "delete main"` in `cmd_apply` | apply --apply never touched the default branch | 241 + 1F of 242 |
| pull | `echo "FAILED pull --ff-only"` in `_pull_default` | union carry: the pull did not fail (+2 siblings) | 117 + 3F of 120 |
| carry | `echo "FAILED"` in `_carry_stray_commits` | stray commits --apply: the pull did not fail (+3 siblings) | 131 + 4F of 135 |
| merge | `echo "eligible #32"` in `cmd_merge` | merge: a PR authored by someone else is not eligible | 211 + 1F of 212 |
| ci | `CI_WAIT_END=0; return 0` at top of `_ci_checks_wait` | ci-wait T3b: never merges on pre-label checks alone (+21) | 105 + 22F of 127 |
| land | `--base main` on both `gh pr create` calls | the create call never names a base | 125 + 1F of 126 |
| deploy | `echo "DEPLOYED ..."` on the failure branch of `_deploy_wait_poll` | deploy-wait never claims DEPLOYED on a failure (+ siblings) | 141 + 5F of 146 |
| log | `echo "index.lock held by another writer"` in `cmd_knowledge_root` | knowledge-root: non-git repo never prints the index.lock message | 113 + 1F of 114 |
| report-lint | dropped the `BLOCKER_RE` guard on the self-runnable warn | a stated blocker clears the warn | 133 + 2F of 135 |
| rebase | `return 1` first in `_rb_changelog_merge` | rebase: pure-addition CHANGELOG exits 0 (+2 siblings) | 99 + 3F of 102 |
| cli | covered by the runner diff and the per-suite subset check | n/a | see T2 table |

## T3 test-affected

Base `HEAD` so the selection isolates the one-line change. `origin/master` has moved since the branch point and would select unrelated suites.

| Step | Command | Output |
|------|---------|--------|
| Rebase line selection | append `# x` to `lib/wrap/wrap-rebase.sh`, `bin/test-affected --base HEAD --list` | `tests/test-meta.sh (always)` and `tests/test-wrap-rebase.sh (module wrap/wrap-rebase.sh)` only |
| First run | `bin/test-affected --base HEAD` | `PASS tests/test-meta.sh`, `PASS tests/test-wrap-rebase.sh`, 2 pass, 214 s |
| Second run, same content | same command | `CACHED` both, 2 cached, 4 s |
| Key moved | append `# y`, same command | `CACHED tests/test-meta.sh`, `PASS tests/test-wrap-rebase.sh`, 32 s |
| Common line selection | append `# x` to `lib/wrap/wrap-common.sh`, `--list` | `test-meta.sh` plus all 13 `tests/test-wrap-*.sh` suites, never the runner `tests/test-wrap.sh` |

PASS, CACHED, PASS holds for the rebase suite. Both temporary appends were restored with `git checkout --`.

## Negative control

| Step | Result |
|------|--------|
| Break | `return 1` inserted as the first body line of `_rb_changelog_merge` in `lib/wrap/wrap-rebase.sh` |
| Run every `tests/test-wrap-*.sh` | only test-wrap-rebase.sh moves beyond baseline |
| Named assert | FAIL `rebase: pure-addition CHANGELOG exits 0`, plus FAIL `rebase: CHANGELOG keeps origin's bullet` and FAIL `rebase: CHANGELOG counted as one stop`; 99 passed, 3 FAILED of 102 |
| Other suites | exit 0 except deploy (145/146) and report-lint (134/135), the two baseline reds |
| Restore | `git checkout -- lib/wrap/wrap-rebase.sh`, `git status --short` empty |

The runner's exit code does not discriminate because the baseline already carries 2 FAILs, so the named rebase assert is the signal.

## Reproduce

```
bash tests/test-wrap.sh
bash tests/test-meta.sh
for t in tests/test-wrap-*.sh; do bash "$t"; done
printf '# x\n' >> lib/wrap/wrap-rebase.sh; bin/test-affected --base HEAD --list; git checkout -- lib/wrap/wrap-rebase.sh
```

## Port of #850 (after rebase onto origin/master 56bab0e5)

| Check | Result |
|---|---|
| Label diff, master monolith vs all `tests/test-wrap-*.sh` | empty both ways, 1532 labels each |
| Function count | 99 (98 plus `_reject_packed` in wrap-common.sh), each defined once |
| `--help` and unknown verb vs `origin/master` export | byte-identical |
| Full runner | `test-wrap: 1596 passed, 2 FAILED of 1598` (the two known wording FAILs; master gained 17 asserts) |
| Negative control | removing `_reject_packed` from the land arg loop turns `packed arg to land names the packed-flags refusal` red (127 of 128); restored |

The 1581 counts above predate the rebase; this section supersedes them.

## Recorded run

```
Command: bash tests/test-wrap.sh
Exit: 1
Summary: test-wrap: 1596 passed, 2 FAILED of 1598
Verdict: PASS for this change: the two FAILs are the pre-existing master wording asserts ("step 10 re-sizes the real diff before landing", "commands/wrap.md classifies each candidate's lane"), identical on origin/master

Command: bash tests/test-meta.sh
Exit: 0
Summary: Passed: 887 / 887
```

## Rollback

The change moves code and tests without changing behavior, so rollback is `git revert` of the merge commit: `lib/wrap/wrap.sh` and `tests/test-wrap.sh` return to single files, and `bin/test-affected` and `tests/run-all.sh` return to their previous selection. No state, config or ledger format changes, so nothing else needs undoing.
