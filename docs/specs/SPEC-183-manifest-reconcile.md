# SPEC-183: manifest-reconcile (repo-root kit.toml -> install render -> resolver read)

Status: SHIPPED (code + tests)
Lane: full
Backlog: harness-ops sub-goal 04 (`_meta/megagoals/harness-ops/goals/04-manifest-reconcile.md`)
Branch: feat/harness-ops-04-manifest
Relates-to: SPEC (config-resolver, `lib/config/kit-config.sh`, merged c84cda5), `docs/specs/DECISION-BRIEF-config-layer.md`
(open question 1, "manifest reconciliation")

## Problem

Three artifacts touch config today and they do not form one coherent chain:

1. `kit.toml.example` at repo root -- the full-schema TEMPLATE (status-tagged
   `[impl]/[design]/[reserved]/[consumer]`), never read by anything, never installed.
2. `install.sh` writes `~/.claude/dwarves-kit/kit.toml` -- but only ever a MINIMAL
   `[modules]` manifest (module -> true/false), hand-authored inline in the script,
   with no relation to the rich template.
3. `lib/config/kit-config.sh` (SPEC c84cda5) resolves `kit_config_get <section.key>`
   against `${KIT_CONFIG_ROOT:-${DWARVES_KIT:-$HOME/.claude/dwarves-kit}}/kit.toml`
   (project `.kit.toml` wins) -- but the file it reads in a real install only ever
   has `[modules]` in it. Every other section the resolver can address
   (`[ledger]`, `[mega]`, `[gate]`, `[features]`, `[team]`) is currently UNREACHABLE
   in a real install: the template exists, the resolver can read it, but nothing
   ships it to where the resolver looks.

This spec closes that gap: repo-root `kit.toml` (promoted from the template) is the
single shipped default; `install.sh` renders the live install `kit.toml` from it,
recomputing only `[modules]`; the resolver keeps reading the (now fuller) install
file, unchanged.

## Design

**One kit.toml, two copies, one chain.** Not a separate runtime-config file (the
brief's rejected alternative): the existing `[modules]` install manifest and the new
config sections ride the SAME file, because splitting them would reintroduce the
"three artifacts, no chain" problem this spec exists to fix.

- **Repo-root `kit.toml`** (this commit renames `kit.toml.example` -> `kit.toml`,
  content unchanged) is the shipped DEFAULT: the full status-tagged schema, source of
  truth for every section's default value. Consumed two ways: (a) `install.sh` reads
  it as the render source; (b) the resolver reads it DIRECTLY in dev (kit-repo-local
  work, `KIT_CONFIG_ROOT`/`DWARVES_KIT` pointed at the checkout).
- **Install `kit.toml`** (`$CLAUDE_DIR/dwarves-kit/kit.toml`, prod) is RENDERED by
  `install.sh`: copy the repo-root file verbatim, then recompute only the `[modules]`
  section's booleans from this run's actual enabled-module set (`KIT_ENABLED_MODULES`,
  unchanged logic) plus `team_mode = false` (reserved, always). Every other section
  (`[ledger]`, `[mega]`, `[gate]`, `[features]`, `[team]`) copies through untouched --
  this is what makes the render "the full schema", not just the old minimal manifest.
  A short generated-file header distinguishes it from the repo-root source (do not
  hand-edit; re-run `install.sh --with <modules>` to change the enabled set; edit
  repo-root `kit.toml` upstream to change a default, or `.kit.toml` to override one
  project).
- **The resolver's kit-root resolution is unchanged** (out of this spec's scope by
  design, owned by the earlier resolver spec): `kit_config_root()` ==
  `${KIT_CONFIG_ROOT:-${DWARVES_KIT:-$HOME/.claude/dwarves-kit}}/kit.toml`. This spec
  CONFIRMS (does not build) that the same function already resolves to the right file
  in both regimes, because the env-var precedence is the whole mechanism:
  - **Prod**: an adopting consumer exports `DWARVES_KIT=$HOME/.claude/dwarves-kit` (or
    leaves it unset, same default) -> resolver reads the INSTALL-rendered file.
  - **Dev**: kit-repo-local work points `KIT_CONFIG_ROOT` (or `DWARVES_KIT`) at the
    checkout itself (the same pattern every test in this repo already uses to point a
    resolver at a fixture root) -> resolver reads the REPO-ROOT file directly, no
    install step needed to iterate on a default.

**Why the hooks-only lint stays satisfied.** The lint (`tests/test-install-modules.sh`,
"STANDING ANTI-DRIFT LINT") asserts no `hooks/*.sh` contains the string `kit.toml`. This
spec touches `install.sh` (a one-time setup script, not a hook) and `lib/config/kit-config.sh`
(sourced by COMMANDS/feature libs at invocation, never by a spine hook) -- neither is in
`hooks/`. Nothing in this change adds a hook read. A negative control now proves the lint
is load-bearing rather than vacuously green: a synthetic hook file containing `kit.toml`,
dropped into a scratch `hooks/` dir, makes the same lint assertion FAIL.

**A necessary, narrow test fix.** The pre-existing NC "spine-only install: no module
recorded true in kit.toml" grepped `^[a-z_]+ = true$` over the WHOLE install file. That
was safe when the file held only `[modules]`, but the fuller render legitimately ships
other sections with `= true` defaults today (`[ledger] telemetry`, `[mega] tier4_close`,
`[gate] understanding_gate`, `[features] learning_ledger`), none of them a module. The
assertion's INTENT (no optional module falsely recorded enabled) is unchanged; its scope
is narrowed to the `[modules]` section so it keeps testing what it always meant to test
without now also asserting something the file was never designed to guarantee (that no
OTHER section has a `true` default). Same fix applied to `install.sh`'s own
`KIT_PRIOR_MODULES` re-install-detection grep, for the identical reason (it must not
mistake `understanding_gate`/`telemetry`/etc. for a "prior module").

## Scope edges

**In:** `install.sh`'s kit.toml render; the repo-root `kit.toml` (promoted from
`kit.toml.example`); confirming (not rebuilding) the resolver's kit-root resolution.
**Out:** the resolver's load/merge/precedence mechanics (owned by the earlier
config-resolver spec); what each section's keys MEAN or wire to (`[ledger]`/`[mega]`
wiring sub-goals).
**Not:** reversing the hooks-only lint; making a hook read config; a general
`install.sh` refactor beyond the render.

## Verification

1. `bash tests/test-install-modules.sh` -- the full pre-existing suite (now with the
   section-scoped fix) plus the new NC block, green.
2. `bash tests/test-manifest-chain.sh` (new) -- the 3-artifact chain run-table: repo-root
   default has the full schema; install render has the full schema PLUS the
   recomputed `[modules]`; resolver reads the install file in the prod regime and the
   repo-root file in the dev regime; `[modules]` still round-trips (`--with`, re-run,
   `--prune`).
3. `bash lib/config/kit-config.sh selftest` -- unchanged resolver mechanics, still green
   (regression check only; this spec does not touch the file).

## After state

- Repo root ships `kit.toml` (was `kit.toml.example`); no `.example` file remains.
- `install.sh` renders the full schema at install time; `[modules]` behavior (the
  6 existing NCs: spine-only, `--with`, un-opted-hook-absent, team_mode-reserved,
  unknown-module-error, additive-reinstall, `--prune`) is byte-for-byte preserved.
- The kit-root chain (repo-root -> install -> resolver) is demonstrated coherent by a
  captured run-table, co-located at `docs/verification/manifest-reconcile/proof-of-done.md`.
