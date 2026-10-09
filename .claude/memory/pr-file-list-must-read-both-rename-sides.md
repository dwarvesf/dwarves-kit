---
name: pr-file-list-must-read-both-rename-sides
description: gh pr diff --name-only lists only a rename's new name; a file-level PR guard must read the REST files list with previous_filename, paginated, and fail closed at its 3000-file cap.
metadata:
  type: project
---

`gh pr diff --name-only` prints only the destination of a rename, so `git mv .kit.toml other` hides the protected path from a guard that greps that list. The REST endpoint `repos/{owner}/{repo}/pulls/<n>/files` carries `previous_filename`; read it with `gh api --paginate --jq '.[] | .filename, (.previous_filename // empty)'`. The endpoint returns at most 3000 files, so a list that long is unclassifiable and must refuse. Never swap in `gh pr view --json files`: it caps at 100 files and fails open. Pin the merge with `--match-head-commit` to the head read before the guards, or a push after the check lands unread.

**Why:** the `.kit.toml` auto-merge guard first matched key names in changed lines (bypassed by editing one entry line), then file names from `gh pr diff` (bypassed by a rename); an Opus security review found the second.

**How to apply:** `_pr_files` and `_pr_head` in `lib/goal/mega-merge.sh` are the reference shapes for any new PR-level guard. Related: [[hook-stderr-dropped-on-exit-zero]].
