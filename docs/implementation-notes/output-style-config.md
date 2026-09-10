# Implementation notes: output-style-config (SPEC-252)

Delta from the spec only; see `docs/specs/SPEC-252-output-style-config.md` for the design.

## 2026-09-10 10:40 a set value overwrites on every adopt run

**Context:** SPEC-192's module wiring re-computes on every adopt run. The statusLine merge in `install.sh` step 7 does the opposite (never overwrites an existing value).

**Decision:** Follow SPEC-192, not statusLine. A set `output.style` writes `.outputStyle` whenever the current value differs.

**Why:** "Configurable" means editing the key and re-running adopt changes the project. Never-overwrite would make the first adopt the only one that counts. The harness's `settings.local.json` already gives each person an override the kit never touches, so overwriting the shared project file takes nothing away from them.

**Alternatives:** an ownership marker next to the key (settings.json has no place for one on a scalar); a `--force` flag (one more thing to remember, for the common case).

**Impact:** an operator who set `outputStyle` by hand in the project `settings.json` and then set a different `[output] style` sees the kit value win. Documented in `output-styles/README.md`.

## 2026-09-10 10:42 install.sh symlinks, adopt copies

**Decision:** `install.sh` symlinks kit styles into `~/.claude/output-styles/` (mirrors how commands are linked); `adopt.sh` copies into the project (mirrors how skills are installed).

**Why:** a project checkout must not depend on a path outside the repo; a user-level link may, and a link keeps the user-level copy current on `git pull`.

**Open question:** an operator who already keeps `~/.claude/output-styles/adhd.md` as a real file (chezmoi-managed) gets "already present as a real file (not overwriting)" and two copies exist. The operator decides which one to keep; the kit does not delete.

## 2026-09-10 10:45 no install.sh test for the symlink step

**Decision:** the new `tests/test-adopt.sh` cases cover the adopt path; the `install.sh` symlink and uninstall steps are verified by the run-table (shellcheck, install-modules, install-contract) but carry no dedicated assertion.

**Why:** the existing install suites drive `install.sh` against a scratch `CLAUDE_DIR`; adding a style assertion there is a small follow-up, not a blocker for a step that mirrors the command-symlink loop line for line.

## 2026-09-10 11:20 operator-level default closes the install.sh gap

**Context:** adopt.sh step 6b writes `outputStyle` into an ADOPTED PROJECT's settings.json. Nothing wrote it for an operator who wants a style as their own default on every repo, adopted or not.

**Decision:** `install.sh` step 7b, right after the statusLine merge, resolves `output.style` operator-only (`kit_config_get`, but with `KIT_PROJECT_ROOT` pointed at an empty scratch dir so the project layer never applies) and sets `.outputStyle` in `$CLAUDE_DIR/settings.json` directly, following the same "overwrite when it differs" rule as adopt's write and the same path-traversal refusal.

**Why:** install has no per-project settings.json to write, and no repo to read `.kit.toml` from that means anything at install time (a stray nearby `.kit.toml` would be someone else's project config, not the operator's intent) -- pointing `KIT_PROJECT_ROOT` at an empty dir makes that explicit instead of relying on the caller's cwd happening to have no `.kit.toml`.

**Alternatives:** a new top-level `[operator]` config section (rejected, `output.style` already resolves operator > kit-root when the project layer is out of the picture, a second key would duplicate the same value); writing the key unconditionally on every install run even when unchanged (rejected, matches adopt's own idempotency contract, and the existing statusLine step already sets the "only write on a real change" precedent this step follows).

**Impact:** an operator with `[output] style = "adhd"` in `~/.config/dwarves-kit/kit.toml` gets `outputStyle: "adhd"` in their own `~/.claude/settings.json` on the next `install.sh` run, with no per-repo adopt step needed. `--uninstall` does not strip it back out; it is the operator's own setting.

## 2026-09-10 10:50 FEATURES.md regenerated in the same commit

The new test block mentions `SPEC-252`, which moved one row of the generated `docs/FEATURES.md` (`test-adopt.sh` joined the /kit:ship test list). Regenerated with `lib/registry/feature-registry.sh generate`; `tests/test-meta.sh` pins freshness.
