# SPEC-299: wrap land adopts the operator's own open PR for its branch

**Status:** VALIDATED (the change lands in the same PR)
Lane: full
**Proof:** `tests/test-wrap.sh`, the SPEC-299 block.

## Problem

`wrap.sh land <worktree>` always runs `gh pr create`. When the operator already opened a PR for that branch, which a full-lane run does before its evidence and review steps, gh refuses with "a pull request for branch ... already exists". `land` then prints `PR REFUSED` and exits 2. The operator finishes the merge, tree check, pull, and tidy by hand, the exact loop `land` exists to own. This happened on dwarves-kit #704.

## Contract

- After the push and before creating a PR, `land` lists open PRs for the branch: `gh pr list --repo <url> --head <branch> --state open --json number,baseRefName,author,isDraft,isCrossRepository`. Entries with `isCrossRepository` true are dropped before counting, so a fork's same-named branch never counts.
- The list call fails: stderr `     PR REFUSED: open-PR lookup for <branch> failed`, exit 2.
- No open PR: `land` creates one exactly as today.
- Two or more: stderr `     PR REFUSED: <k> open PRs for <branch>`, exit 2.
- Exactly one, and its base is not the default branch: stderr `     PR REFUSED: open PR #<n> targets <base>, not <default>`, exit 2.
- Exactly one, and the operator login (the same `gh api user --jq .login` read `_open_own_prs` uses) does not resolve: stderr `     PR REFUSED: open PR #<n>: operator login did not resolve`, exit 2.
- Exactly one, authored by someone else (case-insensitive compare, as `_open_own_prs` does): stderr `     PR REFUSED: open PR #<n> is authored by <login>`, exit 2.
- Otherwise `land` adopts it: stdout `     adopted PR #<n>` in place of `opened PR #<n>`. A draft is first marked ready with `gh pr ready <n> --repo <url>`, as `merge --pr` already does; a failed ready is stderr `     PR REFUSED: open PR #<n> is a draft and gh pr ready failed`, exit 2. When `--title` or `--body-file` was passed, stderr notes `     note: adopted PR #<n> keeps its own title and body`. Every later step (merge with `--match-head-commit`, tree verify, pull, tidy) runs unchanged.
- No refusal reaches a merge call.

## Design record

Adoption reuses the existing merge guard. `gh pr merge --match-head-commit <tip>` already refuses a PR whose head moved, so an adopted PR can only merge the tip `land` just pushed. Refusing a foreign or off-base PR keeps the rule "never merge a PR the operator did not open" that `commands/wrap.md` states for step 3. The query names `--repo`, the same way `scan` does, so it reads the repository and not the lagging search index.

## Test plan

| Case | Open PRs for the head | Expected |
|---|---|---|
| none | `[]` | `opened PR #42`, create called (existing happy path) |
| own, default base | one, base main, author me | `adopted PR #7`, no create call, merge called with #7, exit 0 |
| own, uppercase login | author `Me` | adopted |
| own draft | isDraft true | `pr ready 7` called, then adopted and merged |
| draft, ready fails | isDraft true, ready rc 1 | refused, exit 2, no merge |
| off-base | one, base feat/other | `targets feat/other`, exit 2, no merge |
| foreign author | one, author other | `authored by other`, exit 2, no merge |
| two open | two entries | `2 open PRs`, exit 2, no merge |
| fork entry only | one, isCrossRepository true | treated as none: create called |
| identity read fails | one own PR, `gh api` fails | `operator login did not resolve`, exit 2 |
| list fails | `pr list` exits non-zero | `open-PR lookup ... failed`, exit 2 |
| flags ignored | adopted with `--title` | stderr note present |

The stub gains an open-by-head answer: `pr list --head <b> --state open` reads `GH_STUB_OPEN_HEAD_<key>` (default `[]`) and `GH_STUB_LIST_RC`, so the merged-by-head answer the other suites use stays untouched.

## Verification

`bash tests/test-wrap.sh` runs the SPEC-299 block with the rest of the suite. `bash tests/run-all.sh --changed` stays green.

## Out of scope

No change to `merge`, `scan`, or `apply`. No `gh pr edit` of an adopted PR's title or body.
