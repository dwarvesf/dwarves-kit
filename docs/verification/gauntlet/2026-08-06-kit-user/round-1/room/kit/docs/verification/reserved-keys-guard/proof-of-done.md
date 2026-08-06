# Proof of done: reserved-keys-guard (SPEC-188, harness-ops sub-goal 08)

## Acceptance criteria -> run-table

| # | Criterion | Result | Evidence |
|---|---|---|---|
| AC1 | No live code path reads `[features]`/`[team]` keys under `lib/`, `commands/`, `hooks/` | PASS | "NC no-live-path" block, grep across all 9 reserved keys, 0 hits |
| AC2 | The no-live-path lint is load-bearing, not vacuously green | PASS | "NC lint-load-bearing" block: a planted `kit_config_get team.actor_identity` call in a scratch dir IS caught by the same grep |
| AC3 | The reserved keys are resolver-readable (a future consumer can read them with no resolver change) | PASS | `kit_config_get features.auto_improvement` / `kit_config_get team.actor_identity` resolve to `true` via a project `.kit.toml` override |
| AC4 | Rung-2 negative control: flipping an inert key changes no observed behavior | PASS | two spine surfaces (`kit-config.sh selftest`, `lane-classify.sh classify`) run byte-identical baseline vs. flipped-config |
| AC5 | Status tags document the reserved keys as `[design]`/`[consumer]`, not live | PASS | grep on `kit.toml`: `auto_improvement` -> `[design]`, `learning_ledger` -> `[consumer]`, all 7 `[team]` keys -> `[design]` |
| AC6 | No regression to the config resolver or the manifest chain | PASS | `kit-config.sh selftest` (6/6) + `test-install-modules.sh` (37/37) unchanged |

**Total: 9/9 PASS in `tests/test-reserved-config-guard.sh`. Regression: 6/6 + 37/37 unchanged, 0 FAIL.**

## What this confirms (not builds)

`kit.toml`'s `[features]`/`[team]` sections (shipped by SPEC-183) are documentation-only
today: the resolver (`lib/config/kit-config.sh`) will happily return any value asked of
it, but no command, lib, or hook branches on `features.auto_improvement`,
`features.learning_ledger`, or any `team.*` key. This sub-goal locks that fact behind a
standing test so a future change that silently wires one of these keys to a real code
path fails CI instead of shipping as an undocumented surprise.

## Confirmation run (positive: current tree)

Command: `bash tests/test-reserved-config-guard.sh`
Exit: 0

```
== NC no-live-path: nothing under lib/, commands/, hooks/ branches on [features]/[team] ==
  PASS  no lib/commands/hooks file reads a [features]/[team] key (leaked: none)
== NC lint-load-bearing: the grep genuinely catches a planted live-path read ==
  PASS  NC: planted live-path read of team.actor_identity is caught by the same grep
== resolver-readable: kit_config_get surfaces reserved keys via project override ==
  PASS  resolver reads project override features.auto_improvement=true
  PASS  resolver reads project override team.actor_identity=true
== NC inert-flip-changes-nothing: flipping the reserved keys touches no observed behavior ==
  PASS  config-resolver selftest identical baseline vs inert-key-flipped (features.auto_improvement, team.actor_identity)
  PASS  lane-classify output identical baseline vs inert-key-flipped
== status tags: kit.toml documents the reserved keys as [design]/[consumer], not live ==
  PASS  kit.toml: auto_improvement tagged [design]
  PASS  kit.toml: learning_ledger tagged [consumer]
  PASS  kit.toml: all [team] keys tagged [design] (untagged: none)

== 9 run, 9 passed, 0 failed ==
```

Full log: `/tmp/proof-run-188.log` (this run).

## Negative control (revert the test, or plant a real live-path read)

Two ways this test would go RED, both verified live during authoring:

1. **A future accidental wire-up**: if any file under `lib/`, `commands/`, or `hooks/`
   started calling `kit_config_get features.auto_improvement` (or any other reserved
   key), the "NC no-live-path" assertion fails immediately (grep finds the file).
   Demonstrated by the planted `fake-team-consumer.sh` in AC2 -- the identical grep
   pattern this test's first assertion uses DOES catch it.
2. **A dropped status tag**: if `kit.toml` lost the `[design]` tag on any `[team]` key
   or the `[consumer]` tag on `learning_ledger` (e.g. a careless edit that reformatted
   the comments), the "status tags" block's grep assertions fail. Confirmed by manually
   stripping the `# [design]` suffix from one `[team]` line during authoring and
   re-running: `FAIL  kit.toml: all [team] keys tagged [design] (untagged: actor_identity)`.

## Regression (resolver + manifest chain unaffected)

```
$ bash lib/config/kit-config.sh selftest
ok   project overrides kit-root
ok   kit-root default when no proj
ok   inline comment stripped
ok   commented key -> caller default
ok   missing key -> caller default
ok   missing section -> empty
PASS kit-config selftest

$ bash tests/test-install-modules.sh
... (37 assertions unchanged) ...
== 37 passed, 0 failed ==
```

## Reproduce

```
cd <repo>
bash tests/test-reserved-config-guard.sh   # new, this sub-goal
bash lib/config/kit-config.sh selftest     # regression
bash tests/test-install-modules.sh         # regression
```
