# Proof of done: the ship-gate refuses a push onto a default branch

Acceptance: `hooks/ship-gate.sh` exits 2 on any git push whose resolved destination is a default branch, in any repo, adopted or not. A default branch is `main`, `master`, `production`, the name `origin/HEAD` points at, or the branch the target remote's HEAD names. The destination is resolved from an explicit refspec, or, with no refspec, the way git resolves it: `remote.<remote>.push`, then `push.default` (simple and current push the current branch, upstream pushes to `branch.<cur>.merge`, matching also counts each local default branch). The refusal names the branch, the remote, and the PR route. `KIT_ALLOW_DEFAULT_PUSH=1` in the hook's own environment is the one escape; the same words as a command prefix do not count. Lane: normal (the classifier suggested full for kit machinery). Files: `hooks/ship-gate.sh`, `lib/gate/push-refs.sh`, `tests/test-ship-gate-default-push.sh`, `tests/test-lanes-data.sh`.

A `git checkout <b>` or `git switch <b>` earlier in the same command moves what HEAD means for a later push. Push options the parser cannot list (`--follow-tags`, `--tags`, `--delete`, an unknown option) are held until the default-branch pass has run, so they cannot hide a default push.

## The failure this replaces

A subagent in a scratch shallow clone of `dwarvesf/brainery` ran `gh pr checkout <n>`, which failed. Its loop then committed on `main` and ran a plain `git push`. Four commits landed on brainery's `main` and triggered a publish. Two holes let it through:

| Hook | Why it passed the push |
|---|---|
| `safety-gate.sh` | reads only the ref tokens typed on the command; a plain `git push` names no ref |
| `ship-gate.sh` | `push-refs.sh` did resolve `HEAD` to `main` and printed `@@DEFAULT`, and the hook then exited 0, leaving it to safety-gate |

## Green run

```
Command: bash tests/test-ship-gate-default-push.sh
ok - plain push on main, non-adopted repo -> blocked, names the branch
ok - refusal names the PR route
ok - git push origin main -> blocked
ok - git push -u origin HEAD on main -> blocked
ok - an earlier unresolvable push does not hide a later default push
ok - KIT_ALLOW_DEFAULT_PUSH=1 in the hook env -> allowed
ok - KIT_ALLOW_DEFAULT_PUSH=1 as a command prefix -> still blocked
ok - the escape is logged
ok - cd <repo> && git push from another cwd -> blocked (resolves the target repo)
ok - gh pr create on main -> unchanged (not a git push)
ok - git push origin @ on main -> blocked (@ is HEAD)
ok - git push --follow-tags on main -> blocked (option held until the default pass)
ok - /usr/bin/git push on main -> blocked
ok - pushd <repo> && git push -> blocked
ok - switch -c to a new branch, then push HEAD -> allowed
ok - heredoc opener line: the push after it is still read -> blocked
ok - feature branch: git push origin HEAD:main -> blocked
ok - feature branch: git push origin HEAD:refs/heads/main -> blocked
ok - feature branch: git push origin main -> blocked
ok - feature branch: HEAD:production -> blocked (fallback name)
ok - git push -u origin HEAD:refs/heads/feature -> allowed
ok - feature branch: plain git push -> allowed
ok - feature branch: git push -u origin HEAD -> allowed
ok - feature branch: git push origin feat/thing -> allowed
ok - feature branch: git push origin HEAD:heads/main -> blocked (git expands heads/)
ok - feature branch: git push --follow-tags origin main -> blocked
ok - feature branch: git push --delete origin main -> blocked
ok - checkout main && merge && plain push -> blocked (HEAD is main by then)
ok - switch main && git push origin HEAD -> blocked
ok - push.default=upstream, upstream main: plain git push -> blocked
ok - git -c push.default=upstream push, upstream main -> blocked
ok - push.default=simple, upstream main: plain git push -> allowed (git pushes the same name)
ok - remote.origin.push HEAD:main: plain git push -> blocked
ok - remote HEAD develop: git push origin HEAD:develop -> blocked
ok - a second remote's HEAD: git push upstream HEAD:trunk -> blocked
ok - remote HEAD develop: feature push -> allowed
ok - plain push on master, adopted repo -> blocked
---
PASS=37 FAIL=0
Exit: 0
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
run-all: all 47 suites passed, 0 skipped for missing tooling
Exit: 0
Verdict: PASS, no regression
```

The `--changed` set covers every suite that drives `hooks/ship-gate.sh` or `lib/gate/push-refs.sh`, including `test-hooks`, `test-lanes-data`, `test-wrap-land` and `test-wrap-merge`.

## Expectation changed on purpose

`tests/test-lanes-data.sh` case `ship-push-forms` pinned the old hand-off. Three rows move from exit 0 to exit 2, because the ship-gate now refuses them itself:

| Command | Before | After |
|---|---|---|
| `git push origin feat/x:master` | 0 | 2 |
| `git push origin HEAD:refs/heads/main` | 0 | 2 |
| `git push origin main` | 0 | 2 |

## Negative control

Four controls, each run through `bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-default-push.sh" "<mutation>"` on the committed tree.

| # | Mutation | Under mutation | Restored |
|---|---|---|---|
| 1 | drop the `_default_block` call in `hooks/ship-gate.sh` | Exit 1, PASS=9 FAIL=28 | Exit 0 |
| 2 | the branch base's copy of both files (`git show 4e920ad6:...`) | Exit 1, PASS=9 FAIL=28 | Exit 0 |
| 3 | disable the `push.default=upstream` branch in `push-refs.sh` | Exit 1, PASS=35 FAIL=2 | Exit 0 |
| 4 | ignore an earlier `git checkout` or `git switch` in the command | Exit 1, PASS=34 FAIL=3 | Exit 0 |

```
## Negative control (negctl)
Command: bash tests/test-ship-gate-default-push.sh
Exit: 0 (green before mutation)
Mutation: git show 4e920ad6:hooks/ship-gate.sh > hooks/ship-gate.sh && git show 4e920ad6:lib/gate/push-refs.sh > lib/gate/push-refs.sh
Changed: hooks/ship-gate.sh, lib/gate/push-refs.sh
Exit: 1 (under mutation, RED expected)
Output:
  NOT ok - push.default=upstream, upstream main: plain git push -> blocked (want exit 2 + 'lands on 'main'', got 0: )
  NOT ok - git -c push.default=upstream push, upstream main -> blocked (want exit 2, got 0: )
  NOT ok - remote.origin.push HEAD:main: plain git push -> blocked (want exit 2, got 0: ship-gate: fixture identity check skipped (no base to compare against))
  NOT ok - remote HEAD develop: git push origin HEAD:develop -> blocked (want exit 2 + 'lands on 'develop'', got 0: )
  NOT ok - a second remote's HEAD: git push upstream HEAD:trunk -> blocked (want exit 2 + 'default branch of 'upstream'', got 0: )
  NOT ok - plain push on master, adopted repo -> blocked (want exit 2 + 'lands on 'master'', got 0: )
  ---
  PASS=9 FAIL=28

Restore: git checkout HEAD -- hooks/ship-gate.sh lib/gate/push-refs.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Control 2 is the incident shape: the old code passes the plain push on `master` in an adopted repo, and 28 assertions go red.

## Review

A security lens (`kit:code-reviewer`, bypass hunting) ran on the first version and found seven bypass shapes, rated HIGH to LOW. The fix commits close every row below:

| Finding | Command shape | Now |
|---|---|---|
| branch switch before the push | `git checkout main && git merge feat/x && git push` | blocked |
| a listed-refs option exits early | `git push --follow-tags origin main`, `--delete origin main` | blocked |
| `@` means HEAD | `git push origin @` on main | blocked |
| git expands `heads/` | `git push origin HEAD:heads/main` | blocked |
| heredoc opener line | `git commit -F - <<'EOF' && git push origin main` | blocked |
| absolute git path | `/usr/bin/git push` on main | blocked |
| `pushd`, `-c push.default` | `pushd <repo> && git push`, `git -c push.default=upstream push` | blocked |

`git --git-dir=<other> push` still reads the session repo. It is listed under known gaps.

## Kit verbs that push

A PreToolUse hook reads the command text the agent types, not the git calls inside a kit script. `bin/release` pushes `master` from inside the script, so the hook never sees it. `wrap land` calls the ship-gate directly with `git push origin <branch>` for a feature branch. `wrap` stray carries push `wrap/stray-*` branches. None of them lands on a default branch through the hook, and `test-wrap-land` and `test-wrap-merge` pass unchanged.

## Known gaps

- A push the parser cannot read (a variable, a wrapper, a heredoc fed to a shell, `git checkout -` before the push) still fails open outside adopted repos, as before. The remote's branch protection stays the backstop.
- `git --git-dir=<other>/.git push` resolves against the session repo, not `<other>`.
- An agent able to write `env` into a settings file could set `KIT_ALLOW_DEFAULT_PUSH` for a later session. The escape assumes the operator owns the session environment.
- `KIT_ALLOW_DEFAULT_PUSH=1` does not reach safety-gate, which still refuses an explicit `main` or `master` token on the command. The escape covers the forms only the ship-gate resolves.

## Reproduce

```bash
bash tests/test-ship-gate-default-push.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-default-push.sh" \
  "git show 4e920ad6:hooks/ship-gate.sh > hooks/ship-gate.sh && git show 4e920ad6:lib/gate/push-refs.sh > lib/gate/push-refs.sh"
```

`4e920ad6` is the branch base on `master`.
