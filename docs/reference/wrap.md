# wrap: which verb for which situation

`wrap` is the landing subsystem. The entrypoint is `bin/wrap` in this repo, or `~/.claude/dwarves-kit/bin/wrap` once installed. It forwards to `lib/wrap/wrap.sh`, which owns the verb grammar. The `commands/wrap.md` file is the session-close playbook that calls these verbs; this page is the lookup.

Each row below was read from the verb's source in `lib/wrap/`.

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
| A stacked child PR conflicts after its parent squash-merged and was retargeted to the default branch | `wrap merge --apply --pr <N> --rebase-stacked [--verify <cmd>] <repo>` | Opt-in, the one history rewrite `merge` owns. Finds the merged PR whose last head sits under the child, runs `git rebase --onto origin/<default> <that head>` in the checkout that holds the branch (clean, at the PR head) or a scratch worktree, runs `--verify`, then pushes the PR's own branch with `--force-with-lease` at the head the gates read. It refuses by name and touches nothing on a rebase conflict (the conflicting files are printed, the rebase is aborted), a fork PR, an armed auto-merge, open dependents on the branch, a moved head, or a default-named branch. Then it gates and merges as usual. |
| A PR's new head reports no checks on a repo with a `ci` label | `wrap merge --apply --pr <N> <repo>` | Labels the PR with the same `_ci_label_sync` and `_ci_checks_wait` that `land` uses (remove and add again when the label predates the head), waits for the runs, re-reads, and gates. A repo without the exact `ci` label is untouched. A label that will not set exits 2 and merges nothing. Without `--pr` the label step stays behind `--with-ci`. |
| My branch sits in a worktree and is behind the default branch | `wrap rebase <worktree>` | Rebases onto `origin/<default>`. It resolves only a regenerated file or a CHANGELOG both sides added to, and aborts on any other conflict. It never pushes; the history changed, so the push needs `--force-with-lease`. |
| The worktree branch is committed and I want it merged | `wrap land <worktree>` | Pushes the named branch, opens or adopts the PR, squash-merges, verifies the tree, fast-forwards the main checkout, removes the worktree, deletes the branch. There is no dry run. Every run ends on one `LAND:` line on stdout (read it with `\| tail -1`): `merged #<n> (<sha7>) pull=<ok\|blocked\|skipped> worktree=<removed\|kept>`, `already landed (<proof>) pull=.. worktree=..`, `draft #<n> opened`, or `refused (<step>, exit <rc>)`. The refusal text stays on stderr and the exit codes are unchanged. |
| The branch already has an open PR | `wrap land <worktree>` | Adopts that PR and keeps its title and body. It refuses with 2 or more open PRs, a PR by another author, or a base other than the default. |
| Land a branch while another session is live in the main checkout | `wrap land <worktree> --no-pull` | Same promise as `merge --no-pull` and `apply --no-pull`: never writes the main checkout. It still merges, verifies the tree, deletes the origin branch, and removes the worktree and local branch. It prints `SKIP pull: --no-pull` in place of the fast-forward. |
| Land a branch but do not merge | `wrap land <worktree> --draft [--title T] [--body-file F]` | Pushes the named branch, opens or adopts a draft PR, prints the URL and the proof block, and stops. It never marks the PR ready, merges, tidies, pulls or writes a Ship record, and the worktree stays. It refuses an already-landed branch, an open non-draft PR, a new PR with no proof and no `--body-file`, and a ship-gate block. It exits 64 with `--with-ci`, `--verify` or `--no-pull`. |
| See what `merge` would do | `wrap merge <repo>` | Dry run. Prints `eligible #N` or `SKIP #N <reason>` for each of my open PRs, then `dry run; pass --apply to merge one PR.` |
| Merge one green PR of mine | `wrap merge --apply [--pr <N>] <repo>` | Squash-merges exactly one PR per call, pinned to the head it gated. It takes exactly one `<repo>` path. Only PRs I authored count; `--pr` naming another author's PR is refused. |
| The PR is a draft | `wrap merge --apply --pr <N> <repo>` | Runs `gh pr ready` first. Without `--pr`, a draft is skipped. |
| Report repo state, change nothing | `wrap scan <repo> [<repo>...]` | Report only. Prints ahead and behind counts, dirty files, worktrees, local branches, and my open PRs. |
| Tidy a repo, preview first | `wrap apply <repo>` | Dry run by default. Prints `WOULD ...` lines. Add `--apply` to write. |
| Remove merged worktrees, all sessions | `wrap apply --apply --worktrees <repo>` | Removes every clean, non-detached worktree whose branch is proven merged, then deletes the branch. Other sessions' worktrees qualify too. |
| Remove only my own worktrees | `wrap apply --apply --own <worktree> <repo>` | `--own` is repeatable and implies the worktree opt-in, so `--worktrees` is not needed. Unnamed worktrees are skipped. The local all-branches sweep and `--archive-unmerged` are skipped. The origin merged-branch sweep is scoped to the branches the named worktrees held (`-- origin branches (own scope: N named branches):`); plain `apply` and `--worktrees` sweep origin repo-wide. Stray carry and pull still run. |
| Tidy without pulling the shared checkout | `wrap apply --apply --no-pull --own <worktree> <repo>` | `--no-pull` without `--own` skips both the worktree sweep and the branch sweep. |
| Pull the default branch and nothing else | `wrap apply --apply --pull-only <repo>` | Cannot combine with `--worktrees`, `--own`, `--archive-unmerged`, `--archive-worktrees`, `--tips-file`, or `--no-pull`. |
| Archive stale unmerged or detached worktrees | `wrap apply [--apply] --archive-worktrees <repo>` | Opt-in, never with `--own` or `--no-pull`. A worktree idle at least `wrap.archive_worktree_min_age_hours` (default 72), unlocked, not busy, and holding nothing a removal would lose goes to origin `refs/archive/<slug>-<date>` (uncommitted files as a snapshot commit, create-only lease), then is removed with its branch. Needs `lsof`. |
| Adopt a repo into the kit contract | `wrap adopt [--apply] <repo> [<repo>...]` | Dry run by default. `--body-file` takes exactly one repo. |
| Write the activity line | `wrap log "<slug>: <one sentence>"` | Writes immediately and warns over 300 characters. |
| Get the step 7b flick second opinion | `wrap flick-7b < pairs` | Reads one `<candidate-slug> <hit-name> <existing-verdict>` pair per line on stdin, calls `bin/flick` once, and prints one line: the text of the report's `STATE` row. It prints `flick wrap-7b: off` when `decide.points` lacks `wrap-7b`, and `no pairs` on empty input. It exits 0 on every path. |
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
| `flick-7b` | `lib/wrap/wrap-flick.sh` |

`wrap.sh` sources these helper files, which own no verb: `wrap-common.sh` (shared state), `wrap-carry.sh` (stray-line and autoland carry), `wrap-pull.sh` (the pull and union carry-back), and `wrap-ci.sh` (the `ci` label sync and checks wait). `report-lint.sh` is a separate lint for the wrap report's `Needs you` section.
