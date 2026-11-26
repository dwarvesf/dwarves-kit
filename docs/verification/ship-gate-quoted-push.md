# Verification -- ship-gate-quoted-push

The ship-gate's push parser (`lib/gate/push-refs.sh`) no longer reads a redirection in a real push segment as a refspec, and `push --delete` of plain non-default names passes. Quoted push text is never treated as data. Every real unaccounted push still refuses, and so does a push beside any step that could run another push.

## Green run
```
Command: bash tests/test-ship-gate-refs-block.sh
Exit: 0
Output:
ok - redirect after the refspec, piped to tail
ok - redirect to a file
ok - --delete of two plain-named branches
ok - an empty-source delete of a plain name
ok - review F1: a delete, then push text piped into bash
ok - review F1c: a delete, then push text run as a script on PATH
ok - review F2: an alias written by printf, then run
ok - review F2b: a post-commit hook written by echo
ok - review F3: GIT_EDITOR carries the push
ok - review F3b: git options in a variable
ok - commit -c core.editor carrying push text, then a real push
ok - git -c core.editor carrying push text, then a real push
ok - an editor env prefix, then a real push
ok - rebase --exec, then a real push
ok - an unknown git subcommand (an alias), then a real push
ok - add, commit, then a real push
ok - unproven branch: a plain push
ok - unproven branch: the redirect form
ok - unproven branch: a push after ;
ok - unproven branch: a push after &&
ok - unproven branch: a delete plus a real push
ok - &> before the refspec no longer hides a default push
ok - a wrapped default push after a quoted ; is refused in any repo
Results: 65 passed, 0 failed
Verdict: PASS
```

The real primary flow: the hook itself, fed the PreToolUse JSON of each command, against fixture repos (P adopted with every full-lane gate recorded; A adopted and unproven; Z never adopted).

```
Command: ship-gate.sh <- PreToolUse JSON, per command, before (origin/master) and after (this branch)
Exit: per row below
Output:
row                                              before                                         after
git push -q -u origin feat/done 2>&1 | tail -2   exit 2 '2>' does not resolve to a commit        exit 0
git push -u origin feat/done >/tmp/push.log 2>&1 exit 2 '>/tmp/push.log' does not resolve       exit 0
git push origin --delete feat/old1 feat/old2     exit 2 git push --delete pushes refs ...        exit 0
orca ... --spec "...; 2. git push ..."           exit 2 wrapper ('2.')                           exit 2 wrapper ('orca')
for b in ...; do git push origin --delete "$b"   exit 2 variable or command substitution         exit 2 same
git push &>/dev/null origin master (Z)           exit 0                                          exit 2 lands on 'master'
bash -c "cd /tmp; git push origin feat/other"    exit 0                                          exit 2 wrapper ('bash')
git push -u origin feat/work (unproven)          exit 2 'full' lane requires gates               exit 2 same
git status; git push -u origin feat/work         exit 2 'full' lane requires gates               exit 2 same
git status && git push -u origin feat/work       exit 2 'full' lane requires gates               exit 2 same
Verdict: PASS
```

The second review's harness runs each command for real when the gate passes, then checks the bare origin's master:
```
Command: bash run.sh ./h.sh   (cases F1 F1c F2 F2b F3 F3b F4 F5)
Exit: per case
Output:
F1 F1c F2 F2b F3 F3b   GATE rc=2, nothing ran            (6854d945: GATE rc=0, origin master MOVED)
F4 heredoc piped into bash       GATE rc=0, master MOVED  (same on origin/master: out of this diff)
F5 X=push; git $X origin ...     GATE rc=0, master MOVED  (same on origin/master: out of this diff)
Verdict: PASS for every regression this branch had introduced
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 1
Output:
test-codex-hooks                               ok (8s)
test-hooks                                     ok (156s)
test-lanes-data                                ok (186s)
test-ship-gate-command-words                   ok (58s)
test-ship-gate-default-push                    ok (7s)
test-ship-gate-refs-block                      ok (19s)
run-all: FAILED -> test-boundary-lint test-no-personal-paths
run-all: 61 suites run, 0 skipped for missing tooling
Verdict: PASS for this change. Both failures fail identically on origin/master (commands/ui-design.md:27, a hardcoded operator path); this branch does not touch that file.
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-refs-block.sh" "git show origin/master:lib/gate/push-refs.sh > lib/gate/push-refs.sh"
Exit: 0 (green before mutation), 1 (under mutation, RED expected), 0 (green after restore)
Output:
  Results: 35 passed, 30 failed
Restore: git checkout HEAD -- lib/gate/push-refs.sh
Verdict: PASS
```

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-refs-block.sh" "git show 053b9284:hooks/ship-gate.sh > hooks/ship-gate.sh"
Exit: 0 (green before mutation), 1 (under mutation, RED expected), 0 (green after restore)
Output:
  Results: 64 passed, 1 failed
Restore: git checkout HEAD -- hooks/ship-gate.sh
Verdict: PASS
```
The first control puts master's parser back: 30 rows go red, so the suite pins the redirect, delete, wrapped-default and fail-closed behaviour. The second puts back a hook with no refusal for an answer that names no branch: the stub-parser row goes red. negctl restored both files.

## Not proven
- The installed hook in a live Claude Code session: the kit install under `~/.claude` still runs master's parser until this ships and is reinstalled.
- F4 (a heredoc piped into a shell, gate exit 0 although the parser reports the default push) and F5 (`X=push; git $X ...`) pass on origin/master and on this branch. They are not fixed here.
