# Proof of done: wrap step 0 stops main-checkout writes only

Spec: `docs/specs/SPEC-383-wrap-step0-scope.md` (its "Code review fold" section holds the review delta). Implementation deltas: `docs/implementation-notes/wrap-step0-scope.md`. Commit under test: `6029fd47`.

| Claim | AC | Proof | Verdict |
|---|---|---|---|
| `apply --no-pull` leaves HEAD and the working tree untouched on a behind checkout | AC1 | `tests/test-wrap-apply.sh` `no-pull:` cases | PASS |
| `apply --no-pull` carries no stray commits and does not move the default branch | AC2 | same suite, `no-pull ahead:` cases | PASS |
| `--no-pull --own` still removes an own merged worktree and its branch, HEAD unchanged | AC3 | same suite, `no-pull --own:` cases | PASS |
| `--no-pull` with `--pull-only` exits 64 naming the flag, both orders | AC4 | same suite | PASS |
| a feature-branch checkout keeps its local default ref under `--no-pull`; plain apply moves it | AC5 | same suite, control case | PASS |
| plain `apply --apply` still pulls | AC6 | existing pull cases, `tests/test-wrap-pull.sh` | PASS |
| the stray-line carry pushes nothing under `--no-pull` even with `autoland_carry` true; HEAD, index file and bytes unchanged | AC9 | `tests/test-wrap-carry.sh` `stray --no-pull:` cases | PASS |
| `merge --no-pull` skips a PR whose head the main checkout holds (CONFLICTING, clean, `--pr`, draft); a linked-worktree holder is not skipped; control is eligible | AC11 | `tests/test-wrap-merge-nopull.sh` | PASS |
| `apply --no-pull` without `--own` skips both local sweeps and keeps the origin sweep; with `--own` the origin sweep runs | AC12 | `tests/test-wrap-apply.sh` `no-pull, no --own` and origin cases | PASS |
| `commands/wrap.md` states the narrowed stop and every dependent sentence | AC7, AC8 | `tests/test-wrap-deploy.sh`, one assertion per sentence | PASS |
| `--help` still prints the last header line, cli suite green | AC10 | `tests/test-wrap-cli.sh` and `wrap.sh --help` tail | PASS |
| each new gate is load-bearing | AC1, AC2, AC4, AC9, AC11, AC12 | negative controls NC1 to NC8 below, each RED then restored | PASS |

## Green run

Command: `bash tests/test-wrap.sh` (the runner over every `tests/test-wrap-*.sh` suite)
Exit: 0, `test-wrap: all 2113 passed`

Per suite (each run alone, exit 0): apply 286, carry 145, merge 246, merge-nopull 17, deploy 176, cli 22, pull 202.

`bash tests/test-meta.sh` after regenerating `docs/FEATURES.md` with `feature-registry.sh check --fix` (the new spec shifted its counts): the one failing case was that freshness check.

## Negative control

Each block is negctl output run after the commits. The mutator is `docs/verification/wrap-step0-scope-negctl.py` (one exact-once mutation per name). NC5 and NC6 run against the dedicated `tests/test-wrap-merge-nopull.sh`: the signal-timing cases in `tests/test-wrap-merge.sh` failed intermittently after restore under negctl, so the `--no-pull` cases live in their own suite.

### NC1 the pull still runs under --no-pull (apply)

```
## Negative control (negctl)
Command: bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Mutation: python3 docs/verification/wrap-step0-scope-negctl.py nc1
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC2 the stray-commits move still runs under --no-pull (apply)

```
## Negative control (negctl)
Command: bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Mutation: python3 docs/verification/wrap-step0-scope-negctl.py nc2
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC3 the --pull-only conflict refusal is dropped (apply)

```
## Negative control (negctl)
Command: bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Mutation: python3 docs/verification/wrap-step0-scope-negctl.py nc3
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC4 the stray-line carry still pushes under --no-pull (carry)

```
## Negative control (negctl)
Command: bash tests/test-wrap-carry.sh
Exit: 0 (green before mutation)
Mutation: python3 docs/verification/wrap-step0-scope-negctl.py nc4
Changed: lib/wrap/wrap-carry.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-carry.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC5 merge --no-pull still re-merges a main-held PR (merge-nopull)

```
## Negative control (negctl)
Command: bash tests/test-wrap-merge-nopull.sh
Exit: 0 (green before mutation)
Mutation: python3 docs/verification/wrap-step0-scope-negctl.py nc5
Changed: lib/wrap/wrap-merge.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC6 merge --no-pull --pr still readies and merges a main-held draft (merge-nopull)

```
## Negative control (negctl)
Command: bash tests/test-wrap-merge-nopull.sh
Exit: 0 (green before mutation)
Mutation: python3 docs/verification/wrap-step0-scope-negctl.py nc6
Changed: lib/wrap/wrap-merge.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-merge.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC7 the unscoped branch sweep runs under --no-pull (apply)

```
## Negative control (negctl)
Command: bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Mutation: python3 docs/verification/wrap-step0-scope-negctl.py nc7
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC8 the carry scan refreshes the index again (carry)

```
## Negative control (negctl)
Command: bash tests/test-wrap-carry.sh
Exit: 0 (green before mutation)
Mutation: python3 docs/verification/wrap-step0-scope-negctl.py nc8
Changed: lib/wrap/wrap-carry.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-carry.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Unproven

The command prose (the stop, the `land` hold, the `--pr` draft rule) is model-executed. The doc tests pin the sentences, not the behavior. No live `/kit:wrap` run has met a foreign signal yet.

Validate round 2 ended NEEDS REVISION with its three criticals folded and no third round; the gate ledger holds the `validate` override. Code review (opus review-team lenses) returned APPROVE WITH FIXES; all six fixes are folded in the spec's "Code review fold" section.

## Rollback

The change is additive code plus a prose rewrite, with no persistent state, migration, or deploy. Roll back by reverting the branch's commits (`git revert` of the `fix(wrap)` commits). Reverting restores the old step 0 stop, under which the merge and own-worktree tidy stay stopped on a foreign signal.
