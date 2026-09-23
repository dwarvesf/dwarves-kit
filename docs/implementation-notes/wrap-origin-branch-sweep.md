# Implementation notes: wrap origin branch sweep (SPEC-307)

Delta from the spec only.

| Decision | Choice | Why |
|---|---|---|
| Scope | Every `apply` call, `--worktrees` or not; `--own` skips it | Matches `_apply_branches`: local branch deletes already run on every `apply`, and `--worktrees` gates worktree removal only. `--own` narrows to the named worktrees, so another session's merged origin branch is out of scope. |
| GitHub test | Raw `git config remote.origin.url` matches `github.com[:/]` | `git remote get-url` expands `insteadOf`; the raw key does not, which lets the tests point a github.com URL at a local bare repo. |
| Tip source | `git ls-remote --heads origin` | The first cut read `refs/remotes/origin/`. The real dry run on foundation-workers found 2 instead of 173, because that checkout fetches `main` only. |
| Delete count | Counted from a second `ls-remote` after the pushes | A multi-ref `git push --delete` is not atomic; one protected branch fails the push while the rest land. |
| Race guard | `--force-with-lease=refs/heads/<b>:<tip>` per name, `:refs/heads/<b>` refspec | Added after the security review: a bare delete is unconditional, the lease makes it conditional on the tip that proved the merge. The fully qualified refspec keeps a same-named tag or a leading dash from failing a whole chunk. |
| PR list cap | 1000 merged, 1000 open | A merged PR past the cap leaves its branch kept, which fails safe. A full open page skips the whole sweep, because an unread open PR could need a base branch. |
| Long-lived branches | Deleted when merged whole, like GitHub's `delete_branch_on_merge` | The security review flagged `develop -> main`. Requiring `base == default` would not stop that case and would keep stacked heads GitHub itself deletes. A protected branch refuses and reports `FAILED`. |
