# Implementation note: test-affected-tune

Delta from `docs/specs/SPEC-390-test-affected-tune.md` only; the spec carries the design.

## How the area inputs were derived

Each area suite was read for what it touches, not guessed. Two kinds of read matter:

- **Named paths** (`"$KIT_DIR/docs/WORKFLOW.md"`, `lib/gate/proof-gate.sh`). The existing reference scan in `bin/test-affected` already picks any area suite that names the path or a long basename, so these need no table row. This was the largest share of what the old runner pick covered.
- **Glob and scan reads** (`for f in "$KIT_DIR/commands/"*.md`, `ls "$KIT_DIR/hooks/"*.sh`, `git ls-files '*.md'`, the installer run, the registry regenerate). No reference scan can see these, so each became an arm of `meta_areas`.

A first hand-derived table missed two real reads that an independent replay check found: `test-meta-vmodel-dispatch` counts `hooks/*.sh` and `skills/*/SKILL.md` against the README tables. Both arms now include it. The replay driver scans the area suites' non-comment lines for the path, a long basename, or a glob the path falls under (honouring the `grep -vE` exclusion lists next to each scan), separately from `meta_areas`, and fails a PR whose touched area is not in the after set.

## Always-run set: empty on purpose

The goal asked for a small always-run set for suites that guard every change (doc projection, registry freshness). None qualifies:

- Registry freshness is the `docs-registry` pin, and every input to `docs/FEATURES.md` that a diff can move is a mapped path there (commands, agents, skills, hooks, kit-verb lib files, `lib/*/tests/`, `docs/specs/`). `hooks/ship-gate.sh` also refuses a push that moves one without a fresh `docs/FEATURES.md`.
- Doc projection has its own fast check in the ship gate (`lib/gate/doc-projection-check.sh`).
- The tree-wide lints that really do guard every diff already declare `# always:` in their own headers; `run-all.sh --changed` adds them.

Making `docs-registry` (the slowest area, about 145 s alone) always-run would give back most of the saving for no coverage the mapping lacks.

## Two behaviours worth knowing

- **Archive docs pick no area.** `docs/verification/`, `docs/retro/`, `docs/handoff/`, `docs/research/`, `docs/CHANGELOG.md` and `_meta/` are excluded by every glob scan the areas run, so an edit there picks no area (a direct mention still picks by reference). The file then shows as UNCOVERED, which is reported and not a failure. This is a change from the old rule where any `*.md` picked the whole group.
- **A kit-verb header removal still counts.** The registry reads `# kit-verb:` headers in the first 40 lines of a lib file. A diff that deletes the header leaves a file that no longer looks like a meta input, so `kit_verb_file` also checks the base copy (`git show $BASE:<path>`).

## R8: one timeout source

`tests/run-all.sh` `suite_timeout` reads `bin/test-affected.timeouts` and its hardcoded `test-meta*) echo 900` arm is gone. `tests/test-run-all-timeout.sh` case 7 now builds a fixture data file instead of relying on a `test-meta` name. The `TIMED OUT at ${TIMEOUT_SECS}s ->` summary line is unchanged; each timed-out suite carries its own limit on the `TIMEOUT (Ns)` report line and in the summary list when that limit differs from the default.

## Timeout numbers

The data file holds every suite measured, not only the slow ones: D4 says each suite's ceiling is 2 x its p95, floor 60. The five samples come from parallel full runs (`RUN_ALL_JOBS` auto, four at a time) on a busy host, so they are conservative upper bounds; the header in the file records the load average at the start of each run. Resolution is whole seconds (`run-all.sh --time`), so a sub-second suite measures 0 s and takes the 60 s floor.

## Not changed

- No suite assert, label or fixture. The `# runner-suites:` header and runner expansion from the split stay as they were.
- `lib/gate/lane-data.sh` and `lib/telemetry/kit-log-dir.sh` sit in the `gate-ledger.sh` source chain, so they map to the three areas that run gate-ledger. Any other unnamed `lib/{board,classify,config,gate,goal,registry,telemetry}/` file falls back to the runner: the table does not guess.
