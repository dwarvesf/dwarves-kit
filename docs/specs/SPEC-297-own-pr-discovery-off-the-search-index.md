# SPEC-297: wrap reads its own open PRs off the repository, not the search index

**Status:** BUILT (the helper and its fixtures land in this PR; this spec records the contract)
Lane: full
**Board:** ID-922. **Proof:** `docs/verification/wrap-merge-own-pr-discovery.md`.

## Problem

`bin/wrap merge --apply <repo>` printed `nothing eligible to merge` for an own, green,
non-draft PR opened minutes earlier, three times on 2026-09-17 (ops-toolkit #2872, dotfiles
#466, one on console-labs). `cmd_merge` asked `gh pr list --repo <url> --author "@me"`. An
author filter sends gh to the GraphQL `search()` endpoint (`query PullRequestSearch`), which
reads the eventually-consistent search index; without the filter gh reads
`repository.pullRequests` (`query PullRequestList`), which holds the PR the moment it exists.
The reported path difference (repo root versus secondary worktree) never reached the query:
`--repo` is explicit and both paths resolve the same origin URL. The worktree call succeeded
because it ran later.

## Solution

One helper, `_open_own_prs <repo-url>`, is the single open-PR reader for the subsystem.

- It calls `gh pr list --repo <url> --state open --limit 100 --json number,title,headRefName,author`.
- It filters `.author.login` against `gh api user --jq .login`, case-insensitively.
- It exits 1 when the login or the list does not resolve, and prints nothing.
- It names a full page on stderr, because that is the one case where an own PR can sit past the cap.
- `cmd_merge` and `_scan_repo` both route through it. `cmd_merge` reports the failed query and
  returns 1; `_scan_repo` prints its existing `(gh query failed)` line.

Alternatives considered:

- **Retry the author query when it comes back empty.** Rejected: the reported runs listed
  other PRs, so the answer was non-empty and a retry-on-empty never fires.
- **Keep the author filter and add a `--pr N` escape.** Rejected as the fix: it leaves every
  unattended call reading the lagging index. `--pr N` stays its own item (ID-908).
- **Report an empty set when the identity read fails.** Rejected: that is the same silent
  miss one hop earlier, and it reads as a clean board.

## Verification

`bash tests/test-wrap.sh`: a PR present in the repository list and absent from the
author-filtered answer is eligible; the recorded gh calls carry no `--author`; a PR authored
by someone else is never eligible; a failed identity read exits non-zero, names the query,
and merges nothing. Negative control through `lib/gate/negctl.sh`: restoring the `--author`
filter turns the suite red and the restore returns it green.

## Out of scope

Pagination past 100 open PRs (named on stderr instead), `--pr N` (ID-908), and every other
gate in `_pr_gate`, which is untouched.
