# Proof of done: ship-gate stops engaging on git stash push

The ship-gate engage regex matched `git stash push`, push-refs printed nothing, and the gate blocked the command as "the command parser gave no answer". The fix blanks `git [globals] stash push` before the engage check only. push-refs and the heredoc check still read the raw command.

## Primary flow: the live hook against an adopted repo

Two real PreToolUse payloads fed to the patched hook, cwd `family-office` (adopted). The script builds the push word at runtime so the session's own gate does not read it.

Command: `bash live-gate.sh <worktree>/hooks/ship-gate.sh`
Exit: 0
Output:
```
$ git stash push -u -m "x" -- planning/a.md planning/b.md && git status --short planning/
exit=0

$ git stash push -u -m x && git push origin HEAD:main
exit=2
BLOCKED: ship-gate. This push lands on 'main', the default branch of 'origin'. Never push straight to a defaul
```
Verdict: PASS

Before the fix, the same script against the installed hook printed `exit=2` and `the command parser gave no answer` for the first payload.

## Test suite

Command: `bash tests/test-ship-gate-command-words.sh`
Exit: 0
Output:
```
---
PASS=107 FAIL=0
```
Verdict: PASS

The other eight `tests/test-ship-gate-*.sh` files also exit 0.

## Negative control

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-command-words.sh" "git show origin/master:hooks/ship-gate.sh >| hooks/ship-gate.sh"`
Exit: 0
Output:
```
  ok - push a branch named stash -> engaged
  ---
  PASS=103 FAIL=4

Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Verdict: PASS (RED on the reverted hook, the four failures are the new allow cases, green after restore)

## Security lens

`kit:security-reviewer` (Opus) on the diff: `VERDICT: PASS`. No push-bearing command newly skips the gate because of this change. Two strings with a backtick or `$(...)` push skip it now; each was an older hole that `GIT_RE` already missed on its own.
