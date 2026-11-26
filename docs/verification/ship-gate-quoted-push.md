# Verification -- ship-gate-quoted-push

The ship-gate's push parser (`lib/gate/push-refs.sh`) no longer reads a redirection as a refspec or `git push` text in an allowlisted quoted prompt as a push, and `push --delete` of plain non-default names passes; every real unaccounted push still refuses.

## Green run
```
Command: bash tests/test-ship-gate-refs-block.sh
Exit: 0
Output:
ok - redirect after the refspec, piped to tail
ok - redirect to a file
ok - quoted --spec holding git push and a ;
ok - quoted --spec holding git push, no separator
ok - a commit message that mentions a push
ok - --delete of two plain-named branches
ok - an empty-source delete of a plain name
ok - a for-loop delete: the variable stays unresolved
ok - bash -c runs the quoted push
ok - bash -c with a ; inside the quote
ok - git -c core.pager carrying push text
ok - git grep -O carrying push text
ok - an external diff carrying push text
ok - a push inside ( )
ok - a push inside { }
ok - a wrong @@NONE for an unquoted push is refused
ok - unproven branch: a plain push
ok - unproven branch: the redirect form
ok - unproven branch: a push after ;
ok - unproven branch: a push after &&
ok - unproven branch: a delete plus a real push
ok - &> before the refspec no longer hides a default push
ok - a default push wrapped in bash -c is refused in any repo
ok - a wrapped default push after a quoted ; is refused in any repo
Results: 46 passed, 0 failed
Verdict: PASS
```

The real primary flow: the hook itself, fed the PreToolUse JSON of each command the session saw refused, against fixture repos (P adopted with every full-lane gate recorded; A adopted and unproven; Z never adopted). Harness: a scratch script that pipes `{cwd, tool_input.command}` into `hooks/ship-gate.sh` and prints the exit code and the first `BLOCKED` line.

```
Command: ship-gate.sh <- PreToolUse JSON, per command, before (origin/master) and after (this branch)
Exit: per row below
Output:
row                                         before                                                   after
git push -q -u origin feat/done 2>&1 | tail -2   exit 2 '2>' does not resolve to a commit            exit 0
orca ... --spec "1. ...; 2. git push -u ..."     exit 2 git push runs under a wrapper ('2.')         exit 0
git push origin --delete feat/old1 feat/old2     exit 2 git push --delete pushes refs ...            exit 0
for b in ...; do git push origin --delete "$b"   exit 2 ... variable or command substitution        exit 2 (unchanged, by decision)
git push &>/dev/null origin master (never adopted)  exit 0 (parser: @@REF feat/work)             exit 2 lands on 'master'
bash -c "cd /tmp; git push origin feat/other"    exit 0 (parser: @@REF feat/other)              exit 2 wrapper ('bash')
git push -u origin feat/work (unproven)          exit 2 'full' lane requires gates              exit 2 same
git status; git push -u origin feat/work         exit 2 'full' lane requires gates              exit 2 same
git status && git push -u origin feat/work       exit 2 'full' lane requires gates              exit 2 same
bash -c "git push origin master" (never adopted) exit 0                                         exit 2 lands on 'master'
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 1
Output:
test-codex-hooks                               ok (9s)
test-hooks                                     ok (155s)
test-ship-gate-cd-var                          ok (17s)
test-ship-gate-command-words                   ok (64s)
test-ship-gate-default-push                    ok (8s)
test-ship-gate-refs-block                      ok (15s)
run-all: FAILED -> test-boundary-lint test-no-personal-paths
run-all: 61 suites run, 0 skipped for missing tooling
Verdict: PASS for this change. Both failures fail identically on origin/master (commands/ui-design.md:27, a hardcoded operator path from #1212); this branch does not touch that file.
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-refs-block.sh" "git show origin/master:lib/gate/push-refs.sh > lib/gate/push-refs.sh"
Exit: 0 (green before mutation), 1 (under mutation, RED expected), 0 (green after restore)
Output:
  NOT ok - &> before the refspec should refuse the default push (got 0: )
  NOT ok - a default push wrapped in bash -c should refuse in any repo (got 0: )
  Results: 31 passed, 15 failed
Restore: git checkout HEAD -- lib/gate/push-refs.sh
Verdict: PASS
```

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-refs-block.sh" "git show 053b9284:hooks/ship-gate.sh > hooks/ship-gate.sh"
Exit: 0 (green before mutation), 1 (under mutation, RED expected), 0 (green after restore)
Output:
  Results: 45 passed, 1 failed
Restore: git checkout HEAD -- hooks/ship-gate.sh
Verdict: PASS
```
The first control puts master's parser back: 15 rows go red, so the suite pins the redirect, quote, delete and wrapped-default behaviour. The second puts back the hook from before the engage-view guard: the stub-parser row (a wrong `@@NONE` for an unquoted push) goes red. Both files were restored by negctl.

## Not proven
- The installed hook in a live Claude Code session: the kit install under `~/.claude` still runs master's parser until this ships and is reinstalled.
- Programs other than `orca` that take a prompt in a quoted option stay refused by design (allowlist); no run covers how often that bites.
- `gh pr create` text inside a quoted `gh issue create --body` still refuses ("no answer"); not changed here.
