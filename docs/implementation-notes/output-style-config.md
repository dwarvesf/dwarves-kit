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

## 2026-09-10 10:50 FEATURES.md regenerated in the same commit

The new test block mentions `SPEC-252`, which moved one row of the generated `docs/FEATURES.md` (`test-adopt.sh` joined the /kit:ship test list). Regenerated with `lib/registry/feature-registry.sh generate`; `tests/test-meta.sh` pins freshness.
