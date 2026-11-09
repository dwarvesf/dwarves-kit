# Verification -- land checks wait and empty ignored directories

`wrap land` reads a per-repo checks wait (`wrap.checks_secs`) and its ignored-file guard skips an ignored directory that holds no file.

## Green run
```
Command: bash tests/run-all.sh
Exit: 0
Output:
test-wrap-carry                                ok
test-wrap-ci                                   ok
test-wrap-cli                                  ok
test-wrap-land                                 ok
test-wrap-ship                                 ok
run-all: all 40 suites passed, 0 skipped for missing tooling
Verdict: PASS
```
The new cases: PS1 to PS4 (default 300, project value, env beats project, four bad values) in the `prgate` section; 4f to 4j (empty dir, nested empty dirs, file, deep file, nested symlink) in the `ignored` section.

## Negative control
Checks wait: the two changed files reverted to the pre-change revision, PS2 and PS4 go RED (6 failures), restored and green again.
```
## Negative control (negctl)
Command: LAND_CACHE=0 LAND_ONLY=prgate bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Output:
    PASS PS4 [-5]: exactly one notice line
    PASS PS4: the notice names the bad value
  --- PG5: no pull_request workflow pays nothing: no rollup read before the merge
    PASS PG5: exits 0
    PASS PG5: no statusCheckRollup read
    PASS PG5: merged
  
  test-wrap-land: LAND_ONLY='prgate' selected 1 of 16 sections
  test-wrap-land: 1 sections, 1 ran, 0 cached (0 checks credited)
  test-wrap-land: all 53 passed

Mutation: git show 778fe67b:lib/wrap/wrap-carry.sh > lib/wrap/wrap-carry.sh; git show 778fe67b:lib/wrap/wrap-land.sh > lib/wrap/wrap-land.sh
Changed: lib/wrap/wrap-carry.sh, lib/wrap/wrap-land.sh
Exit: 1 (under mutation, RED expected)
Output:
    FAIL PS4 [-5]: exactly one notice line
    FAIL PS4: the notice names the bad value
  --- PG5: no pull_request workflow pays nothing: no rollup read before the merge
    PASS PG5: exits 0
    PASS PG5: no statusCheckRollup read
    PASS PG5: merged
  
  test-wrap-land: LAND_ONLY='prgate' selected 1 of 16 sections
  test-wrap-land: 1 sections, 1 ran, 0 cached (0 checks credited)
  test-wrap-land: 47 passed, 6 FAILED of 53

Restore: git checkout HEAD -- lib/wrap/wrap-carry.sh lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Empty directory: `wrap-land.sh` reverted to the revision before that fix, 4f and 4g go RED (4 failures), 4h to 4j (a file still refuses) stay green, restored and green again.
```
## Negative control (negctl)
Command: LAND_CACHE=0 LAND_ONLY=ignored bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Output:
    PASS 23: no refusal
  --- 24: a touched path with a newline refuses, never scoped open
    PASS 24: exits 1
    PASS 24: names the newline
    PASS 24: no push
    PASS 24: no PR create, edit, ready or merge
  
  test-wrap-land: LAND_ONLY='ignored' selected 1 of 16 sections
  test-wrap-land: 1 sections, 1 ran, 0 cached (0 checks credited)
  test-wrap-land: all 92 passed

Mutation: git show c86c52a8:lib/wrap/wrap-land.sh > lib/wrap/wrap-land.sh
Changed: lib/wrap/wrap-land.sh
Exit: 1 (under mutation, RED expected)
Output:
    PASS 23: no refusal
  --- 24: a touched path with a newline refuses, never scoped open
    PASS 24: exits 1
    PASS 24: names the newline
    PASS 24: no push
    PASS 24: no PR create, edit, ready or merge
  
  test-wrap-land: LAND_ONLY='ignored' selected 1 of 16 sections
  test-wrap-land: 1 sections, 1 ran, 0 cached (0 checks credited)
  test-wrap-land: 88 passed, 4 FAILED of 92

Restore: git checkout HEAD -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven
- The real wait against a live 6-minute CI: the gh stub reports a pending check and `sleep` is a no-op, so the bound shown is the printed number, not elapsed time.
- `wrap merge` and `wrap apply` carry waits read the same variable but only `wrap land` resolves the project value.
