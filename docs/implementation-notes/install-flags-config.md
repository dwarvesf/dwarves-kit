# install-flags-config: decisions beyond the audit

- `--help`/`-h` is scanned across every argument before the `--uninstall` branch, so it never writes. Usage text lives in `kit_usage` in `install.sh`.
- The `*)` arm sits in the existing flag loop. Nothing before that loop writes, so exit 64 is write-free. `--uninstall` is only valid as the first argument (handled earlier); anywhere else it used to be ignored and run a full install, and now exits 64 with a note.
- Flags found in repo callers: `--with`, `--with=`, `--prune`, `--no-mods`, `--force-both`, `--uninstall`. All still accepted. `--no-mods` description is "skip registering the board pane mod" (read from the code).
- `probe_key_ref`: the task suggested `.kit.toml` for the maintainer's value. Not the right layer: `run-remote.sh` reads it with `kit_config_get_root`, which skips the project `.kit.toml` on purpose (an untrusted PR could set it). The maintainer value must go in `~/.config/dwarves-kit/kit.toml` under `[gauntlet]`; I did not touch that file (outside the project).
- The installed copy `~/.claude/dwarves-kit/kit.toml` still holds the old ref until `install.sh` re-renders it from the new default; a re-install then yields an empty ref.
- `run-remote.sh` default is now `""` (was a `<vault>` placeholder); the guard also rejects any `<...>` placeholder. It runs only after the `local` early exit, so local runs need no key.
- Lock file: no reader of `_meta/backlog-staging.md.lock` exists. The staging lock is `tmpdir/staging-<md5>.lock` (`lib/reflect/staging-format.py`). Old gauntlet transcripts under `docs/verification/gauntlet/` mention the path as history; left alone. The `git rm` rode in the install-flags commit because it was already staged.
- Lane: classifier says normal, suggests full; `kit.toml` is a hard path via `.kit.toml` `extra_hard_paths`, so the push gate may demand the full-lane phases. Only the build phase really ran here.
