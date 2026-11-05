# Proof of done: update-check

Module: `update_check` · Type: behavioral (new hook) · Contract: `lib/update-check/SPEC.md`

## Acceptance criteria

| # | Criterion | Met |
|---|---|---|
| A1 | A newer release prints one `systemMessage` naming latest, installed and the update command | yes (T1) |
| A2 | Equal, older, and every compare position (major, minor, patch, 2.10 vs 2.9) are silent or notify correctly | yes (T2) |
| A3 | Offline, garbage remote, garbage or missing installed VERSION, no curl or jq: exit 0, no output | yes (T3) |
| A4 | At most one fetch per 24h; a stale cache fetches again; a failed fetch keeps the cached latest | yes (T4) |
| A5 | `KIT_UPDATE_CHECK=0` and `modules.update_check = false` (via `anchor-root.sh`) are silent and write no cache | yes (T5) |
| A6 | Wired once in `hooks/hooks.json` and `settings.json`: SessionStart, matcher `startup`, timeout 5 | yes (T6) |
| A7 | Every surface `tests/test-modules-table.sh` pins agrees with the new table row | yes |

## Confirmation run-table

| Check | Command | Result |
|---|---|---|
| Hook test, hermetic | `bash tests/test-update-check-notice.sh` | **37 passed, 0 failed**, Exit: 0 |
| Module table pins | `bash tests/test-modules-table.sh` | **64 passed, 0 failed**, Exit: 0 |
| Install by module | `bash tests/test-install-modules.sh` | **67 passed, 0 failed**, Exit: 0 |
| Meta (docs, registry, lifecycle, plugin hooks) | `bash tests/test-meta-vmodel-dispatch.sh`, `test-meta-plugin-hooks.sh`, `test-meta-docs-registry.sh`, `test-config-registry.sh` | all green |
| Kit contract | `bash tests/test-kit-contract.sh` | green with this module's README, SPEC and proof |
| Real flow, live URL | hook via `anchor-root.sh`, default `raw.githubusercontent.com` URL | latest 2.3.0 cached, silent, 0.48s total, Exit: 0 |
| Real flow, newer release | same, `KIT_UPDATE_CHECK_URL=file://<tmp>/remote` holding `9.9.9` | notice printed, valid JSON (`jq -e .systemMessage` rc 0), Exit: 0 |
| NEGATIVE CONTROL 1 | flip the patch comparison to `-lt` | **2 FAIL** (`2.3.1 vs 2.3.0` silent, `2.3.0 vs 2.3.1` notice), restored with `git checkout --` to 37 passed |
| NEGATIVE CONTROL 2 | swap the operands of `semver_gt` | **16 FAIL** including the T1 newer case, restored to 37 passed |

Output:

```
$ bash tests/test-update-check-notice.sh | tail -1
== 37 passed, 0 failed ==

$ CLAUDE_PLUGIN_ROOT=$PWD KIT_UPDATE_STATE_DIR=$S/b KIT_UPDATE_CHECK_URL=file://$S/remote bash hooks/anchor-root.sh $PWD/hooks/kit-update-notice.sh </dev/null
{"systemMessage":"dwarves-kit 9.9.9 is available (installed: 2.3.0). Run: claude plugin marketplace update dwarves-marketplace && claude plugin update kit@dwarves-marketplace, then restart Claude Code."}
Exit: 0

$ (negative control 2) bash tests/test-update-check-notice.sh | grep -a 'FAIL\|passed'
  FAIL  stdout is valid JSON with a systemMessage
  FAIL  names latest and installed
  FAIL  installed 2.3.0, latest 2.3.1: notice
  ...
== 21 passed, 16 failed ==
```

Rollback: remove the `update_check` row from `lib/config/modules.tsv` and the SessionStart entry from `hooks/hooks.json` and `settings.json`; or set `KIT_UPDATE_CHECK=0`.
