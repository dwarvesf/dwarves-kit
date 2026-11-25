---
name: ship-pr
description: Take a GitHub issue to a merged PR in this repo. Use when asked to do, build, fix or ship an issue or a board row, or when a change is ready to push. Covers claim, branch, proof file, scripts/check.sh, the PR, merge with scripts/pr-merge.sh and clean up.
---

# Ship a PR

Run every command from the repo root of your worktree. The rules behind each step are in `AGENTS.md`, section "Team rules"; the reasons are in `docs/TEAM-WORKFLOW.md`. This file holds the commands only.

## 1. Take the issue

```sh
gh issue list --assignee @me --label ready --state open
gh issue view <n>
gh issue edit <n> --add-assignee @me
```

- Read `## Goal`, `## Done when` and `## Scope`. Done when is your finish check.
- Which issue you may take, and what a PR with no issue says: `AGENTS.md`, sections "Work queue" and "What a PR carries".
- Secrets or access: stop and ask a human (`AGENTS.md`, section "Never"). A `one-way-door` label means step 7 applies.
- To see what is open and what waits on a decision: `bash scripts/team-digest.sh`.

## 2. Branch in a worktree

```sh
git fetch origin {{DEFAULT_BRANCH}}
git worktree add .claude/worktrees/<slug> -b <type>/<slug> origin/{{DEFAULT_BRANCH}}
cd .claude/worktrees/<slug>
```

- `<type>` is feat, fix, refactor, docs, test or chore. The slug is two to five kebab-case words. Never commit on `{{DEFAULT_BRANCH}}`.

## 3. Build

- Make the change. Run the commands for your paths from `AGENTS.md`, section "Commands".
- One logical change per commit. Write the message to a file, then `git commit -F <file>`. Subject `type(scope): subject`, 72 characters or less. Stage explicit paths.
- What the PR must carry (changelog line, docs, owners row, board row): `AGENTS.md`, sections "What a PR carries" and "Changelog". A new script, workflow or job gets a row in `OWNERS.md`; check it with `bash scripts/check-owners.sh`.

## 4. Proof

When a PR owes a proof, and what CI reads in it, is in `AGENTS.md`, section "Proof". Write `docs/verification/<slug>.md` as `docs/verification/README.md` says: a proof file with `Command:` / `Output:` / `Exit:` / `Verdict:` blocks and pasted output, and a negative control. Commit the work first, then run the negative control:

```sh
bash scripts/negctl.sh "<test command>" "<command that breaks one thing>"
```

It shows green, red, restore, green and prints the block to paste into the proof file.

## 5. Check before you push

```sh
bash scripts/check.sh
```

- It runs the same checks as CI with the same inputs. A red check prints the rule and a `Fix:` line. Do what the fix line says, commit, rerun.
- Run your own language tests as well; the stamp ships none.

## 6. Open the PR

```sh
git push -u origin <type>/<slug>
gh pr create --title "<type(scope): subject>" --body-file <file>
```

- Write the body file from `.github/pull_request_template.md`. `Closes #<n>` stands alone on its line. The title becomes the commit subject on `{{DEFAULT_BRANCH}}`.
- When the repo keeps a board file and the issue came from a row, set that row to its shipped state in the same PR.

## 7. One-way door

If the PR touches a door in `AGENTS.md`, section "One-way doors", add the line that section names to the body, with a link to the second person's comment. Without their yes, stop and ask.

## 8. Merge, waiting for CI

```sh
bash scripts/pr-merge.sh --wait --dry-run <n>
bash scripts/pr-merge.sh --wait <n>
```

- `--wait` polls the PR's checks until none is pending, then judges: it refuses a draft, a red or pending check, a conflict, and a change under a door path without a second person's yes. `--dry-run` prints the verdict and merges nothing.
- A refusal prints the rule and a `Fix:` line. A conflict: merge `origin/{{DEFAULT_BRANCH}}` into the branch and push. A red check: read the failing log with `gh run view <run id> --log-failed`, fix, push, run the merge again.
- A repo with no self-hosted runner shows its checks as pending. Run `bash scripts/check.sh` in its place; `--wait` never merges on a pending check.

## 9. Clean up

Never use a bare `gh pr merge`: the hook stops it and CI finds it later. After the merge, from the checkout you started in, remove only your own worktree and branch: `git worktree remove .claude/worktrees/<slug>` and `git branch -d <type>/<slug>`.

## Done when

`gh pr view <n> --json state --jq .state` prints `MERGED`, issue #<n> is closed, the board row (if any) is updated, and your worktree is gone.
