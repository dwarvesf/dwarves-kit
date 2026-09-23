# Implementation notes: wrap origin branch sweep (SPEC-307)

Delta from the spec only.

| Decision | Choice | Why |
|---|---|---|
| Scope | Every `apply` call, `--worktrees` or not; `--own` skips it | Matches `_apply_branches`: local branch deletes already run on every `apply`, and `--worktrees` gates worktree removal only. `--own` narrows to the named worktrees, so another session's merged origin branch is out of scope. |
| GitHub test | Raw `git config remote.origin.url` matches `github.com[:/]` | `git remote get-url` expands `insteadOf`; the raw key does not, which lets the tests point a github.com URL at a local bare repo. |
| Tip source | `git ls-remote --heads origin` | The first cut read `refs/remotes/origin/`. The real dry run on foundation-workers found 2 instead of 173, because that checkout fetches `main` only. |
| Delete count | Counted from a second `ls-remote` after the pushes | A multi-ref `git push --delete` is not atomic; one protected branch fails the push while the rest land. |
| Race guard | None beyond the `ls-remote` read right before the push | `--force-with-lease` would guard the delete, but the file promises never to force a push, and the read-to-push window is seconds. |
| PR list cap | 1000 merged, 1000 open | A merged PR past the cap leaves its branch kept, which fails safe. An open PR past the cap is unseen, so a repo with more than 1000 open PRs could lose a base branch; no operator repo is near that. |
