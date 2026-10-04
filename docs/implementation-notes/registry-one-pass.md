# Implementation notes: registry-one-pass

Deltas from the spec (`docs/specs/SPEC-396-registry-one-pass.md`). Nothing here repeats what the spec states.

## Decisions

- **Cells format in the awk, not the shell.** The first design kept the old `sed | sort -uV | cap_list` pipelines and only replaced the greps. Those pipelines are about 1,200 spawns per run, so the awk now builds the Specs, Tests and Dispatched-by cells too (`cap_list` is gone from the shell). Result: about 4 s, not about 12 s.
- **Rows find their cells by key.** Bash 3.2 has no associative arrays, so `load_refs` fills four parallel arrays and `ref_lookup` scans them (about 130 keys; negligible).
- **The per-verb `grep -lE` over `hooks/*.sh` stays.** It reads about 40 small files per verb, costs a few ms, and keeps the "hooks that call this script" rule in one obvious place.
- **`token_pat` stays**, used only for that hook grep. The awk builds the same regex for non-pure tokens.
- **`FEATURE_REGISTRY_KEEP`** on `check`, not a new flag: callers write `FEATURE_REGISTRY_KEEP=$f ... check`, and a future `check` flag parser does not need to know about it.

## Gotchas

- **Do not use `grep -o` for the one pass.** It consumes the boundary character, so `foo bar` matches `foo ` and then misses `bar`. The set-of-runs lookup has no such overlap.
- **A regex token is not a literal.** `foo.sh` keeps `.` as an any-character wildcard, as in the old grep (`foo.shx` does not match only because of the trailing boundary). `tests/test-registry-one-pass.sh` pins both sides.
- **The one-true-awk compares `(^|x)` groups correctly**, but verify any matcher change against mawk and gawk too: `PATH=<dir with an awk symlink>:$PATH bash lib/registry/feature-registry.sh generate out.md`.
- **Fixtures copy only the generator** (`tests/test-registry-freshness-guard.sh`, `tests/test-registry-verbs.sh`), so the awk program lives inside `feature-registry.sh`, not beside it.

## Left as is

- `docs/FEATURES.md` Tests column still counts prose mentions (the old note in `check` about that stands).
- The generator header and `check` comments still say `tests/test-meta.sh` pins freshness; the pin now lives in `tests/test-meta-docs-registry.sh`. Comment drift, not touched here.
