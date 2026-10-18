# Implementation notes: kit-sweep

Deltas and decisions from the brief. No spec drove this sweep; the brief was the contract.

| Choice | Decision | Why |
|---|---|---|
| Where the module gate lives | `lib/config/hook-module.sh`, called from `hooks/anchor-root.sh` | `tests/test-gate-opt-out.sh` and `tests/test-install-modules.sh` forbid any `hooks/*.sh` from naming the config files. A lib script keeps that lint meaningful and is testable alone. |
| Resolver | One awk pass over `modules.tsv` plus the existing config layers | `kit_config_get` costs up to four awk forks per call and a hook runs on every tool call. `tests/test-anchor-module-gate.sh` pins the result against `kit_config_get` for each layer so the two cannot drift. |
| Spine fast path | `anchor-root.sh` skips the lookup for the six spine hook names | The spine never turns off, and safety-gate and ship-gate run on every Bash call. The lib also answers "not off" for any spine hook, so the list is a speed-up, not a rule. |
| Fail direction | Every uncertainty runs the hook | Unknown hook, missing table, value that is not literally `true` or `false`: the hook runs. |
| Test fixture | `tests/fixtures/gates-on/kit.toml` gains a `[modules]` block with every toggle on | Suites that drive an opt-in hook through the wrapper (the anchor cases in `test-hooks.sh`) need it to run. |
| `_refs_block` coverage | New `tests/test-ship-gate-refs-block.sh`, adopted vs non-adopted repo | Matches the fail-closed-only-where-adopted rule `_fc_applies` encodes. The "parser gave no answer" branch needs a missing parser and is not driven. |
| Drift row 15 | Left open | batch-debt-warn still reaches the ledger migration; no slice touched it. |
| Drift rows 17, 37, 39 | NOT APPLICABLE | The money-gate docs dir is required by the contract test, `bin/learn` is not yet due, and the session-state hook is gone. |
| Hermes bridges | Closed as accepted | Operator decision: keep both as separate jobs. |
| FEATURES.md | Regenerated with `check --fix` | The new lib script and test files move its counts. |
| Who may switch a module off | The project `.kit.toml` wins, as the brief and `kit_config_get` specify | The review lens flagged that a PR branch controls that file. The spine and every `[gate]` key sit outside this toggle, and ship-gate reads gate keys at the default branch, so a project file can only quiet the opt-in and board hooks in the sessions that open that repo. The header of `lib/config/hook-module.sh` records the decision. |
| Differences from `kit_config_get` | An empty config file is skipped; a value that is not `true` or `false` falls through to the next layer | Both fail toward running the hook. |
