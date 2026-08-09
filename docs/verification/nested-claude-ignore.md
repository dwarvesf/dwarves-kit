# Proof of done: nested .claude/ ignore regression fix

Profile: fix   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | A file inside any NESTED `.claude/` dir (megagoal archives, `lib/prose-rag/rust/`) is ignored again | PASS | R1 |
| 2 | Root `.claude/` children other than memory (`goals/`, `worktrees/`) stay ignored | PASS | R1 |
| 3 | Root `.claude/memory/` stays tracked (the PR #361 behavior is preserved) | PASS | R1, R3 |
| 4 | Reverting to the PR #361 two-line version reproduces the regression on the nested probe (negative control) | PASS | R2 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | PR #361 changed `.claude/` to `.claude/*` to make the root memory negation reachable, but an unanchored pattern with a trailing slash matches at ANY depth while a pattern containing a slash is ANCHORED to the repo root. The old line ignored every nested `.claude/` dir in the tree; the new one only covered the root, so a dozen archive `.claude/` dirs surfaced as untracked noise and dirtied the shared checkout (which also trips the queue watcher's dirty-tree guard). |
| Where | `.gitignore`, the one block. Four patterns, order-dependent: `**/.claude/` (any depth), `!/.claude/` (re-include the root dir so git traverses it), `/.claude/*` (re-ignore its children), `!/.claude/memory/` (exempt memory). |
| Root cause | Two gitignore rules compose here: a directory-match excludes the subtree from traversal (no nested negation can apply), and later patterns override earlier ones. Re-including the root dir itself is legal because its parent (the repo root) is not excluded. |
| Reversibility | `git revert`; affects only what git status sees. |

## 3. Confirmation (runs)

| Run | Command | Exit | Verdict |
|---|---|---|---|
| R1 | probe files in a nested archive `.claude/`, root `.claude/goals/`, root `.claude/memory/`; `git check-ignore -v` each | 0 / 0 / 1 | PASS (ignored / ignored / tracked) |
| R2 | `git stash push -- .gitignore` (reverts to the PR #361 version), re-check the nested probe | 1 | RED-as-expected (nested probe NOT ignored = the regression) |
| R3 | `git stash pop`, re-check nested probe + `git ls-files .claude/` | 0; 3 files listed | PASS (fix restored, memory files still tracked) |

## 4. Run detail

### R1 GREEN
```
T1 nested archive .claude (want ignored):
.gitignore:19:**/.claude/	_meta/megagoals/_archive/cc-elevation/.claude/probe.md
exit=0
T2 root goals (want ignored):
.gitignore:21:/.claude/*	.claude/goals/probe.md
exit=0
T3 root memory (want NOT ignored):
exit=1
```

### R2 NEGATIVE CONTROL
```
$ git stash push -- .gitignore   # working tree back to the PR #361 two-line version
NEGCTRL (pre-fix gitignore) nested probe:
exit=1
```
Exit 1 = not ignored: the nested probe would surface as untracked, reproducing the regression.

### R3 RESTORE
```
$ git stash pop
RESTORED nested probe:
.gitignore:19:**/.claude/	_meta/megagoals/_archive/cc-elevation/.claude/probe.md
exit=0
$ git ls-files .claude/
.claude/memory/MEMORY.md
.claude/memory/auto-queue-watcher-pilot.md
.claude/memory/north-star-direction.md
```

## 5. Reproduce

```
mkdir -p _meta/megagoals/_archive/cc-elevation/.claude
echo x > _meta/megagoals/_archive/cc-elevation/.claude/probe.md
git check-ignore -v _meta/megagoals/_archive/cc-elevation/.claude/probe.md  # exit 0, ignored
git check-ignore -v .claude/memory/MEMORY.md                                # exit 1, tracked
```
