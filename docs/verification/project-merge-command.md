# Verification -- project-merge-command

`[merge] command` routes every merge the kit makes (`wrap land`, `wrap merge`, `mega-merge`, `stack-merge`) through the project's own script, and a refusal stops the flow with no fallback (spec: `docs/specs/SPEC-420-project-merge-command.md`).

## Green run

The new suite and the extended mega-merge suite, on the repo's harness (real git, bare remotes, gh stub, a real merge script in a fixture repo):

```
Command: bash tests/test-merge-command.sh
Exit: 0
Output:
  test-merge-command: all 136 passed
Verdict: PASS
```

```
Command: bash tests/test-mega-merge.sh
Exit: 0
Output:
  === 80/80 passed, 0 failed ===
Verdict: PASS
```

What the first 93 cover, by section: the resolver (committed default-branch value wins; a working-tree edit, a PR-branch edit, a tag or branch named `origin/main`, and HEAD never count; an unreadable key, a missing repo dir and five non-simple values exit 2); `kit_merge_exec` (the committed script runs, not an edited working-tree copy; a hostile `GIT_DIR` does not reach it; the temp checkout is removed); `wrap merge --apply` with the key set, refused, unset, and set only in the working tree; the slug path (set refuses, 404 with a readable listing is plain, a 404 on the listing too is a refusal, any other failure refuses); `wrap land` with the key set, refused, refused on a CONFLICTING PR (no merge-in cycle starts), and unset; `stack-merge` set, dry-run, refused (chain stops, child PR put back on its parent), unset.

The change touches the wrap family, so the whole diff-selected set, 87 suites, ran:

```
Command: RUN_ALL_TIMEOUT_SECS=1200 bash tests/run-all.sh --changed --time
Exit: 0
Output:
  run-all: --changed against 2e4b4e75: 20 changed files -> 87 suites (82 named, the rest always-on)
  test-mega-merge                                ok (16s)
  test-merge-command                             ok (32s)
  test-meta-docs-registry                        ok (14s)
  test-wrap-adopt                                ok (140s)
  test-wrap-land                                 ok (257s)
  test-wrap-merge                                ok (224s)
  run-all: all 87 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Independent security review round

An independent review returned SAFE WITH FIXES. Each fix has a test that was red before it (30 FAILs in `test-merge-command`, 5 in `test-mega-merge` with the fixed `lib/` stashed, tests kept):

| Finding | Fix | Test |
|---|---|---|
| unparseable forms read as unset | `_kit_mc_shape` refuses dotted, inline, `[[merge]]`, other quoting, repeated key, sub-table, `#` or backslash in the value (project, operator, slug) | "unreadable form (...)" x10, operator x2, slug dotted |
| head variable advisory | `kit_merge_verify` compares the merged head with the gated head (mega-merge) | "merged a moved head" x3 |
| live-tree fallback | `kit_merge_exec` returns 2 with no default-branch commit | "exec, default branch unresolvable" x2 |
| `#` silently cut | refused, same shape check | "hash inside the value", operator `#` |
| stale `origin/HEAD` | mega-merge (execute) and stack-merge ask `gh repo view` | "stale origin/HEAD" x2 |
| cleanup and gaps | subshell trap removes the checkout; failing `worktree add`, exit 3 in land and merge, unreadable key in land, merge and stack-merge | "exec, worktree add fails" x4, "interrupt" x3, exit-3 x6, unreadable x11 |

```
Command: bash tests/test-merge-command.sh
Exit: 0
Output:
  test-merge-command: all 136 passed
Verdict: PASS
```

```
Command: RUN_ALL_TIMEOUT_SECS=1200 bash tests/run-all.sh --changed --time ; bash tests/test-mega-reconcile.sh ; bash tests/run-all.sh --failed
Exit: 0 after one fix
Output:
  run-all: 87 suites, 4 at a time, 1 serial
  test-merge-command                             ok (42s)
  test-mega-merge                                ok (19s)
  test-wrap-land                                 ok (200s)
  test-wrap-merge                                ok (178s)
  test-mega-reconcile                            FAIL (rc=1) (6s)   <- the default-branch lookup called gh in a dry run
  (fixed: only a real --execute asks GitHub)
  === 35/35 passed, 0 failed ===   (test-mega-reconcile)
  run-all: all 9 suites passed, 0 skipped for missing tooling   (--failed)
Verdict: PASS
```

Negative control for this round, committed first: the shape check forced to pass, the head compare skipped and the unresolvable-ref guard skipped, then restored with `git checkout --`:

```
Command: bash tests/test-merge-command.sh ; bash tests/test-mega-merge.sh   (three guards disabled)
Exit: 1
Output:
  test-merge-command: 113 passed, 23 FAILED of 136
  === 77/80 passed, 3 failed ===   (the 3 are the moved-head cases)
Verdict: RED as intended
```

## Negative control

Committed first, then each router forced to read the key as unset (`mrc=1` in `_merge_pr`, `prc=1` in `mega-merge.sh` and `stack-merge.sh`), the suites re-run, and the files restored with `git checkout -- <file>`:

```
Command: bash tests/test-merge-command.sh   (router forced to "key unset")
Exit: 1
Output:
  FAIL key set: the command is announced with the PR number
  FAIL key set: gh pr merge is never called
  FAIL refusal: merge --apply exits 2
  FAIL refusal: gh pr merge is never called (no fallback)
  FAIL slug, key set: merge refused (exit 2)
  FAIL land, key set: gh pr merge is never called
  FAIL land, refusal: exits 2
  FAIL land, refusal on a CONFLICTING PR: exits 2
  FAIL stack-merge, key set: merges through the project command
  FAIL stack-merge, refusal: exits non-zero
  FAIL stack-merge, refusal with a child PR: the child is put back on the parent branch
  (the capture was cut at 40 FAIL lines)
Verdict: RED as intended
```

```
Command: bash tests/test-mega-merge.sh   (router forced to "key unset")
Exit: 1
Output:
  FAIL project-merge: the DRY-RUN line prints the project command
  FAIL project-merge: gh pr merge is never called when the key is set
  FAIL project-merge [refusal]: --execute returns the command's exit code (7)
  FAIL project-merge [refusal]: no fallback to the plain gh merge
  FAIL project-merge [unreadable key]: --execute fails closed (nonzero)
  === 61/74 passed, 13 failed ===
Verdict: RED as intended
```

Restored: `git status --short` printed nothing after the `git checkout --`, and the suites above are green on the restored files.

## Not proven

- No real GitHub: the suites use a gh stub and local bare remotes. A real `consolelabs/playdate-agent` merge script was not run (the consumer repo is out of bounds for this change).
- A failed fetch of the default branch is not a refusal: the ref may be stale (documented). The command has no timeout.
- stack-merge has no gated head, so it cannot compare a merged head; `wrap land` and `wrap merge` rely on their existing tree check against the gated head.
- The clean-checkout rule means a merge script that reads untracked local files will not find them there.
- `lib/wrap/report-lint.sh` still treats the plain merge as the self-runnable one; a project command is not in its pattern.
