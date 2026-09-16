# Proof of done: `bin/wrap land`, the hand-made-worktree landing loop

`land` takes one committed branch in a hand-made worktree from commit to landed. It pushes the named branch, opens the PR with `--head` and never `--base`, squash-merges as its own call, verifies the default branch holds the PR head through `merge`'s own `_tree_verify`, fast-forwards the main checkout with `--ff-only`, removes the worktree, and deletes the local branch. Every refusal (dirty worktree, HEAD on the default or a protected branch name, `gh` absent or unauthenticated, no commits ahead of the default branch) names its reason and exits non-zero before any write. A refused pull prints `PULL BLOCKED`, leaves the checkout untouched, and still tidies. The verb logs no proof-ledger override: a ship-gate refusal on the push returns the gate's own exit code.

## Acceptance criteria

| AC | Claim | Proof |
|---|---|---|
| AC1 | the named branch reaches the remote before the PR opens | `test-wrap.sh` land happy path: bare remote `feat/land` equals the worktree tip |
| AC2 | the PR opens with `--head` and no `--base` | `chk_has "--head feat/land"` plus `chk_no "--base"` over the gh call log |
| AC3 | the squash merge is its own call, pinned to the pushed head | `grep -c '^pr merge 42 '` equals 1; `--squash --match-head-commit <tip>` present |
| AC4 | the default branch is verified to hold the PR head | output line `merged #42 (1a2b3c4d5e6f): tree verified` |
| AC5 | the main checkout fast-forwards, the worktree and branch go | main checkout HEAD equals the tip; path gone, dropped from `worktree list`, `rev-parse feat/land` fails |
| AC6 | a dirty worktree refuses before any write | exit 1, no gh call recorded, nothing pushed, worktree still present |
| AC7 | a HEAD on the default branch refuses | exit 1, message names `main`, no gh call recorded |
| AC8 | a blocked pull reports and still tidies | exit 2, `PULL BLOCKED` line, main checkout HEAD and the sibling's dirty line unchanged, worktree and branch still removed |
| AC9 | no regression to the rest of wrap | full `test-wrap.sh` green, changed-suite `run-all.sh` green |

## Green run

```
Command: bash tests/test-wrap.sh
Exit: 0
test-wrap: all 565 passed
Verdict: PASS
```

```
Command: bash tests/run-all.sh
Exit: 0
run-all: all 14 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

NEGATIVE CONTROL: `git checkout origin/master -- lib/wrap/wrap.sh` puts back the wrap.sh that has no `land` verb, keeping the new test cases. Every land case goes red and nothing else moves: `land` exits 64 on an unknown verb, so the whole section fails at once.

```
Command: bash tests/test-wrap.sh   (origin/master lib/wrap/wrap.sh)
Exit: 1
FAIL land exits 0 on the happy path
FAIL land reports the push with the tip
FAIL land pushed the named branch to the remote
FAIL land opened the PR with --head
FAIL the create call names the branch as head
FAIL land reports the PR number
FAIL land ran the squash merge as its own call
FAIL the merge call is a squash
FAIL the merge call pins the pushed head
FAIL land verifies the default branch holds the PR head
FAIL land fast-forwarded the main checkout onto the landed tree
FAIL land reports the pull
FAIL land removed the worktree
FAIL land dropped the worktree from the list
FAIL land deleted the local branch
FAIL land reports the delete
FAIL land refuses a dirty worktree with exit 1
FAIL the refusal names the dirt
FAIL land refuses a worktree on the default branch with exit 1
FAIL the refusal names the branch
FAIL a blocked pull exits 2
FAIL the blocked pull says PULL BLOCKED
FAIL the blocked pull says nothing was stashed or reset
FAIL the merge still landed
FAIL the worktree was still removed
FAIL the removal is still reported
FAIL the branch was still deleted
FAIL wrap --help names land
test-wrap: 537 passed, 28 FAILED of 565
```

`git checkout HEAD -- lib/wrap/wrap.sh` returns the suite to `test-wrap: all 565 passed`, exit 0.

## Not proven

- No live GitHub run: `gh` is stubbed, so the real `gh pr create` URL shape, the real `--match-head-commit` refusal, and a real ship-gate push refusal are unexercised. The gate path is asserted only by construction (the push's exit code is returned unchanged).
- The `gh` absent / unauthenticated refusal and the no-commits-ahead refusal have code and a message but no test case.
- Single-repo fixture on `main`; a non-`main` default branch is covered for the other verbs, not for `land`.

## Reproduce

```
bash tests/test-wrap.sh
bash tests/run-all.sh
```
