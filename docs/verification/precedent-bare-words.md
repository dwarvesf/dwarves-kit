# Proof of done: precedent find bare-word args + extensionless script indexing

## Claim

1. `lib/precedent/precedent.sh` `cmd_find` accepts unquoted bare words in a `find` call.
   Extra positional words fold into the description instead of erroring; a lone
   digit-only extra word still sets the legacy `[max]` override.
2. `lib/precedent/inventory.py` `scan_repo_tools` indexes a tool's top-level
   extension-less executable (not only `.sh`/`.py`), matching the house convention
   that launchd launchers carry no extension.

## Green run

```
$ bash tests/test-precedent.sh
...
== summary ==
  69/69 passed
Exit: 0
```

Manual repro of the reported bug, against a real repo:

```
$ bash bin/precedent find --surface inventory --quiet mini run \
    --repo-root /Users/tieubao/workspace/tieubao/ops-toolkit
# precedent inventory: mini run
...
## tools
  tools/mac-mini-substrate/mini-run  , mini-run: run a LOCAL script on the Mac Mini and get its real exit status.
  ...
precedent: N inventory hits in M sections; top: tools
Exit: 0
```

Before the fix this call died with `inventory.py: error: argument --limit: invalid
int value: 'run'` (the second bare word was forced into the legacy `[max]`
positional and handed to `--limit`).

`tools/mac-mini-substrate/mini-run` itself only surfaces once indexed; confirmed by
name alone:

```
$ bash bin/precedent find --surface inventory --quiet "mini-run" \
    --repo-root /Users/tieubao/workspace/tieubao/ops-toolkit
## tools
  tools/mac-mini-substrate/mini-run  , mini-run: run a LOCAL script on the Mac Mini and get its real exit status.
```

Note: the coordinator's exact 4-term repro query
(`"mini-run scratch script Mini"`) still returns 0 hits for `mini-run`, but not
because of this bug: `score()` is a strict AND across every query term (see the
existing "AND semantics" test case), and the literal word "scratch" never appears
in `mini-run`'s name or header comment. Dropping it
(`"mini-run script Mini"`) surfaces the file as shown above.

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-precedent.sh
Exit: 0 (green before mutation)
Mutation: git checkout HEAD~1 -- lib/precedent/precedent.sh lib/precedent/inventory.py
Changed: lib/precedent/inventory.py, lib/precedent/precedent.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/precedent/inventory.py lib/precedent/precedent.sh
Exit: 0 (green after restore)
Verdict: PASS
```

`HEAD~1` is the pre-fix commit (`e8a0fa3`, the branch's merge-base with master).

## Reproducible

Re-running `bash tests/test-precedent.sh` from a clean checkout of this branch
reproduces the green 69/69 verdict above.

## Verdict: PASS
