# Implementation notes: config read once

Delta from `docs/specs/SPEC-398-config-read-once.md` only: what the build learned that the spec did not say.

## Identity: content, not size plus mtime

The brief named size plus mtime. The build measured and dropped it:

- bash 3.2 has no `stat` builtin and its `-nt` compares whole seconds, so a stamp would need a fork per lookup or a temp file to clean up.
- Size plus whole-second mtime cannot see the edit the spec's own test makes: `wave_cap = 2` to `wave_cap = 9` keeps the size and, run in one second, the mtime.
- `lane-data.sh` writes different tomls to one `mktemp` path in a loop, which a path-plus-stat key would serve stale.

Content compare through `$(<file)` is exact and forks nothing. Its price is one read of the file per lookup: about 1 to 2 ms for the 53 KB kit.toml on bash 3.2, because bash reads a command substitution 128 bytes at a time. A stamp-file fast path would cut that to microseconds; it needs a temp file, a trailer for cleanup and a fallback for a read-only filesystem, so it was left out. Known cost, not a bug.

## The first build was slower than master

Per-lookup string work on the 53 KB content and the records ran twice as slow under a UTF-8 locale in bash 3.2 (`[[ == ]]`, `${x%%pat*}`, substring offsets). Measured CPU per `kit_config_get`: 4 to 5 ms before the fix, about 2 ms after. The fix is `local LC_ALL=C` inside `_kit_toml_slot` and `_kit_toml_find`. The awk run keeps the ambient locale so the parse stays what the reference does.

## Cache must be filled in the sourcing shell

Every caller uses `v="$(kit_config_get ...)"`. A cache filled inside that subshell is lost. Without priming at source time the change gains nothing for the 158 call sites. The lib now parses its three layers when sourced. A script that sources it and reads no key pays one awk run per existing layer.

## Prime has a cost for scripts that never read a key

`bin/test-affected` caught it: `tests/test-flick.sh` pins one awk spawn per dictionary batch, and `lib/decide/flick.sh` sources kit-config.sh without reading a key through it (it has its own reader). The prime added one awk per existing layer to every flick run, on a hot path where a spawn is the dominant cost. Fix: `KIT_CONFIG_NO_PRIME=1` skips the prime, and flick.sh sets it on its source line. This is the one caller edit, forced by a real regression. Other sourcers that read nothing would pay the same; none other is known, and the opt-out is one word.

## Not exported

An exported cache would let child scripts skip the parse, but it would put about 100 KB into the environment of every process the kit starts. Rejected.

## `_kit_toml_get` is cached too

It is the sibling getter lane-data.sh, gate-policy.sh, proof-ledger.sh, config.sh and orchestrate.sh call directly. It keeps its output contract: a found key prints the value and a newline, a missing key prints nothing, and a key with an empty value prints an empty line.

## Declined inputs and divergences

- Keys outside `[A-Za-z0-9_-]`, empty keys, and sections with whitespace or a backslash use the reference reader (`_kit_toml_get_awk`), since it treats the key as a regex and `awk -v` expands escapes.
- An unreadable layer file also uses the reference reader, so the stderr text and exit status match.
- `HOME` unset under `set -u`: the old `$(kit_config_operator)` died in its subshell and the layer was skipped; the inlined path now expands to `/.config/dwarves-kit/kit.toml`. That file does not exist in practice, so the value is the same.
- A file holding NUL bytes loses them in the content read. A toml with NULs is not a case the kit has.
- The three public path functions (`kit_config_project`, `kit_config_operator`, `kit_config_root`) are untouched, but the getters no longer call them. A test that redefines one of them no longer redirects the getters. No file in the repo does.

## Test shape

`tests/test-config-cache.sh` compares the cached lib to `tests/lib/kit-config-reference.sh`, a frozen copy of the pre-cache resolver, so the parity proof outlives master's copy. `KIT_CONFIG_REFERENCE=<file>` swaps the oracle, used to confirm against `git show origin/master:lib/config/kit-config.sh`.
