# Verification -- wrap-land-pr-gate

`wrap land` refuses to open a new PR with the title as its body when the repo has a GitHub PR template, and waits for the PR's checks before the first merge on a repo whose workflows trigger on `pull_request`, refusing the merge when one failed.

Defect evidence: four PRs on one repo were opened by `land` with a 45 to 62 char title-only body, then squash-merged about 5 seconds later. The repo's `PR evidence` check (it requires a `## How I verified it` section) had not registered when the merge ran, so it went red after the merge and only emailed.

Lane: bug. Files: `lib/wrap/wrap-land.sh`, `tests/test-wrap-land.sh`, `lib/config/module-registry.md`, `commands/wrap.md`, `docs/CHANGELOG.md`.

## Green run
```
Command: bash tests/test-wrap-land.sh
Exit: 0
Output: test-wrap-land: all 435 passed
Verdict: PASS
```
Eight new case groups (27 checks), all green:

| Case | Proves |
|---|---|
| PG1, PG1b | template present and no `--body-file`: exit 2, template path named, no `pr create`, nothing pushed, worktree kept; a lowercase `docs/pull_request_template.md` is found; `--body-file` lets the land through |
| PG2 | no template: the title-as-body fallback is unchanged |
| PG3 | a red check: `MERGE REFUSED #42: checks failed: PR evidence; PR left open`, exit 2, no `pr merge` |
| PG4 | green checks: merges |
| PG4b | a check that registers on the third read is waited for, then judged (the actual defect shape) |
| PG4c | a check still pending at the bound refuses |
| PG5 | no `pull_request` workflow: no `statusCheckRollup` read at all |

Neighbouring suites after the change:

```
Command: bash tests/test-wrap-ci.sh   -> test-wrap-ci: all 127 passed
Command: bash tests/test-wrap-merge.sh -> test-wrap-merge: all 246 passed
Command: bash tests/test-wrap-carry.sh -> test-wrap-carry: all 135 passed
Command: bash tests/test-wrap-cli.sh   -> test-wrap-cli: all 22 passed
Command: bash tests/test-meta.sh       -> All meta tests passed.
```

## Negative control
```
Command: perl -e '$SIG{TERM}="DEFAULT"; $SIG{INT}="DEFAULT"; exec @ARGV' bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Mutation: git show 8c8f9f01:lib/wrap/wrap-land.sh > lib/wrap/wrap-land.sh
Changed: lib/wrap/wrap-land.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```
The mutation puts the pre-change `wrap-land.sh` back. Against it the new cases fail 19 of 27 checks (`test-wrap-land: 416 passed, 19 FAILED of 435`): every PG1, PG1b, PG3, PG4b and PG4c check goes red, while PG2, PG4 and PG5 (the unchanged-behaviour cases) stay green, as they should. The file was restored from HEAD and the suite is green again.

The `perl` wrapper resets SIGINT and SIGTERM to default. `negctl.sh` ignores both for the rest of its process after the restore step, children inherit that, and the suite's own interrupt cases (`land-merge: an interrupted cycle exits 130`) then fail on the post-restore run, so a bare `bash tests/test-wrap-land.sh` command reports `FAIL: test not green after restore` on this suite. That is a `negctl.sh` limitation, not a defect in this change; the same suite passes by hand.

## Not proven
- No live GitHub run. `gh` is stubbed in the suite (real git, real worktrees, stubbed PR and check answers), so the 5-second race itself, real check registration latency and a real `PR evidence` workflow are not exercised.
- The `pull_request` detection is a plain grep of `.github/workflows`, so a commented-out trigger still arms the wait (one grace period, 30s by default).
- A repo that gates checks on a label and runs nothing on `pull_request` without it waits one grace period and then merges, the same as before the change.
- `tests/test-config-registry.sh` reports one failure (`declared root-only keys == actual kit_config_get_root call sites`) that is also present on unmodified master.
