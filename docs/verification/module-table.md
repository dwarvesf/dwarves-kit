# Proof of done: one module table and a smaller default install

`install.sh` and `lib/adopt.sh` now read one table, `lib/config/modules.tsv`, instead of two private ones. A fresh install wires the spine plus the core module (`board`). `install.sh` refuses to wire hooks next to the kit plugin, and `lib/adopt.sh` wires no per-repo hooks there. Closes drift row 43 and the plugin-plus-bash half of the "Consumer wiring gaps" risk.

## Confirmation runs

| # | Check | Command | Exit | Verdict |
|---|---|---|---|---|
| 1 | Table, `kit.toml`, registry, both manifests agree | `bash tests/test-modules-table.sh` | 0 | PASS (59/59) |
| 2 | Default install = spine + board; existing install keeps its set; `--with`, `--prune`, migration | `bash tests/test-install-modules.sh` | 0 | PASS (49/49) |
| 3 | Plugin machine: refusal, `--with` ignored, roster-only plugin, mode `both`, `--force-both` | `bash tests/test-install-compat.sh` | 0 | PASS |
| 4 | Adopt reads the table, wires the modules it used to miss, skips hooks on a plugin machine | `bash tests/test-adopt.sh` | 0 | PASS (62/62) |
| 5 | One detector; roster-only plugin; install and adopt call it | `bash tests/test-onboard-detect.sh` | 0 | PASS (22/22) |
| 6 | Registry completeness reads the table | `bash tests/test-config-registry.sh` | 0 | PASS (60/60) |
| 7 | Bulk adopt, driver stubbed, machine independent | `bash tests/test-wrap-adopt.sh` | 0 | PASS (207/207; the master baseline passes 207/207 too) |
| 8 | Hook behavior | `bash tests/test-hooks.sh` | 0 | PASS (826/826) |
| 9 | Stand-in kits carry the table and detector | `bash tests/test-install-lib-copy.sh`, `bash tests/test-install-self-symlink.sh` | 0 | PASS |
| 10 | Contract lint over the module list | `bash tests/test-kit-contract.sh` | 0 | PASS (25/25) |
| 11 | Neighbours: gate opt-in/out, config seams, boundary lint, config, wrap scan | `bash tests/test-gate-opt-in.sh` and five more | 0 | PASS |
| 12 | NC1 module table, event swapped | `negctl.sh --at HEAD` on `test-modules-table.sh` | 1 then 0 | RED then green |
| 13 | NC2 plugin refusal off | `negctl.sh --at HEAD` on `test-install-compat.sh` | 1 then 0 | RED then green |
| 14 | NC3 core added on every re-run | `negctl.sh --at HEAD` on `test-install-modules.sh` | 1 then 0 | RED (47/49) then green |
| 15 | NC4 adopt plugin skip off | `negctl.sh --at HEAD` on `test-adopt.sh` | 1 then 0 | RED (60/62) then green |
| 16 | After merging master (which carries #992) | `bash tests/test-modules-table.sh` and a default install on the merge | 0 | PASS (59/59; installed hooks equal the table) |

## Green run

```
Command: bash tests/test-modules-table.sh
Exit: 0
Output:
  == T3 settings.json and hooks/hooks.json agree with the table ==
    PASS  settings.json: every hook is in one module under its event, every table hook is wired (no problems)
    PASS  hooks/hooks.json (the plugin manifest) agrees too (no problems)
  == T4 install.sh and adopt.sh keep no table of their own ==
    PASS  install.sh defines no kit_module_hooks / kit_module_clis function
    PASS  lib/adopt.sh sources lib/config/modules.sh
  == 59 passed, 0 failed ==
Verdict: PASS
```

```
Command: bash tests/test-install-modules.sh
Exit: 0
Output:
    PASS  default install wires exactly spine + board's hooks (expected from the table: ...)
    PASS  default install: only board is recorded true in kit.toml [modules] (got: board)
    PASS  a plain re-run on a spine-only install stays spine-only (board is not added)
  == 49 passed, 0 failed ==
Verdict: PASS
```

```
Command: bash tests/test-install-compat.sh
Exit: 0
Output:
  ok   plugin machine: install says it refused to wire hooks
  ok   plugin machine: --with is named as ignored
  ok   roster-only plugin: took the compat branch
  ok   mode both: install warns the hooks already fire twice and names the fix
  ok   --force-both wires the spine hooks next to the plugin
  PASS: install compat
Verdict: PASS
```

```
Command: bash tests/test-adopt.sh
Exit: 0
Output:
  ok - fresh adopt seeds exactly the module table's modules (incl. money_gate, prose_rag, worktree, sync; no bridge)
  ok - --with money_gate,prose_rag wires money-gate.sh and prose-rag.sh (modules the old adopt table did not know)
  ok - plugin machine: .kit.toml records the modules, no project settings.json is written, adopt names why
  PASS=62 FAIL=0
Verdict: PASS
```

## Negative control

Each control ran through `lib/gate/negctl.sh --at <HEAD sha>`, which mutates a throwaway export of the commit and leaves this worktree alone.

```
Command: bash tests/test-modules-table.sh
Mutation: perl -pi -e 's/PreToolUse:board-row-gate\.sh/SessionStart:board-row-gate.sh/' lib/config/modules.tsv
Exit: 1
Output:
    FAIL  NC: the real table is not flagged by the same check (no vacuous pass)
  == 56 passed, 3 failed ==
Restore: git checkout HEAD -- lib/config/modules.tsv
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash tests/test-install-compat.sh
Mutation: perl -pi -e 's/plugin\|both\) KIT_PLUGIN_PRESENT=1/plugin|both) KIT_PLUGIN_PRESENT=0/' install.sh
Exit: 1
Output:
  <no output>   (the suite runs under set -e; the full install it now reaches exits non-zero)
Restore: git checkout HEAD -- install.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash tests/test-install-modules.sh
Mutation: perl -pi -e 's/\{ \[ ! -f "\$KIT_TOML" \] \|\| \[ -L "\$KIT_TOML" \]; \}/true/' install.sh
Exit: 1
Output:
  == 47 passed, 2 failed ==
Restore: git checkout HEAD -- install.sh
Exit: 0 (green after restore)
Verdict: PASS
```

```
Command: bash tests/test-adopt.sh
Mutation: perl -pi -e 's/plugin\|both\)$/plugin_disabled)/' lib/adopt.sh
Exit: 1
Output:
  PASS=60 FAIL=2
Restore: git checkout HEAD -- lib/adopt.sh
Exit: 0 (green after restore)
Verdict: PASS
```

What each mutation broke, confirmed by hand where the captured tail does not name it. NC1 moved board-row-gate to the wrong event, so the table and `settings.json` disagree. NC2 made install treat a plugin machine as a bash machine, so it wired hooks. NC3 made every re-run add the core set: a pruned install re-run with that mutation wired `board-row-gate` and recorded `board = true`, which the real code does not. NC4 made adopt ignore the plugin, so a plugin machine got per-repo hooks. All four were restored from the commit and the suites went green again.

## Not proven

- `hooks/hooks.json`, the plugin manifest, still registers every hook whatever the module choice. The smaller default applies to the bash install and to adopt, not to the plugin.
- No run on a real plugin install through Claude Code; the plugin cache and roster are fixtures.
- The table's per-module `core` flag is a fresh-install default, not a lock: a per-project `.kit.toml` can turn `board` off, and `install.sh --prune` trims it.
