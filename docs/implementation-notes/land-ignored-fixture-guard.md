# Implementation notes: land-ignored-fixture-guard

Deltas from the spec (`docs/specs/SPEC-394-land-ignored-fixture-guard.md`). Nothing here repeats what the spec states.

## Spec deltas

- **TASK-1 and TASK-2 share one commit.** AC10 in `tests/test-config-registry.sh` requires the "Root-only keys" table to equal the literal `kit_config_get_root` call sites. A registry row with no call site, or the reverse, goes red, so the knob, its registry rows, and the guard that reads it ship together.
- **`MANUAL.md` is a stub.** The root `MANUAL.md` is 11 lines and lists no refusals. The operator reference lives in `docs/MANUAL.md`, so the sentence went into its `/kit:wrap` section as a `Landing refusal` line. `docs/MANUAL.md` was not in the spec's `Touches` list; it is added there.
- **Test plan count.** TASK-2 said rows 1 to 22, but the table has 23 rows. The AC now says 1 to 23.
- **Row 4 split in two.** Row 4's new path-form built-ins (`tests/.cache`, `lib/*/bin/*-rs`) need a different touched scope than the `tools/x` caches, so they run as case `4b` with its own fixture. Both are named `4` and `4b` in the test output.
- **`KIT_CONFIG_OPERATOR` is a directory.** The resolver reads `$KIT_CONFIG_OPERATOR/kit.toml`. The four `ignored.bin` sections and the guard cases hand it a directory holding a `kit.toml`.
- **`.git/info` does not exist in a fixture clone.** `wrap-stub.sh` pins `GIT_TEMPLATE_DIR` to an empty dir, so row 12 creates `.git/info` before writing `exclude`.
- **Reads capture the exit code through `PIPESTATUS`.** `git diff -z` and `git status -z` pipe into `tr '\0' '\001'` (bash cannot hold a NUL, and a path may hold a newline). The git exit code comes from `PIPESTATUS[0]` inside the command substitution. `wrap.sh` runs `set -uo pipefail` with no `-e`, so this holds.
