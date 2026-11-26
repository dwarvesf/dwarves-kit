# Verification -- ship-gate-quoted-push

The ship-gate's push parser (`lib/gate/push-refs.sh`) answers a push only when the push is the whole Bash call. It no longer reads an fd redirect on that push as a refspec, and `push --delete` of plain non-default names passes. Any other step beside a push refuses, and the default-branch rule still holds in every repo.

## Green run
```
Command: bash tests/test-ship-gate-refs-block.sh
Exit: 0
Output:
ok - 2>&1 on the push
ok - >/dev/null 2>&1 on the push
ok - one pipe into grep with a literal pattern
ok - redirect to a file
ok - a ~/.gitconfig write, then a push
ok - an XDG git config write, then a push
ok - export GIT_CONFIG_GLOBAL, then a push
ok - GIT_CONFIG_GLOBAL= prefix on the push
ok - cd, then a push
ok - --delete of two plain-named branches
ok - review F1: a delete, then push text piped into bash
ok - add, commit, then a real push
ok - --receive-pack= on a real push
ok - review H2: config receivepack, then a delete
ok - review S1: GIT_CONFIG_* env sets receivepack, then a push
ok - review S2: HOME moved and ~/.gitconfig written, then a push
ok - review S3: a pre-push hook written into .git, then a push
ok - review S5: export GIT_DIR, then a push
ok - unproven branch: a plain push
ok - unproven branch: the redirect form
ok - unproven branch: a push after ;
ok - unproven branch: a push after &&
ok - &> before the refspec no longer hides a default push
ok - a wrapped default push after a quoted ; is refused in any repo
ok - gh pr create with $(...) in the title
ok - gh pr create with a backtick in the title
ok - gh pr create with a process substitution
ok - git push with $(...) in a refspec
ok - a pipe into a path named cat
Results: 108 passed, 0 failed
Verdict: PASS
```

The real primary flow: the hook itself, fed the PreToolUse JSON of each command, against fixture repos (P adopted with every full-lane gate recorded; A adopted and unproven; Z never adopted).

```
Command: ship-gate.sh <- PreToolUse JSON, per command, before (origin/master) and after (this branch)
Exit: per row below
Output:
row                                              before                                     after
git push -q -u origin feat/done 2>&1 | tail -2   exit 2 '2>' does not resolve to a commit    exit 0
git push origin --delete feat/old1 feat/old2     exit 2 git push --delete ...                 exit 0
git push -u origin feat/done >/tmp/push.log 2>&1 exit 2 '>/tmp/push.log' does not resolve   exit 2 only command in the call
orca ... --spec "...; 2. git push ..."           exit 2 wrapper ('2.')                       exit 2 wrapper ('orca')
for b in ...; do git push origin --delete "$b"   exit 2 variable or command substitution     exit 2 same
git push &>/dev/null origin master (Z)           exit 0                                      exit 2 lands on 'master'
bash -c "cd /tmp; git push origin feat/other"    exit 0                                      exit 2 wrapper ('bash')
git push -u origin feat/work (unproven)          exit 2 'full' lane requires gates           exit 2 same
git status; git push -u origin feat/work         exit 2 'full' lane requires gates           exit 2 only command in the call
Verdict: PASS
```

The review harness runs each command for real when the gate passes, then checks the bare origin's master:
```
Command: GIT_CONFIG_GLOBAL=/dev/null bash run.sh ./h.sh   (all 41 review cases at this head)
Exit: per case
Output:
F1 F1c F2 F2b F3 F3b R1-R5 D1 D2 D2b D3-D9 P1 H1 H2 H2r H3 O3 O4 O5 S1 S1b S2 S2b S3 S4 S5   GATE rc=2, nothing ran
O1 delete with -o carrying push text   GATE rc=0, no push landed (a push option is server data)
O2 --force-with-lease with a delete    GATE rc=0, no push landed (a force push is safety-gate's)
C0 plain feature push (control)        GATE rc=0, no push landed on master
F4 heredoc piped into bash             GATE rc=0, master MOVED  (same on origin/master: out of this diff)
F5 X=push; git $X origin ...           GATE rc=0, master MOVED  (same on origin/master: out of this diff)
Verdict: PASS for every case this branch had let through
```

```
Command: GIT_CONFIG_GLOBAL=/dev/null bash tests/run-all.sh --changed --time
Exit: 1
Output:
run-all: FAILED -> test-boundary-lint test-no-personal-paths
run-all: 61 suites run, 0 skipped for missing tooling
(test-hooks, test-codex-hooks, test-lanes-data and every test-ship-gate-* suite: ok)
Verdict: PASS for this change. Both failures fail identically on origin/master (commands/ui-design.md:27); this branch does not touch that file. The global git config is isolated because the operator's ~/.gitconfig was overwritten during the review with a remote.origin.push refspec, which turns every plain push in a fixture into a default push.
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-refs-block.sh" "git show origin/master:lib/gate/push-refs.sh > lib/gate/push-refs.sh"
Exit: 0 (green before mutation), 1 (under mutation, RED expected), 0 (green after restore)
Output:
  Results: 37 passed, 71 failed
Restore: git checkout HEAD -- lib/gate/push-refs.sh
Verdict: PASS
```

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-refs-block.sh" "git show 053b9284:hooks/ship-gate.sh > hooks/ship-gate.sh"
Exit: 0 (green before mutation), 1 (under mutation, RED expected), 0 (green after restore)
Output:
  Results: 107 passed, 1 failed
Restore: git checkout HEAD -- hooks/ship-gate.sh
Verdict: PASS
```
The first control puts master's parser back: 71 rows go red. The second puts back a hook with no refusal for an answer that names no branch: the stub-parser row goes red. negctl restored both files. Both ran with `GIT_CONFIG_GLOBAL=/dev/null`.

## Not proven
- The installed hook in a live Claude Code session: the kit install under `~/.claude` still runs master's parser until this ships and is reinstalled.
- Config, hooks or environment left by an EARLIER Bash call. Only a native git pre-push hook, which sees the exact refs, can close that.
- F4 (a heredoc piped into a shell) and F5 (`X=push; git $X ...`) get through on origin/master and on this branch.
