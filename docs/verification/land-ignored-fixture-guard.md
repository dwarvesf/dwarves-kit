# Proof of done: wrap land refuses a branch whose touched paths hold ignored files

## What changed

`wrap land` (and `wrap adopt`, which calls it) now refuses, before anything is pushed or opened, when the worktree holds a gitignored file under a directory the branch touches. A clean checkout will not have such a file, so a test that reads it passes here and fails there. Build output, tool caches, local config, and the kit's own state are always allowed; `[wrap] land_ignored_allow` (root-only: the operator or kit-root `kit.toml`, never a project `.kit.toml`) adds entries. Contract: `docs/specs/SPEC-394-land-ignored-fixture-guard.md`. Builder deltas: `docs/implementation-notes/land-ignored-fixture-guard.md`.

## Gate table

| Claim | Evidence |
|---|---|
| every Test plan row passes (1 to 24, with row 4 split into 4 and 4b) | `LAND_ONLY=ignored` run below: 70 checks green |
| the full land suite stays green, including the four `ignored.bin` sections | full run below |
| the knob sits in the registry's Root-only table and `kit.toml` carries it once | `test-config-registry` below (AC10) |
| the guard is load-bearing | five negative controls below, each red under its mutation and green after restore |
| no regression in the suites the diff touches | `run-all.sh --changed` below |

## Run table

```
Command: LAND_ONLY=ignored bash tests/test-wrap-land.sh
Exit: 0
Output:
  PASS 22: exits 0 with the operator entry
--- 23: an already-landed branch takes the landed path, the guard never runs
  PASS 23: reports already landed
  PASS 23: no refusal
test-wrap-land: LAND_ONLY='ignored' selected 1 of 13 sections
test-wrap-land: all 70 passed
Verdict: PASS
```

```
Command: LAND_CACHE=0 bash tests/test-wrap-land.sh
Exit: 0
Output:
test-wrap-land: 13 sections, 13 ran, 0 cached (0 checks credited)
test-wrap-land: all 555 passed
Verdict: PASS
```

```
Command: bash tests/test-config-registry.sh
Exit: 0
Output:
=== 59/59 passed ===
Verdict: PASS
```

```
Command: awk '/^\[wrap\]/{s=1;next} /^\[/{s=0} s && /^land_ignored_allow[[:space:]]*=/' kit.toml
Exit: 0
Output:
land_ignored_allow = ""         # [impl] space-separated allow entries for `wrap land`'s ignored-file
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 1
Output:
run-all: --changed against 34b0a10e: 8 changed files -> 57 suites (54 named, the rest always-on)
test-wrap-land                                 ok (179s)
test-wrap-adopt                                ok (137s)
test-config-registry                           ok (74s)
test-meta-docs-registry                        FAIL (rc=1) (258s)
      !   FAIL docs/FEATURES.md is fresh (check verb, SPEC-219)
test-kit-contract                              FAIL (rc=1) (6s)
      !   FAIL no un-grandfathered CC_* env in lib/hooks/bin (offenders: CC_TMP )
      | === kit-contract: 24 passed, 1 failed ===
run-all: 57 suites run, 0 skipped for missing tooling
(55 of 57 suites ok; the host load was 90 or more, so the run was slow)
Verdict: PARTIAL, both reds explained below
```

The two reds, one fixed and one not this change:

```
Command: bash lib/registry/feature-registry.sh check
Exit: 0
Output: feature-registry: docs/FEATURES.md is fresh
Verdict: PASS (after the regenerate commit; it was DRIFTED at the merge-base commit too)
```

```
Command: bash tests/test-meta-docs-registry.sh
Exit: 0
Output:
Passed: 120 / 120
All meta tests passed.
Verdict: PASS
```

```
Command: bash tests/test-kit-contract.sh   (run in an export of origin/master, no branch changes)
Exit: 1
Output:
  FAIL no un-grandfathered CC_* env in lib/hooks/bin (offenders: CC_TMP )
=== kit-contract: 24 passed, 1 failed ===
Verdict: FAIL on master as well, so it is not this change
```

## Test plan coverage

| Row | Case | Run / skip reason |
|---|---|---|
| 1 | ignored `a.raw.json` under a touched unit refuses, nothing pushed | `sec_ignored` case 1 |
| 2 | the same fixture committed through `git add -f` lands | case 2 |
| 3 | an ignored file outside every scope passes | case 3 |
| 4 | the built-in list passes: caches, build output, local config; `tests/.cache` and `lib/*/bin/*-rs` | cases 4 and 4b |
| 5 | nested `.gitignore` match refuses with its full path | case 5 |
| 6 | a slash-free allow entry never matches an ancestor | case 6 |
| 7 | operator path-form entry allows | case 7 |
| 8 | an allow glob never expands against the cwd | case 8 |
| 9 | kit-root layer allows with no operator file | case 9 |
| 10 | a project `.kit.toml` never allows | case 10 |
| 11 | tracked and ignored passes | case 11 |
| 12 | `.git/info/exclude` counts like `.gitignore` | case 12 |
| 13 | root scope: direct children only | case 13 |
| 14 | depth-1 scope: direct children only | case 14 |
| 15 | a space prints raw, a control byte prints as `?` | case 15 |
| 16 | secret-shaped paths carry the marker, no commit hint | case 16 |
| 17 | failed `git status` refuses | case 17 |
| 18 | failed `git diff` refuses | case 18 |
| 19 | failed merge base refuses | case 19 |
| 20 | `status.showUntrackedFiles=no` does not blind the guard | case 20 |
| 21 | an adopted (already open) PR refuses before the re-push | case 21 |
| 22 | a collapsed ignored directory is named with `/`, then allowed | case 22 |
| 23 | an already-landed branch takes the landed path | case 23 |
| 24 | a touched path holding a newline refuses | case 24 |

## Negative controls

Each ran after the feature commit, with `LAND_CACHE=0 LAND_ONLY=ignored bash tests/test-wrap-land.sh`, and was restored with `git checkout -- lib/wrap/wrap-land.sh`.

| NC | Mutation | Red rows (under mutation) | Totals under mutation | After restore |
|---|---|---|---|---|
| 1 | delete the `_land_ignored_guard` call in `cmd_land` | 1, 5, 6, 10, 12 to 22 (every refusal row) | 26 passed, 40 FAILED of 66 | all 66 passed |
| 2 | drop `node_modules` from the built-in list | 4 (`exits 0`, `no refusal`) | 64 passed, 2 FAILED of 66 | all 66 passed |
| 3 | swallow the status read's exit code (`st_rc=0`) | 17 (`exits 1`, `names git status`, `no PR create`) | 63 passed, 3 FAILED of 66 | all 66 passed |
| 4 | skip the scope filter and the pathspec narrowing | 3, 13, 14 | 63 passed, 3 FAILED of 66 | all 66 passed |
| 5 | match slash-free entries against every component | 6 (`exits 1`, `names the path under dist`) | 64 passed, 2 FAILED of 66 | all 66 passed |
| 6 | drop the newline refusal in the diff loop | 24 (`names the newline`, `no PR create`) | 67 passed, 3 FAILED of 70 | all 70 passed |

NC4 as the spec words it (skip the scope filter only) turned rows 13 and 14 red but not row 3: the status call already narrows to `:(literal)tools/x`, so git never reports `other/far.raw.json`. Removing the pathspec narrowing as well, which is what "scope every ignored entry" means in this code, turns row 3 red too. Both runs are recorded in the notes; the table row is the combined mutation.

```
Command: LAND_CACHE=0 LAND_ONLY=ignored bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Mutation: delete the _land_ignored_guard call line in cmd_land
Changed: lib/wrap/wrap-land.sh
Exit: 1 (red under mutation)
Output: test-wrap-land: 26 passed, 40 FAILED of 66
Restore: git checkout -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: LAND_CACHE=0 LAND_ONLY=ignored bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Mutation: drop node_modules from _LAND_IGNORED_BUILTIN
Changed: lib/wrap/wrap-land.sh
Exit: 1 (red under mutation)
Output: test-wrap-land: 64 passed, 2 FAILED of 66
Restore: git checkout -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: LAND_CACHE=0 LAND_ONLY=ignored bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Mutation: set st_rc=0 after the guard's git status read
Changed: lib/wrap/wrap-land.sh
Exit: 1 (red under mutation)
Output: test-wrap-land: 63 passed, 3 FAILED of 66
Restore: git checkout -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: LAND_CACHE=0 LAND_ONLY=ignored bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Mutation: skip the scope filter ([ "$found" -eq 1 ] || continue becomes :) and drop the pathspec narrowing (specs=())
Changed: lib/wrap/wrap-land.sh
Exit: 1 (red under mutation)
Output: test-wrap-land: 63 passed, 3 FAILED of 66
Restore: git checkout -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: LAND_CACHE=0 LAND_ONLY=ignored bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Mutation: the slash-free allow match checks every component (case "/$p/" in */$entry/*)
Changed: lib/wrap/wrap-land.sh
Exit: 1 (red under mutation)
Output: test-wrap-land: 64 passed, 2 FAILED of 66
Restore: git checkout -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```
cd <worktree>
LAND_ONLY=ignored bash tests/test-wrap-land.sh
bash tests/test-wrap-land.sh
bash tests/test-config-registry.sh
bash tests/run-all.sh --changed --time
```

For a negative control: apply the mutation named above with an editor, run the first command and expect the named rows red, then `git checkout -- lib/wrap/wrap-land.sh` and run it again for green.

## Not proven

- No live GitHub run. `gh` is stubbed (real git, real worktrees, stubbed PR answers).
- `wrap adopt` reaches the guard through `cmd_land` and no test plants a file in adopt's own worktree; coverage is by construction plus the green `test-wrap-adopt` suite.
- A fixture outside every scope (a root-level test reading `testdata/x`, a depth-1 test reading a grandchild) is not seen; the scope rule is a heuristic, noted at the scope code.
- `test-kit-contract` reports `no un-grandfathered CC_* env in lib/hooks/bin (offenders: CC_TMP)`. The offender is `lib/gate/gate-ledger.sh`, which this branch does not edit, and the same check fails on an `origin/master` export.
