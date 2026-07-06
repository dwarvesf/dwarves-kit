# Proof of done: manifest-reconcile (SPEC-183, harness-ops sub-goal 04)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | Repo-root `kit.toml` is the shipped default (promoted from `kit.toml.example`, full status-tagged schema) | PASS | `git mv kit.toml.example kit.toml`; `tests/test-install-modules.sh` "repo-root kit.toml exists" + "kit.toml.example no longer exists" |
| AC2 | `install.sh` renders the install `kit.toml` FROM the repo-root default + `--with`, preserving the existing `[modules]` manifest write | PASS | `kit_render_install_toml()` in install.sh; 6 pre-existing `[modules]` NCs unchanged and green (spine-only, `--with`, un-opted-hook-absent, team_mode-reserved, unknown-module-error, additive-reinstall, `--prune`) |
| AC3 | The install-rendered file carries the FULL schema (`[ledger]`/`[mega]`/`[gate]`/`[features]`/`[team]`), not just `[modules]` | PASS | "chain-coherent" block, 10 section-presence assertions |
| AC4 | The resolver's kit-root resolution is confirmed coherent: prod (install-rendered) vs dev (repo-root direct) | PASS | "prod regime" + "dev regime" assertions (`kit_config_get modules.board` / `kit_config_get mega.wave_cap`) |
| AC5 | The hooks-only `kit.toml` lint stays green | PASS | STANDING ANTI-DRIFT LINT block, unchanged |
| AC6 | NEGATIVE CONTROL: the lint actually catches a hook that reads `kit.toml`, not vacuously green | PASS | "NC lint-load-bearing" block: a planted `fake-config-reader.sh` is caught by name; the untouched real hook is not false-flagged |
| AC7 | No regression: full existing suite + adjacent install/hook/meta tests stay green | PASS (37+452+7+3+49+679 = 1227/1227) | Regression section below |

**Total: 37/37 PASS in `tests/test-install-modules.sh` (13 new assertions), 0 FAIL. Adjacent suites: 1190/1190.**

## What changed (the 3-artifact chain)

Before this sub-goal, three artifacts touched config with no coherent relationship:

```
kit.toml.example (repo root)     install.sh                    kit-config.sh (resolver)
  full schema, never read   -->  writes ONLY [modules]    -->  reads ~/.claude/dwarves-kit/kit.toml
  (dead reference doc)           to the install location        (in prod: only ever saw [modules],
                                                                   every other section unreachable)
```

After:

```
kit.toml (repo root, was .example)         install.sh                      kit-config.sh (resolver)
  the shipped DEFAULT, full schema   -->    kit_render_install_toml():  --> prod: reads the install file
  (source of truth for every            copies repo-root verbatim,          (now the FULL schema)
   section's default)                     recomputes ONLY [modules]     --> dev: KIT_CONFIG_ROOT/DWARVES_KIT
                                           from --with                       pointed at the checkout reads
                                                                              THIS file directly
```

`install.sh` additions: `kit_toml_modules_section_true()` (section-scoped "which
modules are `true`" reader, replaces a file-wide grep that would now misfire on
other sections' legitimate `true` defaults) and `kit_render_install_toml()` (the
render itself). Same section-scoping principle applied to
`tests/test-install-modules.sh`'s `modules_section_true()` helper, for the
identical reason.

## Confirmation run (positive: current tree, `tests/test-install-modules.sh`)

Command: `bash tests/test-install-modules.sh`
Exit: 0

```
== NC chain-coherent: repo-root kit.toml -> install render -> resolver read ==
  PASS  repo-root kit.toml exists (promoted from kit.toml.example)
  PASS  kit.toml.example no longer exists (fully promoted)
  PASS  repo-root default carries section \[ledger\]
  PASS  install-rendered kit.toml carries section \[ledger\] (full schema, not modules-only)
  PASS  repo-root default carries section \[mega\]
  PASS  install-rendered kit.toml carries section \[mega\] (full schema, not modules-only)
  PASS  repo-root default carries section \[gate\]
  PASS  install-rendered kit.toml carries section \[gate\] (full schema, not modules-only)
  PASS  repo-root default carries section \[features\]
  PASS  install-rendered kit.toml carries section \[features\] (full schema, not modules-only)
  PASS  repo-root default carries section \[team\]
  PASS  install-rendered kit.toml carries section \[team\] (full schema, not modules-only)
  PASS  prod regime: resolver reads the INSTALL kit.toml (modules.board=true from --with board,stats)
  PASS  dev regime: resolver reads the REPO-ROOT kit.toml directly (mega.wave_cap=2, no install needed)

== NC lint-load-bearing: a hook that DOES read kit.toml is caught, not a vacuous green ==
  PASS  NC: lint catches a planted hook reading kit.toml (caught: .../fake-config-reader.sh)
  PASS  NC: lint does not false-positive the untouched real hook

== STANDING ANTI-DRIFT LINT: no hook reads kit.toml at runtime (record, not registry) ==
  PASS  no hooks/*.sh reads kit.toml (leaked: none)

== 37 passed, 0 failed ==
```

Full log: `/tmp/proof-run-183.log` (this run).

## Negative control (revert the change, same test file, must go RED)

The whole point of the "chain-coherent" block is that it is not trivially true;
checking the SAME new test file against the PRE-change tree (commit `d1c8eab`, the
branch point, where `install.sh` still wrote a `[modules]`-only manifest and the repo
root still had `kit.toml.example`, not `kit.toml`) makes 13 of the new assertions fail.

Command:
```
D=$(mktemp -d) && git worktree add -q --detach "$D" d1c8eab \
  && cp tests/test-install-modules.sh "$D/tests/test-install-modules.sh" \
  && (cd "$D" && bash tests/test-install-modules.sh)
```
Exit: 1

```
  FAIL  repo-root kit.toml exists (promoted from kit.toml.example)
  FAIL  kit.toml.example no longer exists (fully promoted)
  FAIL  repo-root default carries section \[ledger\]
  FAIL  install-rendered kit.toml carries section \[ledger\] (full schema, not modules-only)
  FAIL  repo-root default carries section \[mega\]
  FAIL  install-rendered kit.toml carries section \[mega\] (full schema, not modules-only)
  FAIL  repo-root default carries section \[gate\]
  FAIL  install-rendered kit.toml carries section \[gate\] (full schema, not modules-only)
  FAIL  repo-root default carries section \[features\]
  FAIL  install-rendered kit.toml carries section \[features\] (full schema, not modules-only)
  FAIL  repo-root default carries section \[team\]
  FAIL  install-rendered kit.toml carries section \[team\] (full schema, not modules-only)
  PASS  prod regime: resolver reads the INSTALL kit.toml (modules.board=true from --with board,stats)
  FAIL  dev regime: resolver reads the REPO-ROOT kit.toml directly (mega.wave_cap=2, no install needed)

== 24 passed, 13 failed ==
```

(The one surviving PASS, "prod regime", is expected: the OLD install.sh already wired
`--with board,stats` into `[modules]` correctly, just without the other sections. The
NC specifically targets the "full schema" and "dev regime bypasses install" claims,
which is exactly what was missing before.)

Full log: `/tmp/proof-nc-183.log` (this run).

## Regression (adjacent suites, unchanged code paths)

| Suite | Result |
|---|---|
| `bash lib/config/kit-config.sh selftest` | 6/6 PASS (resolver mechanics untouched by this spec) |
| `bash tests/test-hooks.sh` | 452/452 PASS |
| `bash tests/test-install-compat.sh` | 7/7 PASS |
| `bash tests/test-install-contract.sh` | 3/3 PASS |
| `bash tests/test-kit-foldin-hooks.sh` | 49/49 PASS |
| `bash tests/test-meta.sh` | 679/679 PASS |

## Reproduce

```
cd dwarves-kit
bash tests/test-install-modules.sh                 # 37/37, chain-coherent + lint-NC
bash lib/config/kit-config.sh selftest              # 6/6, resolver regression
bash tests/test-hooks.sh                            # 452/452
bash tests/test-install-compat.sh                   # 7/7
bash tests/test-install-contract.sh                 # 3/3
bash tests/test-kit-foldin-hooks.sh                 # 49/49
bash tests/test-meta.sh                             # 679/679
```
