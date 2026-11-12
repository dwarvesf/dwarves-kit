# Verification -- project-merge-command

`[merge] command` routes every merge the kit makes (`wrap land`, `wrap merge`, `mega-merge`, `stack-merge`) through the project's own script, and a refusal stops the flow with no fallback (spec: `docs/specs/SPEC-420-project-merge-command.md`).

## Green run

The new suite and the extended mega-merge suite, on the repo's harness (real git, bare remotes, gh stub, a real merge script in a fixture repo):

```
Command: bash tests/test-merge-command.sh
Exit: 0
Output:
  test-merge-command: all 93 passed
Verdict: PASS
```

```
Command: bash tests/test-mega-merge.sh
Exit: 0
Output:
  === 74/74 passed, 0 failed ===
Verdict: PASS
```

What the 93 cover, by section: the resolver (committed default-branch value wins; a working-tree edit, a PR-branch edit, a tag or branch named `origin/main`, and HEAD never count; an unreadable key, a missing repo dir and five non-simple values exit 2); `kit_merge_exec` (the committed script runs, not an edited working-tree copy; a hostile `GIT_DIR` does not reach it; the temp checkout is removed); `wrap merge --apply` with the key set, refused, unset, and set only in the working tree; the slug path (set refuses, 404 with a readable listing is plain, a 404 on the listing too is a refusal, any other failure refuses); `wrap land` with the key set, refused, refused on a CONFLICTING PR (no merge-in cycle starts), and unset; `stack-merge` set, dry-run, refused (chain stops, child PR put back on its parent), unset.

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
- The clean-checkout rule means a merge script that reads untracked local files will not find them there.
- `lib/wrap/report-lint.sh` still treats the plain merge as the self-runnable one; a project command is not in its pattern.
