# Verification -- wrap-merge-own-pr-discovery

`wrap merge` and `wrap scan` read the repository's own open-PR list and filter the author
locally, so a PR opened seconds earlier is listed. The previous `gh pr list --author "@me"`
sent gh to the GraphQL search index, which is eventually consistent and dropped a fresh own
PR from the eligibility loop.

## Root cause

| Query | gh GraphQL operation | Source |
|---|---|---|
| `gh pr list --repo R --author "@me" --state open` | `PullRequestSearch` / `search(` | the search index, eventually consistent |
| `gh pr list --repo R --state open` | `PullRequestList` / `pullRequests(` | the repository itself, current |

```
Command: GH_DEBUG=api gh pr list --repo dwarvesf/dwarves-kit --author "@me" --state open --json number
Exit: 0
Verdict: the request body carries `query PullRequestSearch` and `search(`. The same command
without --author carries `query PullRequestList` and `pullRequests(`.
```

The path in the report (repo root vs secondary worktree) never reached the query: `cmd_merge`
passes `--repo <origin url>` and both paths resolve the same URL. The worktree call succeeded
because it ran minutes later, once the index had caught up.

## Green run
```
Command: bash tests/test-wrap.sh
Exit: 0
Verdict: all 578 passed, including the three new cases (a PR absent from the author-filtered
answer is still eligible, a PR authored by someone else is never listed, and a failed
identity read is reported instead of reading as an empty board).
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Verdict: all 29 suites passed, 0 skipped for missing tooling.
```

Before the fix the same suite reported `test-wrap: 570 passed, 4 FAILED of 574`.

## Negative control
```
Command: bash lib/gate/negctl.sh <worktree> "bash tests/test-wrap.sh" "<put --author \"@me\" back into _open_own_prs>"
Exit: 0
Verdict: PASS. Green before the mutation, exit 1 under it, green again after
`git checkout HEAD -- lib/wrap/wrap.sh`, with the tree matching the snapshot.
```

## Not proven
- The index lag itself is GitHub-side and not reproducible on demand; the test models it
  through the stub, and the endpoint split above is the evidence that the old query depended
  on the lagging index.
- A repo with more than 100 open PRs reads only the first page. The run says so on stderr
  rather than paginating.
