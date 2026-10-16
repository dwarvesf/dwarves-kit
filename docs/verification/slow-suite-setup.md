# Proof of done: faster config lookups and a lean install lib copy

## What changed

Two setup costs, no assertion changed in any existing suite. The third, the Orca fixture build, shipped on its own as #960 and is not part of this branch.

1. `_find_row` in `lib/config/config.sh` forked two `$(_row_get)` subshells per registry row on every seam lookup. It is now one awk pass with the same first-match order and the same split and trim rules (escaped pipes included).
2. `install.sh` ran `cp -R "$KIT_DIR/lib"`, which also copied gitignored build output: `lib/prose-rag/rust/target` (419M), `lib/stats/.venv` (54M), `lib/prose-rag/bin/prose-rag-rs`, `__pycache__`. A dev checkout installed 485M; the install is now 7M. The copy streams through `tar` with the build-output excludes from `.gitignore`.

## Gate table

| Claim | Evidence |
|---|---|
| each touched suite is faster | timing table below |
| assertion sets are identical | check-count table below |
| `_find_row` rewrite is equal to the old loop | equivalence run below (513 keys, 0 diffs) and the seams suite |
| `_find_row` rewrite is load-bearing | negative control 1 |
| install exclude drops only build output | tracked-file diff below (511 of 511 land) |
| install exclude is load-bearing | negative control 2, `tests/test-install-lib-copy.sh` |
| nothing at runtime reads the dropped paths | install artifact findings below |
| no regression in the suites the diff touches | `bin/test-affected` run below |

## Timing table

Before is the p95 from the suite timing history (`bash tests/run-all.sh --times p95 <suite>`), measured under shared load. After is one run of `bash tests/run-all.sh --only <suite> --time` for test-config-seams, and the test-hooks time from the parallel `--changed` run below. The old code was not re-run.

| Suite | Before p95 (s) | After (s) | Main cause |
|---|---|---|---|
| test-config-seams | 344 | 6 | `_find_row` forks |
| test-hooks | 233 | 189 (ran beside 38 other suites, 3 cores) | six installs now copy 7M, not 485M (the worktree carried APFS clones of the build dirs, so the install saw the real layout) |

The before and after columns are not a controlled A/B: the before figures are p95 under load, the test-hooks after figure was taken while 38 other suites ran in parallel. `install.sh` alone, same tree, measured directly: 2.8s with `cp -R`, 1.3s with the tar copy.

## Check counts

| Suite | Before | After |
|---|---|---|
| test-config-seams | 56 (file untouched) | 56/56 passed |
| test-hooks | file untouched | file untouched, suite green |
| test-install-lib-copy (new) | n/a | 5 checks |

## Run table

```
Command: bash tests/run-all.sh --only test-config-seams --time
Exit: 0
Output:
test-config-seams                              ok (6s)
run-all: all 1 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output (rebased on origin/master; the diff selects every suite covering install.sh, lib/config/config.sh, docs/FEATURES.md and the new test):
test-config                                    ok (0s)
test-config-registry                           ok (98s)
test-gate-opt-in                               ok (2s)
test-hooks                                     ok (189s)
test-install-clis                              ok (18s)
test-install-compat                            ok (21s)
test-install-contract                          ok (1s)
test-install-lib-copy                          ok (0s)
test-install-mods                              ok (20s)
test-install-modules                           ok (44s)
test-install-plugin-detect                     ok (5s)
test-install-self-symlink                      ok (0s)
test-meta-docs-registry                        ok (17s)
(26 more suites, all ok; slowest after test-hooks: test-wrap-land 140s, test-config-registry 98s)
run-all: all 39 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

```
Command: bash tests/test-install-lib-copy.sh
Exit: 0
Output:
ok   tracked lib files are copied
ok   a .venv is not copied
ok   a __pycache__ is not copied
ok   rust/target cargo output is not copied
ok   a bin/*-rs built binary is not copied
PASS: install lib copy skips build output
Verdict: PASS
```

Install artifact findings (the question "does the installed kit need a built artifact"):

| Excluded path | Runtime reference | Decision |
|---|---|---|
| `lib/prose-rag/rust/target`, `lib/prose-rag/bin/prose-rag-rs` | none: the crate was retired (`git rm -r lib/prose-rag/rust`), and `bin/prose-rag` resolves `$PROSE_RAG_BIN`, then `ctx`, then `prose-rag` on PATH and "never looks under lib/" | exclude |
| `lib/stats/.venv` | `bin/stats` runs `uv run --project lib/stats`, which creates the venv on first use. The copied venv was also wrong: it is an editable install whose `.pth` and shebangs hold the absolute path of the source checkout, so an installed `stats` imported from the checkout, not the pinned copy | exclude |
| `__pycache__`, `*.pyc` | regenerated by python on first import | exclude |

Nothing was kept: no built artifact under `lib` is needed by the installed kit.

Equivalence of `_find_row` (old loop kept in a scratch script, every env var and kit.toml key in the live registry plus `""`, `-`, a missing key, a key with a backslash, and an escaped-pipe key):

```
Command: bash eq.sh <worktree>
Exit: 0
Output:
compared=513 diffs=0
Verdict: PASS
```

## Negative control

Both controls ran after the change was committed, and each was restored with `git checkout --`.

```
Control 1: in _find_row, match only the kit.toml key column (drop the env var column)
Command: bash tests/test-config-seams.sh
Exit: 1
Output:
FAIL skill filled and resolving under a KIT_SKILL_DIRS dir inside HOME
FAIL dir filled and existing -> filled
FAIL --check exits 0 when every live-registry row is default/absent, none unresolved
FAIL the same dir INSIDE HOME set as knowledge.root -> filled
FAIL a plain regular file under HOME -> filled
FAIL the raw relative value is reported verbatim, not a cwd-resolved path
=== 50/56 passed ===
Verdict: RED as expected; restored, 56/56 passed
```

```
Control 2: in install.sh, drop --exclude='lib/*/rust/target' (and separately --exclude='.venv')
Command: bash tests/test-install-lib-copy.sh
Exit: 1
Output:
FAIL rust/target cargo output is not copied
SOME TESTS FAILED
(the .venv variant printed: FAIL a .venv is not copied)
Verdict: RED as expected; restored, 5/5 ok
```

## Not proven

- The before column is a loaded-host p95, the after column an idle-host run, so the ratio overstates the gain from these changes alone. No controlled A/B was run.
- The PROSE_RAG_BIN cases in test-config-seams still run a live report. After the `_find_row` fix the whole suite takes 6s, so a one-row fixture registry was not worth a changed assertion path.
- GNU tar was not run (bsdtar only); the flags used (`--exclude`, `-cf -`, `-xpf - -C`) are the common subset of bsdtar and GNU tar.
