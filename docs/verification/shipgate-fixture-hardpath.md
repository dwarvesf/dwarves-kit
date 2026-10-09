# Verification -- shipgate-fixture-hardpath

A committed `[lanes] hard_path_exempt` ERE, read only at the merge base, lets a repo ship a reviewed non-risky path (the `sd-login-locked.mjs` test oracle) past the hard-path floor, while real auth paths still block.

## Green run

The real primary flow: the consumer case pushed through the real `hooks/ship-gate.sh` in a fixture repo, with only normal-lane gates recorded (script: a scratch `e2e.sh` that builds the repo, records `spec validate build review ship`, and pipes a `git push -u origin feat/x` payload into the hook).

```
Command: bash e2e.sh <worktree> <scratch>
Exit: 0
Output:
== no exemption, oracle only: hook exit 2
BLOCKED: ship-gate. This diff touches a hard path (auth: experiments/qa-runner/cases/oracle/sd-login-locked.mjs); the full lane's gates apply whatever the spec's Lane says:
BLOCKED | ship-gate | x (hard-path auth)
== base exemption, oracle only: hook exit 0
EXEMPT | floor | x (auth: experiments/qa-runner/cases/oracle/sd-login-locked.mjs)
== base exemption, oracle + src/auth/login.ts: hook exit 2
BLOCKED: ship-gate. This diff touches a hard path (auth: src/auth/login.ts); the full lane's gates apply whatever the spec's Lane says:
EXEMPT | floor | x (auth: experiments/qa-runner/cases/oracle/sd-login-locked.mjs)
BLOCKED | ship-gate | x (hard-path auth)
== base exemption, oracle + lib/session.ts: hook exit 2
BLOCKED: ship-gate. This diff touches a hard path (auth: lib/session.ts); the full lane's gates apply whatever the spec's Lane says:
EXEMPT | floor | x (auth: experiments/qa-runner/cases/oracle/sd-login-locked.mjs)
BLOCKED | ship-gate | x (hard-path auth)
Verdict: PASS
```

The acceptance cases, one per AC row, plus the existing floor and ship cases they sit beside:

```
Command: bash tests/test-lanes-data.sh ship-exempt-logged ship-exempt-in-pr-blocks floor-exempt-fixture-quiet floor-exempt-real-auth-still-hits floor-exempt-working-tree-ignored floor-exempt-never-kit-config floor-exempt-empty-match-rejected floor-exempt-data-loss-still-hits classify-files-exempt floor-paths ship-migration-blocks ship-no-spec-blocks ship-flip-gate-in-pr
Exit: 0
Output:
PASS ship-exempt-logged
PASS ship-exempt-in-pr-blocks
PASS floor-exempt-fixture-quiet
PASS floor-exempt-real-auth-still-hits
PASS floor-exempt-working-tree-ignored
PASS floor-exempt-never-kit-config
PASS floor-exempt-empty-match-rejected
PASS floor-exempt-data-loss-still-hits
PASS classify-files-exempt
PASS floor-paths
PASS ship-migration-blocks
PASS ship-no-spec-blocks
PASS ship-flip-gate-in-pr
Verdict: PASS
```

Whole suites touched by the diff:

```
Command: bash tests/test-lanes-data.sh
Exit: 0
Output:
67 PASS, 0 FAIL
Verdict: PASS

Command: bash tests/run-all.sh --changed origin/master
Exit: 0
Output:
run-all: all 56 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control

Mutation 1: the exemption filter blanks every path instead of the exempt ones.

```
Command: bash tests/test-lanes-data.sh floor-exempt-real-auth-still-hits floor-exempt-fixture-quiet
Exit: 1 (under mutation, RED expected)
Output:
  FAIL floor-exempt-real-auth-still-hits:  [src/auth/login.ts => ''] [lib/session.ts => '']
  PASS floor-exempt-fixture-quiet
Verdict: PASS
```

Mutation: `perl -pi -e 's/grep -nE -f "\$tmp\/exre" "\$tmp\/paths"/grep -nE "" "\$tmp\/paths"/' lib/classify/lane-classify.sh`. Restored with `git checkout HEAD -- lib/classify/lane-classify.sh`, green after restore (exit 0), run by `lib/gate/negctl.sh`.

Mutation 2: both read points take `HEAD` instead of the merge base.

```
Command: bash tests/test-lanes-data.sh floor-exempt-working-tree-ignored classify-files-exempt
Exit: 1 (under mutation, RED expected)
Output:
  FAIL floor-exempt-working-tree-ignored: A='full auth: experiments/qa-runner/cases/oracle/sd-login-locked.mjs' B=''
  FAIL classify-files-exempt: base exemption => 'normal' (want normal); branch-only => 'normal' (want full)
Verdict: PASS
```

Restored with `git checkout HEAD -- lib/classify/lane-classify.sh`, green after restore (exit 0), run by `lib/gate/negctl.sh`.

## Not proven

- The consumer repo's own `.kit.toml` entry: it ships there as its own full-lane PR.
- A broad entry crafted to dodge every canary path still exempts what it matches; the full-lane review of the `.kit.toml` change is the check on that.
- Hostile ERE complexity (catastrophic patterns) in a reviewed base file is not timed.
