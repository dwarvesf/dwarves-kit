# Sub-goal 02: wire-ledger

**Merge policy:** auto
**Time budget:** 2-3 hours
**Proof:** run-table showing a `[ledger]` key read via the resolver changing behavior + a negative control (env var still wins over config). Rung 2.
**Design:** obvious
**Depends on:** 01 (the resolver)
Model: sonnet
**Branch:** feat/harness-ops-02-ledger
**PR base:** main

## Outcome

The `[ledger]` config section is live: `location` ("shared"|"isolated"|path) resolves the ledger root, `telemetry` toggles run-tracking, `delivery_ratio_warn`/`delivery_real_floor` feed the proof-vs-real gate , all read through `lib/config/kit-config.sh` at the point each is consumed (ledger init, proof-ledger), never by a hot hook. Back-compat preserved: an explicit env var (`KIT_LEDGER_DIR`, `KIT_DELIVERY_RATIO_WARN`, ...) still WINS. Precedence: env > project `.kit.toml` > kit-root `kit.toml` > hardcoded default.

## How to close the loop

- In `lib/telemetry/kit-log-dir.sh` (and `lib/gate/proof-ledger.sh` for the delivery thresholds), source the resolver and insert config as the layer BETWEEN the env var and the hardcoded default.
- `location = "isolated"` → `$PWD/.kit/logs`; `"shared"` → the XDG default; a path → that path. Set-but-empty env stays fatal.
- Test: a project `.kit.toml` `[ledger] location="isolated"` writes under the project; `location="shared"` under XDG; setting `KIT_LEDGER_DIR` overrides BOTH (the negative control). Capture the run-table.

**Done =** `[ledger]` keys resolve through `kit-config.sh` with env>project>kit-root>default precedence (captured run-table incl. the env-wins negative control), and no hot hook sources the resolver (the hooks-only lint stays green).

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → normal; record build+review via gate-ledger.sh).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; overwrite HANDOFF.md → next ready sub-goal; append DECISIONS.md; report in records; EXIT.

## Scope edges

**In:** `[ledger]` resolution in kit-log-dir.sh + proof-ledger.sh's threshold reads.
**Out:** the ledger append format, the resolver itself (01), `[mega]` (03).
**Not:** changing the XDG default, adding new ledger keys beyond the schema, touching hooks.

## PR body

Wires the `[ledger]` config section through the kit-config resolver (env > project > kit-root > default), keeping env-var back-compat. Verify: the isolated/shared/env-wins run-table. Part of `harness-ops` (Track A), see ROADMAP.md.

## Notes
