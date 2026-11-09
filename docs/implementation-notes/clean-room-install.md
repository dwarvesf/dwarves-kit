# clean-room-install: implementation notes

Branch `test/clean-room-install`. No spec: this is test work (lane `normal`), the brief is the contract.

## Goal

One test that proves a stranger can install the kit and use it with none of the maintainer's setup, plus the operator-layer fence that keeps the rest of the suite from reading the host.

## Scope and honest limits

- Covers the bash path (`install.sh`). The plugin path needs a running Claude Code to load `.claude-plugin/`, so no shell test can cover it. `commands/onboard.md` and `/kit:adopt` are model-driven; the test drives the scripts they call (`lib/onboard-detect.sh`, `lib/adopt.sh`), which are the scriptable forms.
- The repo is public (`gh repo view dwarvesf/dwarves-kit` says `PUBLIC`). The CI change adds no runner: `tests/run-all.sh --all` already collects the new suite by glob, so `.github/workflows/test.yml` needs no edit.
- The Docker room in `tests/gauntlet/cleanroom/` is untouched. It is heavier and not wired into CI. The new test is the cheap shell-level version.

## Design

- Sandbox root `$T`: `home/` (fake HOME), `repo/` (project), `remote.git` (bare, so `origin/HEAD` resolves for ship-gate), `tmp/` (TMPDIR), `bin/` (symlinks to bash, jq, git).
- Every command runs under `env -i` with only `HOME`, `PATH`, `TMPDIR`, `KIT_CONFIG_OPERATOR` (a path that does not exist). No `XDG_*`, no `GH_TOKEN`, no `OP_*`.
- PATH is the symlink dir plus the system dirs. `op` and `direnv` must not resolve; `gh`, which Ubuntu runners ship in `/usr/bin`, may exist but must not be authenticated.
- Sequence: install, detect, adopt (check, dry-run, real, idempotent re-run), commit and push the adoption to the toy default branch (the ship-gate reads `[gate]` at the merge base), a normal-lane run (start, check red, record gates, check green), ship-gate through its hook entry with a push payload (blocked, then allowed), `config seams` and `--check`.
- One named function, `assert_writes_land_only_in`, holds the "writes land only in allowed dirs" rule. Today it checks (1) the sandbox root holds nothing but the allowed entries and (2) no file under the real HOME's kit dirs carries the run's unique token. The data-root work tightens it by changing the allowed list in one place.
- `assert_no_host_leak` scans captured output and the generated config files for `tieubao`, `han-ws`, `ops-toolkit`, `op://` and the real user's home. The kit checkout path is stripped first: it is the kit's own location, not host config.
- Both assertion functions are exercised against planted failures inside the test (a stray entry, a tokened file in a fake canary dir, a leak string), so a broken guard shows up as a red case.

## Delta

(filled as the work lands)
