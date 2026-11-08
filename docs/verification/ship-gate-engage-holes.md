# Proof of done: ship-gate engages on quoted separators, substitutions and IFS

The engage regex `GIT_RE` failed open on three shapes. It stopped at a `;`, `&` or `|` inside quotes, so `git -C "a;b" push` skipped the gate. It needed whitespace after the push word, so a push that ends a backtick or `$(..)` substitution skipped it. It never read `${IFS}` as a separator. The fix reads `$IFS` and `${IFS..}` as a space, lets the push word end at a backtick, `)`, `;`, `&` or `|`, and matches a second engage copy with quoted text and escaped characters blanked. Both copies are matched, so the change only adds engagement. push-refs.sh is unchanged and still decides, failing closed.

## Primary flow: the live hook against an adopted repo

Real PreToolUse payloads fed to the patched hook, cwd this worktree (adopted, feature branch). The script builds the push word at runtime so the session's own gate does not read it.

Command: `bash live-gate.sh <worktree>/hooks/ship-gate.sh <worktree>`
Exit: 0
Output:
```
$ git -C "a;b" push -u origin HEAD
exit=2
BLOCKED: ship-gate. This command pushes refs the gate cannot account for: the command parser gave no answer.

$ echo `git push`
exit=2
BLOCKED: ship-gate. This command pushes refs the gate cannot account for: the command parser gave no answer.

$ x=$(git push origin HEAD)
exit=2
BLOCKED: ship-gate. This command pushes refs the gate cannot account for: the command parser gave no answer.

$ x=$(git push)
exit=2
BLOCKED: ship-gate. This command pushes refs the gate cannot account for: the command parser gave no answer.

$ x=$(git${IFS}push${IFS}origin${IFS}HEAD)
exit=2
BLOCKED: ship-gate. This command pushes refs the gate cannot account for: the command parser gave no answer.

$ git stash push -u -m "a;b" -- x
exit=0

$ x=$(git stash push)
exit=0

$ echo "remember to push"
exit=0

$ git status
exit=0
```
Verdict: PASS

The same script against the installed hook (master, #1099) printed `exit=0` for `git -C "a;b" push`, ``echo `git push` ``, `x=$(git push)` and the `${IFS}` form. Only `x=$(git push origin HEAD)` engaged there.

## Test suites

Command: `for t in tests/test-ship-gate-*.sh; do bash "$t"; done`
Exit: 0
Output:
```
tests/test-ship-gate-command-words.sh rc=0 :: PASS=133 FAIL=0
tests/test-ship-gate-coverage-map.sh rc=0 :: PASS=10 FAIL=0
tests/test-ship-gate-default-push.sh rc=0 :: PASS=37 FAIL=0
tests/test-ship-gate-fail-closed.sh rc=0 :: PASS=12 FAIL=0
tests/test-ship-gate-identities.sh rc=0 :: pass=11 fail=0
tests/test-ship-gate-impl-notes.sh rc=0 :: PASS=19 FAIL=0
tests/test-ship-gate-profiles.sh rc=0 :: ALL PASS (3 profiles x allow+block)
tests/test-ship-gate-refs-block.sh rc=0 :: Results: 11 passed, 0 failed
tests/test-ship-gate-review-verdict.sh rc=0 :: pass=60 fail=0
```
Verdict: PASS

Command: `bash tests/run-all.sh --changed --time`
Exit: 0
Output:
```
run-all: all 32 suites passed, 0 skipped for missing tooling
```
Verdict: PASS

## Negative control

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-command-words.sh" "git show origin/master:hooks/ship-gate.sh >| hooks/ship-gate.sh"`
Exit: 0
Output:
```
Mutation: git show origin/master:hooks/ship-gate.sh >| hooks/ship-gate.sh
Changed: hooks/ship-gate.sh
Exit: 1 (under mutation, RED expected)
Output:
  ok - stash push, quoted ; in the message -> not engaged
  ok - stash push inside backticks -> not engaged
  ok - stash push ends a substitution -> not engaged
  ok - stash push with ${IFS} -> not engaged
  ok - -C value is a stash push subst -> engaged
  ok - -C value is a stash push backtick -> engaged
  ok - --git-dir= value is a stash subst -> engaged
  ok - quoted ; then push in a commit msg -> not engaged
  ---
  PASS=118 FAIL=15

Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Verdict: PASS (RED on the master hook, green after restore)

The 15 red cases are the new engage cases: the quoted `;`, `&`, `|` and escaped `;` in the `-C` dir, a quoted `;` inside a substitution and inside backticks, push inside backticks, push ending a substitution, push followed by `;`, `&&` and `|`, and the four `IFS` forms. `x=$(git push origin HEAD)` already engaged on master, so it stays green there.

## Security-lens regression and its control

The first cut widened the stash push ending to `)` and a backtick, and a git global's value could hold `$(git` or a backtick. So `git -C $(git stash push) push origin HEAD` was blanked whole as a stash push and lost its outer push (exit 2 on master, exit 0 on the branch). Global option values now exclude backticks, `$` and parens. Three engage cases cover it. Control against the first-cut hook:

Command: `bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-command-words.sh" "git show 1e6ee561:hooks/ship-gate.sh >| hooks/ship-gate.sh"`
Exit: 0
Output:
```
  NOT ok - -C value is a stash push subst -> should engage (exit 2)
  NOT ok - -C value is a stash push backtick -> should engage (exit 2)
  NOT ok - --git-dir= value is a stash subst -> should engage (exit 2)
  ok - quoted ; then push in a commit msg -> not engaged
  ---
  PASS=130 FAIL=3

Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Verdict: PASS (the three regressions go RED on the first cut, green after restore)

## Known false positives

A git command whose text has `push` followed by `;`, `)`, `|` or `&` now engages, for example a commit message `git commit -m "fix push;"` or `git log --grep 'push|pull'`. In an adopted repo push-refs.sh then names no ref and the gate blocks it. Master already had the same class for `push` followed by a space (`git commit -m "docs: push the fix"` engages there).

## Bypasses still open

These shapes still skip the engage check (exit 0 in the fixture). Each predates this change: `"git" push`, `g'i't push`, `git "push"`, `git pu''sh`, `git pu\sh`, `git$IFS'push'`, `{git,push,origin,HEAD}`, `g=git; $g push`, `p=push; git $p`. They hide the command word through quoting, brace expansion or a variable, which a regex engage check cannot resolve.
