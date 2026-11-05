# Verification -- ship-vendored-mods

`install.sh` loads five Claude Code mods (board-pane plus the vendored secrets-veil, memory-lens, loop-detective, context-inspector) from one list, skips a mod whose plugin name another `CLAUDE_CODE_PLUGIN_DIRS` entry already loads, and uninstalls only the kit's paths.

## Green run
```
Command: bash tests/test-install-mods.sh
Exit: 0
Output:
  PASS  a ~ entry with the same plugin name skips the kit copy
  PASS  a different folder name with the same manifest name skips the kit copy
  PASS  a manifest-less entry falls back to its folder name
  PASS  only the mods without a twin are registered, after the foreign entries
  PASS  uninstall leaves the foreign entries exactly as they were
  PASS  compat skips the checkout path of a mod that is already loaded
  PASS  the full install leaves the checkout's kit.toml byte for byte
  ---
  PASS=55 FAIL=0
Verdict: PASS
```

```
Command: for each of the five mod dirs: claude plugin validate <dir>; claude plugin test <dir>
Exit: validate 0 and test 0 for every mod
Output:
  board-pane        validate=0 test=0   56 pass 0 fail
  secrets-veil      validate=0 test=0    5 pass 0 fail
  memory-lens       validate=0 test=0   11 pass 0 fail
  loop-detective    validate=0 test=0   41 pass 0 fail
  context-inspector validate=0 test=0  102 pass 0 fail
Verdict: PASS (board-pane validate warns about a missing author, as it did before this change)
```

```
Command: bash tests/run-all.sh --changed --time
Exit: 0
Output:
  run-all: all 35 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## Negative control
```
Command: bash tests/test-install-mods.sh
Exit: 0 (green before mutation)
Output:
  PASS=55 FAIL=0

Mutation: a `return 1` as the first line of kit_mod_skip_dup in install.sh (the duplicate guard never fires)
Changed: install.sh
Exit: 1 (under mutation, RED expected)
Output:
  FAIL  a ~ entry with the same plugin name skips the kit copy
  FAIL  a different folder name with the same manifest name skips the kit copy
  FAIL  a manifest-less entry falls back to its folder name
  FAIL  only the mods without a twin are registered, after the foreign entries
  FAIL  a skipped mod is not copied
  FAIL  a re-run changes nothing
  FAIL  the kit entry for the twin is gone, the foreign one stays
  FAIL  compat skips the checkout path of a mod that is already loaded
  FAIL  compat registers the other four checkout paths
  PASS=46 FAIL=9

Restore: git checkout -- install.sh
Exit: 0 (green after restore, PASS=55 FAIL=0)
Verdict: PASS
```
The mutation was committed-state clean before it (the installer change was committed first), and `git status` was clean after the restore.

## Test plan coverage
| Behavior | Test |
|---|---|
| All five mods copied and registered in list order, tests and generated types left behind | `tests/test-install-mods.sh` fresh install section |
| Re-run adds nothing, unrelated entries and env keys survive | same file, re-run and shared-value sections |
| `--no-mods` skips all | same file, `--no-mods` section |
| Uninstall removes only kit paths and copies | same file, uninstall sections (full, compat, foreign twin) |
| Compat install registers the five checkout paths | same file, compat sections |
| Duplicate guard: `~` entry, manifest name vs folder name, folder-name fallback, later foreign twin, compat | same file, duplicate-guard sections |
| loop-detective report shows no `Failure:` line and no status row | `loop-detective/tests/report.test.ts`, `adapter.test.ts` |
| context-inspector export holds hashes for non-file targets | `context-inspector/tests/export.test.ts` |
| memory-lens trusts no repo store without a trusted-roots file | `memory-lens/tests/memory-lens.test.ts` |

## Not proven
- Live loading in a real Claude Code session: the tests use fixture homes and the mod runtime's mock engine, and `claude plugin validate` and `claude plugin test` do not start an interactive session.
- Hook order between secrets-veil and the other mods in `CLAUDE_CODE_PLUGIN_DIRS`: not tested, so loop-detective and context-inspector may see tool output before secrets-veil masks it (the Failure excerpt and the raw export targets were removed for that reason).
- The memory-lens and secrets-veil gating hooks have no `.catch`; `claude plugin validate` reports it for the audited copies and they are left as vendored.
- `tsc` was run on loop-detective and context-inspector in a scratch copy with the engine types, not through the checkout.
