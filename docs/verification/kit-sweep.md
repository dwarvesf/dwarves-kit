# Proof of done: anchor-root honors the module choice, plus the doc and design sweep

## What changed

`hooks/anchor-root.sh` skips a hook whose module is off, so a plugin install (whose `hooks/hooks.json` registers every hook) honors `[modules]`. The lookup is `lib/config/hook-module.sh`: one awk pass over `lib/config/modules.tsv` and the project, operator and kit-root `kit.toml`, with the table's default column last. The spine, an unlisted hook and a missing table always run. Also: `_refs_block` gets a test suite, the ship-gate and money-gate headers state what the hooks really do, the docs the six slices could not reach are corrected, and `docs/SYSTEM-DESIGN.md` (rev B) and `docs/design/kit-uml.html` follow the code.

## Gate table

| Claim | Evidence |
|---|---|
| a hook of an off module exits 0 without running; an on module runs | `tests/test-anchor-module-gate.sh` cases for default, kit-root, operator and project layers |
| precedence matches `kit_config_get` | the parity cases in the same suite |
| the spine never skips, an unlisted hook runs, a missing table runs | spine, unlisted and missing-table cases |
| every `hooks.json` hook is in the module table | the last case of the suite |
| `_refs_block` refuses an unaccountable push in an adopted repo and passes elsewhere | `tests/test-ship-gate-refs-block.sh` |
| no hook names the config files, the codex pin is fresh, the hard-claim meta test holds | `test-gate-opt-out`, `test-install-modules`, `test-codex-hooks`, `test-meta-hard-claims` |
| both new suites go RED when the code is broken | negative controls below |

## Run table

```
Command: bash tests/test-anchor-module-gate.sh
Exit: 0
Output: Results: 39 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/test-ship-gate-refs-block.sh
Exit: 0
Output: Results: 11 passed, 0 failed
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed   (94 suites)
Exit: 1
Output: FAILED test-codex-hooks (ship-gate trust pin stale after the header edit), test-outcome-emit-sweep (49 of 51, an unpaired outcome bracket in commands/debug.md, fails the same way on master per the module-table slice).
        TIMED OUT at the 300 s ceiling: test-adopt, test-ship-gate-impl-notes.
Re-runs alone after `bash lib/codex/repin.sh` and `lib/adopt/known-hashes.sh`: test-codex-hooks 94 passed 0 failed; test-adopt PASS=63 FAIL=0; test-ship-gate-impl-notes 17 ok.
        Earlier single runs: test-hooks 813 of 813, test-install-modules 49 of 49, test-gate-opt-out ALL PASS, test-config-registry 60 of 60, test-modules-table 62 of 62, test-meta-hard-claims 25 of 25, test-meta-plugin-hooks 54 of 54.
Verdict: PASS
```

## Negative control

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-anchor-module-gate.sh" "<turn the skip's exit 0 into true in hooks/anchor-root.sh>"
Exit: 1 (under mutation, RED expected)
Output: Results: 23 passed, 5 failed
Restore: git checkout HEAD -- hooks/anchor-root.sh
Exit: 0 (green after restore, 39 passed)
Verdict: PASS
```

```
Command: bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-refs-block.sh" "<turn exit 2 into exit 0 inside _refs_block in hooks/ship-gate.sh>"
Exit: 1 (under mutation, RED expected)
Output: Results: 4 passed, 7 failed
Restore: git checkout HEAD -- hooks/ship-gate.sh
Exit: 0 (green after restore, 11 passed)
Verdict: PASS
```

## Review

One read-only `kit:code-reviewer` lens on the wrapper and lib script returned FIX THEN SHIP. Applied: `${0%/*}` instead of two `dirname` forks, empty config files skipped, tests for prefix keys, CRLF, an empty file, a path with a space, stdin passthrough, one-module-per-hook and the spine fast path against the table row. Recorded as a decision: the project layer wins, as `kit_config_get` does (header of `lib/config/hook-module.sh`).

## Not proven

- The wrapper cost per hook call was timed by hand only (about 20 ms for a non-spine hook on a laptop under load), not budgeted by a test.
- The "parser gave no answer" branch of `_refs_block` needs a missing parser and is not driven.
- The rebuilt design set was read sheet by sheet by eye (hooks, board, gates, planes, board-row and queue-row sheets); no automated layout check ran beyond the build's own error sheet, which is empty.
- `test-outcome-emit-sweep` still fails on an unpaired outcome bracket in `commands/debug.md`; it is outside this change.
