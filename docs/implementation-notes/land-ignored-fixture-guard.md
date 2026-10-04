# Implementation notes -- land-ignored-fixture-guard

Builder-level points for `docs/specs/SPEC-394-land-ignored-fixture-guard.md`, carried from validate round 1 and from the grounding samples. Nothing here repeats what the spec already states.

## The git shim must fail only the guard's own call shape

- Context: rows 17 to 19 stub a failing `git status`, `git diff --name-only`, or `git merge-base`. `cmd_land` also calls `git status` (the dirty check and `_land_tidy`) and `merge-base` (`proof_base`, and possibly `_merge_proof`).
- Decision/Change: match the shim on the full argv shape the guard uses (`status --porcelain -z --ignored=matching`, `diff --name-only -z --no-renames`). Otherwise exec `REAL_GIT_BIN`. For row 19, failing every `merge-base` is fine, but assert the guard's own message ("the merge base"), not only the exit code, because an earlier step may refuse first for an unrelated reason.
- Why: a shim that fails every `status` trips the dirty check first. That row would pass with the guard deleted, which is a vacuous test.

## Pin both global-excludes sources in the test section

- `GIT_CONFIG_GLOBAL=<fixture file>` alone still lets git read `$XDG_CONFIG_HOME/git/ignore` (sampled). Set `XDG_CONFIG_HOME` to an empty fixture dir too. Otherwise the operator's `~/.gitignore` (`.DS_Store`, `.env`, `.env.*`) leaks into the fixtures, and a test can pass or fail by host.
- Run `wrap land` with the worktree as the cwd. The knob reader must never pick up the kit checkout's own config by accident.

## Splitting and matching the allow list

- Split the value under `set -f` (or `read -ra` with `set -f` around it). Restore the caller's state after the split; `cmd_land` relies on globbing nowhere else, but the sourced `wrap.sh` may.
- Match with `case "$x" in $glob)`, with the pattern unquoted on purpose. `x` is the last component for slash-free entries, each leading run of components for path entries, and for trailing-`/` entries any non-last component equal to the name (the entry with its `/` stripped).
- Secret-shape matching is case-insensitive: lower-case the basename first (`tr 'A-Z' 'a-z'`, as `cmd_land` already does for logins), then `case`.

## Reading `-z` status records

- Each record is `XY<space><path>` NUL-terminated. With `--no-renames` absent, a rename in status would add a second NUL field, but `!!` records never carry one, so filter on the `!! ` prefix before anything else.
- Read with `while IFS= read -r -d '' rec`, as `_branch_worktree` does. Capture the status rc separately (a process substitution hides it): write to a temp file or a variable first, check the rc, then parse.

## Printing

- Map control bytes with `LC_ALL=C tr '[:cntrl:]' '?'` per path, after the scope and allow decisions (those run on the raw path).
- The 20-path cap counts printed lines. The `and <N> more` line counts the rest.

## Registry and config

- `tests/test-config-registry.sh` AC10 asserts the "Root-only keys" table equals the set of keys passed to `kit_config_get_root` across `lib/`. Adding the read without the table row fails that suite, and the reverse fails it too.
- The kit-root line ships empty (`land_ignored_allow = ""`). The built-in list lives in code, so an operator value never drops a built-in entry.

## Existing fixtures

- The four land-merge sections that plant `ignored.bin` (`utref`, `ignx`, `ignr`, `igno`) get `KIT_CONFIG_OPERATOR` pointing at a fixture `kit.toml` with `[wrap] land_ignored_allow = "ignored.bin"`. `wrap-stub.sh` exports `KIT_CONFIG_OPERATOR="$TMPD/no-operator-config"` globally, so set it per call, not by editing the stub.
- `tests/test-wrap-land.sh` caches sections by input hash (`LAND_CACHE`). Run the full file once with `LAND_CACHE=0` before claiming no regression.

## Builder deltas from the spec

- **TASK-1 and TASK-2 share one commit.** AC10 in `tests/test-config-registry.sh` requires the "Root-only keys" table to equal the literal `kit_config_get_root` call sites. A registry row with no call site, or the reverse, goes red, so the knob, its registry rows, and the guard that reads it ship together.
- **`MANUAL.md` is a stub.** The root `MANUAL.md` is 11 lines and lists no refusals. The operator reference lives in `docs/MANUAL.md`, so the sentence went into its `/kit:wrap` section as a `Landing refusal` line. `docs/MANUAL.md` was not in the spec's `Touches` list; it is added there.
- **Test plan count.** TASK-2 said rows 1 to 22, but the table has 23 rows. The AC now says 1 to 23.
- **Row 4 split in two.** Row 4's new path-form built-ins (`tests/.cache`, `lib/*/bin/*-rs`) need a different touched scope than the `tools/x` caches, so they run as case `4b` with its own fixture. Both are named `4` and `4b` in the test output.
- **`KIT_CONFIG_OPERATOR` is a directory.** The resolver reads `$KIT_CONFIG_OPERATOR/kit.toml`. The four `ignored.bin` sections and the guard cases hand it a directory holding a `kit.toml`.
- **`.git/info` does not exist in a fixture clone.** `wrap-stub.sh` pins `GIT_TEMPLATE_DIR` to an empty dir, so row 12 creates `.git/info` before writing `exclude`.
- **Reads capture the exit code through `PIPESTATUS`.** `git diff -z` and `git status -z` pipe into `tr '\0' '\001'` (bash cannot hold a NUL, and a path may hold a newline). The git exit code comes from `PIPESTATUS[0]` inside the command substitution. `wrap.sh` runs `set -uo pipefail` with no `-e`, so this holds.
