# Proof of done: the ship-gate refuses a push onto a default branch

Acceptance: `hooks/ship-gate.sh` exits 2 on any git push whose resolved destination is a default branch, in any repo, adopted or not. A default branch is `main`, `master`, `production`, the name `origin/HEAD` points at, or the branch the target remote's HEAD names. The destination is resolved from an explicit refspec, or, with no refspec, the way git resolves it: `remote.<remote>.push`, then `push.default` (simple and current push the current branch, upstream pushes to `branch.<cur>.merge`, matching also counts each local default branch). The refusal names the branch, the remote, and the PR route. `KIT_ALLOW_DEFAULT_PUSH=1` in the hook's own environment is the one escape; the same words as a command prefix do not count. Lane: normal (the classifier suggested full for kit machinery). Files: `hooks/ship-gate.sh`, `lib/gate/push-refs.sh`, `tests/test-ship-gate-default-push.sh`, `tests/test-lanes-data.sh`.

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
ok - feature branch: git push origin HEAD:main -> blocked
ok - feature branch: git push origin HEAD:refs/heads/main -> blocked
ok - feature branch: git push origin main -> blocked
ok - feature branch: HEAD:production -> blocked (fallback name)
ok - git push -u origin HEAD:refs/heads/feature -> allowed
ok - feature branch: plain git push -> allowed
ok - feature branch: git push -u origin HEAD -> allowed
ok - feature branch: git push origin feat/thing -> allowed
ok - push.default=upstream, upstream main: plain git push -> blocked
ok - push.default=simple, upstream main: plain git push -> allowed (git pushes the same name)
ok - remote.origin.push HEAD:main: plain git push -> blocked
ok - remote HEAD develop: git push origin HEAD:develop -> blocked
ok - a second remote's HEAD: git push upstream HEAD:trunk -> blocked
ok - remote HEAD develop: feature push -> allowed
ok - plain push on master, adopted repo -> blocked
---
PASS=25 FAIL=0
Exit: 0
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed --time
run-all: 47 suites, 4 at a time, 0 serial
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

Three controls, each run through `bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-default-push.sh" "<mutation>"` on the committed tree.

| # | Mutation | Under mutation | Restored |
|---|---|---|---|
| 1 | drop the `_default_block` call in `hooks/ship-gate.sh` | Exit 1, PASS=8 FAIL=17 | Exit 0 |
| 2 | the branch base's copy of both files (`git show HEAD~1:...`, base `4e920ad6`) | Exit 1, PASS=8 FAIL=17 | Exit 0 |
| 3 | disable the `push.default=upstream` branch in `push-refs.sh` | Exit 1, PASS=24 FAIL=1 | Exit 0 |

```
## Negative control (negctl)
Command: bash tests/test-ship-gate-default-push.sh
Exit: 0 (green before mutation)
Mutation: git show HEAD~1:hooks/ship-gate.sh > hooks/ship-gate.sh && git show HEAD~1:lib/gate/push-refs.sh > lib/gate/push-refs.sh
Changed: hooks/ship-gate.sh, lib/gate/push-refs.sh
Exit: 1 (under mutation, RED expected)
Output:
  NOT ok - push.default=upstream, upstream main: plain git push -> blocked (want exit 2 + 'lands on 'main'', got 0: )
  NOT ok - remote.origin.push HEAD:main: plain git push -> blocked (want exit 2, got 0: ship-gate: fixture identity check skipped (no base to compare against))
  NOT ok - remote HEAD develop: git push origin HEAD:develop -> blocked (want exit 2 + 'lands on 'develop'', got 0: )
  NOT ok - a second remote's HEAD: git push upstream HEAD:trunk -> blocked (want exit 2 + 'default branch of 'upstream'', got 0: )
  NOT ok - plain push on master, adopted repo -> blocked (want exit 2 + 'lands on 'master'', got 0: )
  ---
  PASS=8 FAIL=17
Restore: git checkout HEAD -- hooks/ship-gate.sh lib/gate/push-refs.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Control 2 is the incident shape: the old code passes the plain push on `master` in an adopted repo, and 17 assertions go red.

## Kit verbs that push

A PreToolUse hook reads the command text the agent types, not the git calls inside a kit script. `bin/release` pushes `master` from inside the script, so the hook never sees it. `wrap land` calls the ship-gate directly with `git push origin <branch>` for a feature branch. `wrap` stray carries push `wrap/stray-*` branches. None of them lands on a default branch through the hook, and `test-wrap-land` and `test-wrap-merge` pass unchanged.

## Known gaps

- A push the parser cannot read (a variable, a wrapper, an unknown option, a heredoc fed to a shell) still fails open outside adopted repos, as before. The remote's branch protection stays the backstop.
- `KIT_ALLOW_DEFAULT_PUSH=1` does not reach safety-gate, which still refuses an explicit `main` or `master` token on the command. The escape covers the forms only the ship-gate resolves.

## Reproduce

```bash
bash tests/test-ship-gate-default-push.sh
bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-default-push.sh" \
  "git show 4e920ad6:hooks/ship-gate.sh > hooks/ship-gate.sh && git show 4e920ad6:lib/gate/push-refs.sh > lib/gate/push-refs.sh"
```

`4e920ad6` is the branch base on `master`. The recorded run used `HEAD~1`, which was that base while the feature commit was the tip.
