# wrap: which verb for which situation

`wrap` is the landing subsystem. The entrypoint is `bin/wrap` in this repo, or `~/.claude/dwarves-kit/bin/wrap` once installed. It forwards to `lib/wrap/wrap.sh`, which owns the verb grammar. The `commands/wrap.md` file is the session-close playbook that calls these verbs; this page is the lookup.

Each row below was read from the verb's source in `lib/wrap/`. A verb with no row has no situation worth a rule here.

## Rules that apply to every verb

- Only `wrap --help` (or `help`, or no verb) prints usage. `wrap <verb> --help` exits 64 with `unknown flag '--help'`. Read the verb's usage line from `wrap.sh` or from the error a bad call prints.
- A `<repo>` or `<worktree>` argument is a filesystem path, resolved from the current directory. A bare repo name that is not a directory there fails with `is not a git repo`. Pass an absolute path.
- A bad call exits 64. A write that fails inside a verb exits non-zero and names the step.
- A verb never switches a branch in the shared checkout and never force-pushes.

## Verb by situation

| Situation | Run | What the code does |
|---|---|---|
| Start work on a new branch, main checkout is dirty or shared | `wrap start <repo> <branch>` | Fetches the default branch, creates `<repo>/.claude/worktrees/<slug>` on the new branch, prints only the worktree path on stdout. `<slug>` is the branch name after its last `/`. |
| Same, and move my uncommitted edits across | `wrap start <repo> <branch> --carry [<path>...]` | Stashes the main checkout's edits under a unique name, applies them in the new worktree, drops that stash on a clean apply. A conflict keeps the stash and exits 2. |
| The branch already exists, locally or on origin | none | `wrap start` refuses with `branch <name> already exists`. No verb adds a worktree for an existing branch. |
| The worktree path already exists | none | `wrap start` refuses with `<path> already exists`. |
| The branch name is the default branch, `main`, or `master` | none | `wrap start` refuses. `land` and `rebase` refuse the same names. |
| An open PR of mine conflicts with the default branch | `wrap merge --apply --pr <N> <repo>` | Tries one re-merge of the default branch into the PR head and pushes it. It uses a scratch detached worktree when no checkout holds the branch. If the head already holds the base, it opens a `<branch>-squash` replacement PR. Without `--apply` it only prints a note. |
| My branch sits in a worktree and is behind the default branch | `wrap rebase <worktree>` | Rebases onto `origin/<default>`. It resolves only a regenerated file or a CHANGELOG both sides added to, and aborts on any other conflict. It never pushes; the history changed, so the push needs `--force-with-lease`. |
| The worktree branch is committed and I want it merged | `wrap land <worktree>` | Pushes the named branch, opens or adopts the PR, squash-merges, verifies the tree, fast-forwards the main checkout, removes the worktree, deletes the branch. There is no dry run. |
| The branch already has an open PR | `wrap land <worktree>` | Adopts that PR and keeps its title and body. It refuses with 2 or more open PRs, a PR by another author, or a base other than the default. |
| Land a branch but do not merge | none | `land` always merges. Push the branch and open the PR with `git` and `gh` instead. |
| See what `merge` would do | `wrap merge <repo>` | Dry run. Prints `eligible #N` or `SKIP #N <reason>` for each of my open PRs, then `dry run; pass --apply to merge one PR.` |
| Merge one green PR of mine | `wrap merge --apply [--pr <N>] <repo>` | Squash-merges exactly one PR per call, pinned to the head it gated. It takes exactly one `<repo>` path. Only PRs I authored count; `--pr` naming another author's PR is refused. |
| The PR is a draft | `wrap merge --apply --pr <N> <repo>` | Runs `gh pr ready` first. Without `--pr`, a draft is skipped. |
| Report repo state, change nothing | `wrap scan <repo> [<repo>...]` | Report only. Prints ahead and behind counts, dirty files, worktrees, local branches, and my open PRs. |
| Tidy a repo, preview first | `wrap apply <repo>` | Dry run by default. Prints `WOULD ...` lines. Add `--apply` to write. |
| Remove merged worktrees, all sessions | `wrap apply --apply --worktrees <repo>` | Removes every clean, non-detached worktree whose branch is proven merged, then deletes the branch. Other sessions' worktrees qualify too. |
| Remove only my own worktrees | `wrap apply --apply --own <worktree> <repo>` | `--own` is repeatable and implies the worktree opt-in, so `--worktrees` is not needed. Unnamed worktrees are skipped. The all-branches sweep and `--archive-unmerged` are skipped. |
| Tidy without pulling the shared checkout | `wrap apply --apply --no-pull --own <worktree> <repo>` | `--no-pull` without `--own` skips both the worktree sweep and the branch sweep. |
| Pull the default branch and nothing else | `wrap apply --apply --pull-only <repo>` | Cannot combine with `--worktrees`, `--own`, `--archive-unmerged`, `--tips-file`, or `--no-pull`. |
| Adopt a repo into the kit contract | `wrap adopt [--apply] <repo> [<repo>...]` | Dry run by default. `--body-file` takes exactly one repo. |
| Write the activity line | `wrap log "<slug>: <one sentence>"` | Writes immediately and warns over 300 characters. |
| Wait for a push-deploy check | `wrap deploy-wait <owner>/<name> <sha> [--check S]... [--timeout N]` | Polls the commit's check runs. Exit 0 all success, 1 a run failed, 124 timeout. |

## Which verbs preview first

| Dry run by default | Writes at once |
|---|---|
| `apply`, `merge`, `adopt` (add `--apply`) | `start`, `land`, `rebase`, `log`, `stage` |

`scan` writes nothing at any setting.

## Source files

| Verb | File |
|---|---|
| `scan` | `lib/wrap/wrap-scan.sh` |
| `apply` | `lib/wrap/wrap-apply.sh` |
| `merge` | `lib/wrap/wrap-merge.sh` |
| `land` | `lib/wrap/wrap-land.sh` |
| `start` | `lib/wrap/wrap-start.sh` |
| `rebase` | `lib/wrap/wrap-rebase.sh` |
| `adopt` | `lib/wrap/wrap-adopt.sh` |
| `log`, `stage`, `knowledge-root` | `lib/wrap/wrap-log.sh` |
| `deploy-wait`, `default-branch`, `follow-mode` | `lib/wrap/wrap-deploy.sh` |
