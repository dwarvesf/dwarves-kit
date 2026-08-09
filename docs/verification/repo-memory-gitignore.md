# Proof of done: repo-memory .gitignore fix

Profile: fix   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | A new file under `.claude/memory/` is NOT ignored by git | PASS | R1 |
| 2 | A new file under any other `.claude/` subdir (`.claude/goals/`, `.claude/worktrees/`) IS still ignored | PASS | R1 |
| 3 | Reverting to the old `.gitignore` line reproduces the ignore on the same `.claude/memory/` file (negative control) | PASS | R2 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `.gitignore`'s blanket `.claude/` line silently ignored `.claude/memory/` too, so the repo-memory notes this repo's own `CLAUDE.md` documents as git-tracked never actually left the machine. Switched the line to `.claude/*` (a glob over direct children) plus `!.claude/memory/` (a negation), and committed the two notes that had been sitting locally, uncommitted, for an unknown span. |
| Where | `.gitignore` (the one line), plus the two orphaned notes it had been hiding. |
| Root cause | A plain `.claude/` pattern is a directory match: git excludes the whole subtree from traversal, so no `!` negation pattern nested inside it can ever apply (a standard gitignore limitation, not specific to this repo). `.claude/*` matches only direct children, so git still descends into `.claude/` to evaluate the negation. |
| Reversibility | `git revert` the commit; no runtime behavior changes, only what `git status`/`git add` sees. |

## 3. Confirmation (runs)

| Run | Command | Exit | Verdict |
|---|---|---|---|
| R1 | `echo probe >\| .claude/memory/probe.md && git check-ignore -v .claude/memory/probe.md` | 1 | PASS (not ignored) |
| R1b | `git check-ignore -v .claude/goals/telemetry-closure.md` / `.claude/worktrees` | 0 / 0 | PASS (still ignored) |
| R2 | Same probe file, `.gitignore` swapped to the pre-fix `.claude/` line | 0 | RED-as-expected (ignored) |
| R2b | `.gitignore` restored via `git checkout -- .gitignore` | 1 | PASS (not ignored again) |

## 4. Run detail

### R1 GREEN
```
$ echo probe >| .claude/memory/probe.md && git check-ignore -v .claude/memory/probe.md
GREEN exit=1
```
No match printed, exit 1: the file is not ignored.

### R1b other `.claude/` subdirs still ignored
```
$ git check-ignore -v .claude/goals/telemetry-closure.md
.gitignore:17:.claude/*	.claude/goals/telemetry-closure.md
$ git check-ignore -v .claude/worktrees
.gitignore:17:.claude/*	.claude/worktrees
```
Both still match and are ignored, exit 0, confirming the fix is scoped to `.claude/memory/` only.

### R2 NEGATIVE CONTROL
```
$ git show HEAD~1:.gitignore >| .gitignore.negctrl && cat .gitignore.negctrl >| .gitignore
$ git check-ignore -v .claude/memory/probe.md
.gitignore:13:.claude/	.claude/memory/probe.md
RED exit=0
```
With the pre-fix `.gitignore` line restored, the exact same probe file is ignored again, confirming the fix (not some unrelated cache state) is what changes the outcome.

### R2b restore
```
$ git checkout -- .gitignore
$ git check-ignore -v .claude/memory/probe.md
RESTORED exit=1
```
Fixed `.gitignore` restored from the index; the probe file is not ignored again.

## 5. Reproduce

```
echo probe >| .claude/memory/probe.md
git check-ignore -v .claude/memory/probe.md   # exit 1, not ignored
```

## Before/after

**Before:**
```
.claude/
```
Excludes the whole `.claude/` subtree from traversal; any note written to `.claude/memory/` sits permanently untracked no matter what the repo's own docs claim.

**After:**
```
.claude/*
!.claude/memory/
```
Direct children of `.claude/` are still ignored by default (`.claude/goals/`, `.claude/worktrees/`, etc.), but git still descends into `.claude/` to evaluate the negation, so `.claude/memory/` and everything under it is tracked.
