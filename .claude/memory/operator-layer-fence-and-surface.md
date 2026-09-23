---
name: operator-layer-fence-and-surface
description: A test suite that reads config must pin KIT_CONFIG_OPERATOR to an empty dir, and every config-reading surface must resolve through kit-config.sh, or an operator preference turns the suite red and the CLI lies about the effective value.
metadata:
  type: feedback
---

Two faults surfaced together when `adopt.single_source = true` landed in the operator kit.toml. test-adopt read the live operator file, so 14 of its cases failed on master with no code change. `bin/config get|explain|list` built its own precedence chain without the operator layer, so it printed `false` for keys the resolver returned as `true`, and had done so for as long as the operator file existed.

**Why:** the operator kit.toml is a per-machine preference layer. A test that inherits it asserts the operator's taste, not the kit's default. A CLI that skips it shows a value nothing runs with.

**How to apply:** every test that calls a config-reading path exports `KIT_CONFIG_OPERATOR="$(mktemp -d)"` at the top (test-wrap and test-adopt do; copy that shape), and a section that needs its own operator file restores the pin instead of `unset`. Every new surface that reports or acts on a knob calls `kit_config_get` / `kit_config_get_root`, never a hand-built chain. The negative control for a new knob: set it in a scratch operator file, run the suite unpinned, watch it go red, then pin. Related: [[gate-ledger-keys-by-spec-slug]].
