# Proof of done: wrap step 0 stops main-checkout writes only

Spec: `docs/specs/SPEC-383-wrap-step0-scope.md`. Implementation deltas: `docs/implementation-notes/wrap-step0-scope.md`. Commit under test: `38fb8b9b`.

| Claim | AC | Proof | Verdict |
|---|---|---|---|
| `--no-pull` leaves HEAD and the working tree untouched on a behind checkout | AC1 | `tests/test-wrap-apply.sh` `no-pull:` cases | PASS |
| `--no-pull` carries no stray commits and does not move the default branch | AC2 | same suite, `no-pull ahead:` cases | PASS |
| `--no-pull --own` still removes an own merged worktree and its branch, HEAD unchanged | AC3 | same suite, `no-pull --own:` cases | PASS |
| `--no-pull` with `--pull-only` exits 64 naming the flag, both orders | AC4 | same suite | PASS |
| a feature-branch checkout keeps its local default ref under `--no-pull`; plain apply moves it | AC5 | same suite, control case | PASS |
| plain `apply --apply` still pulls | AC6 | existing pull cases, `tests/test-wrap-pull.sh` | PASS |
| the carry never autolands under `--no-pull` with `autoland_carry` true | AC9 | `tests/test-wrap-carry.sh` `autoland --no-pull:` cases | PASS |
| `commands/wrap.md` states the narrowed stop and every dependent sentence | AC7, AC8 | `tests/test-wrap-deploy.sh`, one assertion per sentence | PASS |
| `--help` still prints the last header line, cli suite green | AC10 | `tests/test-wrap-cli.sh` and `wrap.sh --help` tail | PASS |
| each new gate is load-bearing | AC1, AC2, AC4, AC9 | negative controls NC1 to NC4 below, each RED then restored | PASS |

## Green run

Command: `bash tests/test-wrap.sh` (the runner over every `tests/test-wrap-*.sh` suite)
Exit: 0, `test-wrap: all 2072 passed`

Per suite after the change: apply 272, carry 143, deploy 168, cli 22, pull 202 (each run alone, exit 0).

## Negative control

Each block is negctl output, run after the commit. The mutator is `docs/verification/wrap-step0-scope-negctl.py` (one exact-once mutation per name).

### NC1 the pull still runs under --no-pull

```
## Negative control (negctl)
Command: bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Mutation: python3 mut.py lib/wrap/wrap-apply.sh '"-- pull:"
  if [ "$NO_PULL" = 1 ]; then' '"-- pull:"
  if [ "$NO_PULL" = 99 ]; then'
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC2 the stray-commits move still runs under --no-pull

```
## Negative control (negctl)
Command: bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Mutation: python3 mut.py lib/wrap/wrap-apply.sh '    if [ "$NO_PULL" = 1 ]; then
      echo "-- stray commits:"' '    if [ "$NO_PULL" = 99 ]; then
      echo "-- stray commits:"'
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC3 the --pull-only conflict refusal is dropped

```
## Negative control (negctl)
Command: bash tests/test-wrap-apply.sh
Exit: 0 (green before mutation)
Mutation: python3 mut.py lib/wrap/wrap-apply.sh '  if [ "$PULL_ONLY" = 1 ] && [ "$NO_PULL" = 1 ]; then' '  if [ "$PULL_ONLY" = 99 ] && [ "$NO_PULL" = 1 ]; then'
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

### NC4 the carry autolands under --no-pull

```
## Negative control (negctl)
Command: bash tests/test-wrap-carry.sh
Exit: 0 (green before mutation)
Mutation: python3 mut.py lib/wrap/wrap-carry.sh '  [ "$NO_PULL" != 1 ] || return 1' '  :'
Changed: lib/wrap/wrap-carry.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-carry.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Unproven

The command prose (the stop, the dry-run protocol, the `land` hold, the `--pr` eligible-only rule) is model-executed. The doc tests pin the sentences, not the behavior. No live `/kit:wrap` run has met a foreign signal yet. The re-merge of a CONFLICTING PR held by the main checkout has no verb gate (accepted residue, named in the spec).

Validate round 2 ended NEEDS REVISION with its three criticals folded and no third round; the gate ledger holds the `validate` override.

## Rollback

The change is additive code plus a prose rewrite, with no persistent state, migration, or deploy. Roll back with `git revert 38fb8b9b` (the code, tests, and `commands/wrap.md`). Reverting restores the old step 0 stop, under which the merge and own-worktree tidy stay stopped on a foreign signal.
