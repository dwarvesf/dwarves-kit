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

### Findings the first clean-room run surfaced
- The shipped `kit.toml` comments named `ops-toolkit` twice (the `learning_ledger` and `memory_tidy` rows). Every install copies that file into a stranger's `~/.claude/dwarves-kit/`. Both comments now say "the operator's own repo" and "your own tooling repo". Other `ops-toolkit` mentions remain in code comments and docs (`install.sh`, `lib/config/module-registry.md`, `lib/mega/mega.sh`, `lib/goal/megagoals.sh`, `docs/verification/README.md`). They are not config a stranger reads as settings, so the test scans only generated config and command output. Cleaning the rest is a docs pass, left alone here.
- The ship-gate reads `[gate]` from the merge base with the remote default branch. Adopting a repo and not landing the adoption on the default branch leaves every gate off (`OFF-BY-CONFIG` in the hook log). The test commits the adoption and sets `refs/remotes/origin/trunk` to match, which is what a merged adoption PR does. A stranger who adopts and then pushes a feature branch with the adoption still on it gets no gate. That is existing behavior, not changed here.
- The ship-gate refuses fixture author identities (`.test`, `example.com`, `t@t.dev`). The toy repo uses a `users.noreply.github.com` address.
- `op://` appears in shipped docs as `op://<vault>/...` placeholders. The leak scan counts `op://` only when a vault name follows.
- The test runs `git` without pushing: a local remote-tracking ref stands in for `origin/trunk`. The operator's branch guard and the live ship-gate hook both refuse a literal `git push` to a default branch even inside a throwaway sandbox, so the test avoids one.

### Hook for the data-root work
`ALLOWED_WRITE_DIRS` (one line) and `assert_writes_land_only_in` in `tests/test-clean-room.sh`. Today the allowed list is the whole sandbox HOME. The data-root branch narrows that entry to the kit data root plus the install-owned dirs. The function walks every path under the sandbox, so a state file landing outside the narrowed list fails by name. `real_home_canaries` lists the real-HOME dirs it watches; the data-root branch adds its new root there.

### Operator layer
- 49 suites reached the resolver by name (kit-config, `bin/config`, adopt, wrap, gate-ledger, lane data, hook-module) with no pin of their own. `tests/test-wrap.sh` was not one of them: it pins through `tests/lib/wrap-stub.sh`, and the guard follows a sourced `tests/lib` helper.
- Sensitivity scan: each of those suites ran twice on the maintainer's host, once with the real operator file and once pinned. No suite changed its result because of the operator file today (one wrap suite timed out under load in the real-operator run and passed pinned; load, not the file). So today the pin is prevention, not a repair. The next knob someone sets in their operator file would have broken them, as `adopt.single_source` broke test-adopt.
- Fix, three layers: (1) each of the 49 suites exports `KIT_CONFIG_OPERATOR` to a path that does not exist, right after its `set -` line; (2) `tests/run-all.sh` and `bin/test-affected` export it for every suite they start, which fences an indirect reach a name match cannot see; (3) `tests/test-operator-pin.sh` fails a suite that reaches the resolver with no pin, and fails a runner that stops pinning.
- Guard false-alarm surface: the reach test is a name match, so a suite that only mentions `adopt.sh` in a string is flagged until it pins (one line). Exemption is `# operator-layer: unpinned-ok <reason>` in the suite. A comment mentioning the variable does not count as a pin.
- Not covered: a suite that reaches the resolver only through a binary the pattern does not name. Layer 2 covers it when run by a runner; a bare `bash tests/test-x.sh` of such a suite stays unpinned.

### CI
`.github/workflows/test.yml` is untouched. It runs `bash tests/run-all.sh --all`, which collects `tests/test-*.sh` by glob, so both new suites run on the existing `ubuntu-latest` and `macos-latest` matrix. The repo is public (checked with `gh repo view`), so those runners cost nothing and the private-repo runner rule does not apply. No new runner type.
