# Sub-goal 08: config-surface

**Merge policy:** auto
**Time budget:** 3-6 hours of loop work
**Proof:** (SPEC-198) run-table: `config list` full render (freeze-PNG + text) on a fixture with an env override + a project `.kit.toml` override both visibly winning their rows; `config explain <key>` showing the four-level provenance chain; registry drift-lint green + NC (a planted unregistered env var fails the lint, captured). Rung 2.
**Design:** bearing (the registry is a new single-source artifact with a lint contract)
**Depends on:** 01
Model: sonnet
**Branch:** `feat/loop-08-config-surface`
**PR base:** master

## Touches

bin/ (new `config` entry), lib/config/ (verbs beside the resolver, resolver itself unchanged), a new checked-in registry file (docs/ or lib/config/, ADR-0034 names the home), tests/

## Outcome

`bin/config list|get|explain` is the one window into the harness's knobs: every declared key rendered with effective value, provenance (env > project `.kit.toml` > kit-root `kit.toml` > default), status tag (`[impl]/[design]/[reserved]/[consumer]`, non-impl rendered visibly inert, never as a live toggle), and owning module + enabled state. Backing it: the env↔key REGISTRY, one checked-in table mapping every user-facing env var to its kit.toml key (or "env-only"), its default, its doc line, generated-from-nothing-else, EXPLICITLY including the data-plane keys (`[ledger]` section, `KIT_LEDGER_DIR`/`DWARVES_KIT_LOG_DIR`, every `STATS_*` source var with its no-default-consumer marking), with a drift lint (any `$KIT_*`/`WAVE_*`/`QUEUE_*`/`CC_SI_*`/etc. read in lib/ or hooks/ that is absent from the registry fails the test, allowlist for internals). The lint REUSES the shared `tests/lib/contract-lint.sh` helper SG-02 lands (grep-diff-against-manifest, parameterized); do not write a second bespoke grep. `config set` is OUT (ships later if the read verbs prove out; writing config is `.kit.toml` hand-edit for now, stated in the help text).

## Quality bar

Provenance you can trust at a glance: a value's row answers "why is this the value" without opening a file. The registry kills the ~30-undocumented-vars problem structurally, not editorially: after this, an undocumented knob cannot merge.

## How to close the loop

1. Spec; the registry schema in the Design block.
2. Seed the registry from a FRESH self-derived sweep: `rg -ohE '\$\{?(KIT|WAVE|QUEUE|MEGA|CC_SI|PROSE_RAG|MONEY_GATE|TIER4|MUX|TMUX|PANE|TERMINAL|STATS|CC_BACKLOG|HARVEST|BACKLOG|DWARVES)[A-Z_]*' lib hooks bin | sort -u`, then verify each hit's reader + default at its source (no pre-existing table exists in the repo; the sweep IS the source material).
3. Build list/get/explain over `kit_config_get` + env inspection; resolver file untouched (its selftest still green byte-identical).
4. Fixture: env override + project override + kit-root default + hardcoded default, one key each; capture list + explain output.
5. Drift lint + its NC.

**Done =** list/explain captures committed + registry complete against the live sweep + drift lint green with failing-NC captured + resolver selftest unchanged.

Kit-adopted repo: record gates via `bash lib/gate/gate-ledger.sh` per lane plan before the PR push.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HANDOFF.md: next = 09; first action = read this sub-goal's registry + ADR-0034 §4 fences. 3. DECISIONS.md: registry home + allowlist policy. 4. EXIT.

## Scope edges

**In:** the three read verbs, the registry + lint, help text.
**Out:** `config set`, resolver changes, hook behavior, kit.toml schema changes.
**Not:** a TUI, editing env for the user, "fixing" undocumented vars by deleting them (register them; retiring a knob is its own future decision).

## Where to look

`lib/config/kit-config.sh` (the resolver contract, DO NOT edit), `kit.toml` status tags, `lib/telemetry/kit-log-dir.sh` (the canonical env-over-toml precedence example), DECISION-BRIEF-config-layer (the locked read model), the mechanism audit's env sweep in the harness-loop brief's source notes.

## PR body

`bin/config list|get|explain`: effective value + provenance + status tag for every declared knob; env↔key registry + drift lint (an unregistered var can no longer merge). Verify: fixture captures + lint NC in the proof-of-done. Roadmap: `_meta/megagoals/harness-loop/ROADMAP.md` SG-08.

## Notes
