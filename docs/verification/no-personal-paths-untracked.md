# Verification -- no-personal-paths-untracked

The always-on `test-no-personal-paths` tree scan listed files with `git ls-files`, so a file not yet committed was never scanned. A proof written after the last local run (the usual order) reached master carrying an operator path, and the nightly regression went red a day later. The scan now lists tracked plus untracked-but-not-ignored files, and the two leaking lines in the merged proof are rewritten to a portable form.

| # | Run | Command | Exit | Result | Verdict |
|---|---|---|---|---|---|
| 1 | Red on origin/master | `bash tests/test-no-personal-paths.sh` | 1 | `Passed: 2 / 3`, two lines of `docs/verification/ship-gate-cd-var.md` flagged | PASS |
| 2 | Green run after the fix | `bash tests/test-no-personal-paths.sh` | 0 | `Passed: 3 / 3` | PASS |
| 3 | Diff-scoped regression | `bash tests/run-all.sh --changed --time` | 0 | `all 8 suites passed, 0 skipped for missing tooling` | PASS |
| 4 | Negative control A: the old proof text restored | `git show origin/master:docs/verification/ship-gate-cd-var.md` over the file, then the suite | 1 | `Passed: 2 / 3`, red; green again after restoring the fix | PASS |
| 5 | Negative control B: an untracked file carrying an operator path | the suite, new scan vs the origin/master scan | 1 new, 0 old | new scan red, old scan stays green (blind spot shown) | PASS |

## Green run
```
Command: bash tests/test-no-personal-paths.sh
Exit: 0
Output:
ok - adopt renders no render-time install path into the consumer repo
ok - rendered files still point at the kit (portable ~ or $HOME form)
ok - no operator path or hostname anywhere in the tree

Passed: 3 / 3
All no-personal-paths tests passed.
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
test-no-personal-paths                         ok (1s)
test-no-scattered-ids                          ok (1s)
test-operator-pin                              ok (3s)
run-all: all 8 suites passed, 0 skipped for missing tooling
```

## NEGATIVE CONTROL
Control A, the original defect. The merged proof text is put back and the suite run:
```
Exit: 1
ok - adopt renders no render-time install path into the consumer repo
ok - rendered files still point at the kit (portable ~ or $HOME form)
NOT ok - operator path/hostname still present:
Passed: 2 / 3
1 test(s) failed.
```
The fixed text is restored afterwards and the suite is green again (run 2).

Control B, the class. A throwaway untracked file under docs/verification holds an operator home path. The suite from origin/master (tracked files only) still exits 0 with `Passed: 3 / 3`, so the leak is invisible until the file is committed. The suite with the `--others --exclude-standard` listing exits 1 with `Passed: 2 / 3` and names the file. The probe file is removed afterwards.

## Why PR time did not catch it
No CI runs on a pull request or push (test.yml is dispatch and release tags only, by design). The local gate is `bash tests/run-all.sh --changed`, which does run this suite (marked `# always:`). That run happens before the proof is written, and the scan ignored untracked files, so the proof committed afterwards was never scanned.
