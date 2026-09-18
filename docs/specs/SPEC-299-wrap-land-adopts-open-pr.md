# SPEC-299: wrap land adopts the operator's own open PR for its branch

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
**Proof:** `tests/test-wrap.sh`, the SPEC-299 block.

## Problem

`wrap.sh land <worktree>` always runs `gh pr create`. When the operator already opened a PR for that branch, which a full-lane run does before its evidence and review steps, gh refuses with "a pull request for branch ... already exists". `land` then prints `PR REFUSED` and exits 2. The operator finishes the merge, tree check, pull, and tidy by hand, the exact loop `land` exists to own. This happened on dwarves-kit #704.

## Contract

- Before creating a PR, `land` lists open PRs for the branch: `gh pr list --repo <url> --head <branch> --state open --json number,baseRefName,author`.
- Exactly one open PR, authored by the operator (`gh api user --jq .login`), whose base is the default branch: `land` adopts it and prints `     adopted PR #<n>` in place of `opened PR #<n>`. Every later step (merge with `--match-head-commit`, tree verify, pull, tidy) runs unchanged.
- One open PR whose base is not the default branch: `land` prints `     PR REFUSED: open PR #<n> targets <base>, not <default>` and exits 2 before any merge.
- One open PR authored by someone else: `land` prints `     PR REFUSED: open PR #<n> is authored by <login>` and exits 2.
- Two or more open PRs for the branch: `land` prints `     PR REFUSED: <k> open PRs for <branch>` and exits 2.
- No open PR: `land` creates one exactly as today.
- An identity read that fails counts as "not the operator", so an adoption never happens on an unknown author.

## Design record

Adoption reuses the existing merge guard. `gh pr merge --match-head-commit <tip>` already refuses a PR whose head moved, so an adopted PR can only merge the tip `land` just pushed. Refusing a foreign or off-base PR keeps the rule "never merge a PR the operator did not open" that `commands/wrap.md` states for step 3. The query names `--repo`, the same way `scan` does, so it reads the repository and not the lagging search index.

## Test plan

| Case | Open PRs for the head | Expected |
|---|---|---|
| none | `[]` | `opened PR #42`, create called (existing happy path) |
| own, default base | one, base main, author me | `adopted PR #7`, no create call, merge called with #7, exit 0 |
| off-base | one, base feat/other | `PR REFUSED ... targets feat/other`, exit 2, no merge |
| foreign author | one, author other | `PR REFUSED ... authored by other`, exit 2, no merge |
| two open | two entries | `PR REFUSED: 2 open PRs`, exit 2, no merge |
| identity read fails | one own PR, `gh api` fails | refused as authored by someone else, exit 2 |

## Verification

`bash tests/test-wrap.sh` runs the SPEC-299 block with the rest of the suite. `bash tests/run-all.sh --changed` stays green.

## Out of scope

No change to `merge`, `scan`, or `apply`. A draft PR is adopted like any other and `gh pr merge` answers for it as it does today.
