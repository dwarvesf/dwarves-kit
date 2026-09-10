# Sub-goal 01: the engine keeps one seam and forgets every consumer's name

**Merge policy:** auto
**Time budget:** 3 hours
**Proof:** run-table: `bin/config seams` lists `wrap.learn` (kind `skill`, filled by "learning-kit dev-learner lane, or the operator"); `commands/wrap.md` Step 7a and 7c invoke the seam and name no skill; `tests/test-boundary-lint.sh` is green on this branch and RED when a fixture line `learning-ledger` is planted in `lib/learn/weekend-batch.sh` (NEGATIVE CONTROL); `bin/learn` forwards to `bin/reflect` with a one-line deprecation, `tests/run-all.sh` green.
**Depends on:** 00 Accepted.
Model: sonnet
Effort: high
**Branch:** feat/engine-learn-seam

## Outcome

Three things. A `wrap.learn` seam key: `[wrap] learn = ""` in `kit.toml`, a registry row, a `## Seams` row, resolved with `kit_config_get_root` like its siblings; Step 7a records the DEBT marker as it does today and then invokes whatever `wrap.learn` names, and Step 7c does the same for the incident memory note, so the engine writes the data and the learner's kit decides what to teach from it. A boundary lint, `lib/gate/boundary-lint.sh`, wired into `tests/run-all.sh`, that greps `lib/`, `commands/`, `tests/`, `kit.toml` for any of: a dotfiles path, `ops-toolkit/`, or the name of a skill that is not under `skills/` in this repo, and fails naming the line; the allowlist is the `## Seams` table's `Filled by` column and nothing else. The `learn` → `reflect` rename: `bin/reflect` and `lib/reflect/` carry `propose` and `drain`; `bin/learn` stays as a forwarder that prints one deprecation line; `learn debt` moves under `bin/reflect debt` because the DEBT ledger reader is engine data.

## Quality bar

No new engine: the seam is one more row in the tables SPEC-249 already built. The lint is a grep with an allowlist, under 60 lines. The rename is `git mv` plus path fixes; `git log --follow` survives. Every existing test passes unchanged except for the path of the thing it calls.

## How to close the loop

`/kit:spec` first (three units, one spec). Build in the order lint, seam, rename, so the lint is what proves the seam left no name behind. Negative control on the lint by planting a name.

**Done =** the three proofs above, suite green, zero skips.

## Scope edges

**In:** the key, the lint, the rename, Step 7a/7c prose, the seams table.
**Out:** any skill body; learning-kit; dotfiles.
**Not:** changing what the DEBT marker records or when.
