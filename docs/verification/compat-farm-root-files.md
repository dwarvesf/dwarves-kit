# Compat farm carries kit.toml and VERSION

`lib/config/kit-config.sh` resolves the kit-root `kit.toml` from `~/.claude/dwarves-kit` by default, and `lib/gate/gate-ledger.sh` reads `VERSION` from the same root. The plugin-compat install linked only `bin lib hooks WORKFLOW.md AGENTS.md` plus two docs, so on a compat machine 11 kit-root keys (`sync.*`, `team.*`) resolved unset and ledger records carried an empty kit version. `install.sh` now links both files.

| Run | Command | Exit | Verdict |
|---|---|---|---|
| Green | `bash tests/test-install-compat.sh` | 0 | PASS: `PASS: install compat`, new `kit.toml` and `VERSION` symlink checks ok |
| Negative control | `bash lib/gate/negctl.sh "$PWD" "bash tests/test-install-compat.sh" "sed -i '' 's/ kit.toml VERSION / /' install.sh"` | 1 under mutation, 0 after restore | PASS: `Verdict: PASS` |
| Siblings | `tests/test-install-self-symlink.sh`, `tests/test-install-plugin-detect.sh` | 0, 0 | PASS |
| Live key diff before the fix | every key in `kit.toml`, farm default root vs `KIT_CONFIG_ROOT=<checkout>` | n/a | 11 of 100 keys differed, all `sync.*` and `team.*` |

Rollback: revert the commit; the two links become inert extra symlinks on machines that already ran the installer.
