# Verification -- audit-trust-boundaries

Four trust-boundary fixes from a security audit: secrets-guard resolves symlinks before the ALLOW list, ship-gate runs only the kit's own registry and doc-projection scripts, board sync reads the Multica URL and token ref (and the observe push URL) from operator config only, and adopt plus session hooks refuse repo symlinks.

## Green run
```
Command: bash tests/test-hooks.sh; bash tests/test-symlink-guard.sh; bash tests/test-sync-dispatch.sh; bash tests/test-registry-freshness-guard.sh; bash tests/test-config-registry.sh; bash tests/test-meta-docs-registry.sh; bash tests/test-wrap-adopt.sh; bash tests/test-harvest-parity.sh; python3 lib/bench/tests/test_dashboard.py
Exit: 0
Output:
test-hooks:                    Passed: 815 / 815
test-symlink-guard:            PASS=21 FAIL=0
test-sync-dispatch:            10/10 passed
test-registry-freshness-guard: PASS=15 FAIL=0
test-config-registry:          60/60 passed
test-meta-docs-registry:       Passed: 120 / 120
test-wrap-adopt:               all 210 passed
test-harvest-parity:           171 passed, 0 failed
test_dashboard.py:             PASSED 13/13
Verdict: PASS
```
A normal push of a clean adopted repo still passes the gate: `tests/test-ship-gate-*.sh` and `tests/test-registry-freshness-guard.sh` (cases 6, 7, 8, 10) were green in `bash tests/run-all.sh --changed --time` (93 suites).

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "<hooks + symlink-guard + sync-dispatch + registry-freshness + dashboard suites>" "git checkout origin/master -- <the ten fixed source files>"
Exit: 1 (under mutation, RED expected)
Output:
    === Results ===
    Passed: 814 / 815
    Failed: 1
Verdict: PASS
```
Reverting the ten fixed files to origin/master turns the secrets-guard case red (the other suites chain after it and were not reached). Per suite, with the old code of each fix alone: `test-symlink-guard.sh` 9 of 21 NOT ok, `test-registry-freshness-guard.sh` 3 NOT ok, `test-sync-dispatch.sh` 5 of 10 FAIL, `test_dashboard.py` AssertionError, `test-wrap-adopt.sh` case 40 FAIL. The tree was restored by negctl and re-run green.

## Rollback
Revert the merge commit. No data, schema or config is migrated. Operator note: `sync.multica_url` and `sync.multica_token_ref` must now live in the operator `kit.toml` (`~/.config/dwarves-kit/kit.toml`); a project `.kit.toml` value is ignored with a stderr note. Multica is not in any current `apps` list.

## Not proven
- The installed copy under `~/.claude/dwarves-kit` was not exercised after merge; it updates through the kit's install path.
- secrets-guard still allows a symlinked example file when `realpath` is missing from PATH (the lexical fallback); not changed here.
- A symlink inside the project root is refused by adopt too (for example `CLAUDE.md` pointing at `AGENTS.md`); adopt exits 1 naming the path.
- `rewrite()` in staging-format.py and a symlinked parent of a staging file are not covered by the `O_NOFOLLOW` change.
