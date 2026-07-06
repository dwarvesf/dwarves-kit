# Sub-goal 04: install-wire

**Merge policy:** auto
**Time budget:** 3-5 hours of loop work
**Proof:** run-table, a SPINE-ONLY install into a temp HOME wires ONLY the spine (grep settings.json: no optional-module hooks present); a `--with board,stats` install wires exactly those + records them in `kit.toml [modules]`; a re-run reproduces the same wired set from the manifest; named NCs: (a) an un-opted-in module's hook NEVER appears in settings.json, (b) the `team_mode` slot exists and defaults false, (c) unknown module name = clean error. COVERAGE-DELTA. Rung 2. This touches `install.sh` (consumer-facing wiring), over-test.
**Design:** bearing (the `[modules]` manifest schema + the layered-install mechanism; spec per design note B)
**Depends on:** 03 (wires the commands/modules)
Model: sonnet
**Branch:** feat/kitmod-04-install-wire
**PR base:** master (rebased after 03)

## Outcome

Enablement is by shell install/wire, a-la-carte. The core install wires the SDD spine unconditionally; each optional module has its own opt-in wire step (`install.sh --with board,stats,bridge` or a per-module wire). A light `kit.toml [modules]` manifest RECORDS what is enabled + its tier (for `kit list` / re-install), driving shell wiring, NOT a runtime feature-registry every hook reads. `install.sh` wires ONLY opted-in hooks, an un-installed module's hook never enters the consumer's `settings.json`, so a spine-only consumer has a quiet kit. A reserved `[modules] team_mode = false` slot exists (a not-yet-installable add-on). **Existing-consumer migration (advisor P6):** re-running `install.sh` on a consumer who already has all hooks wired is ADDITIVE/idempotent only , it NEVER retroactively un-wires a previously-wired hook. Trimming an existing consumer to spine-only is an explicit opt-in the consumer must request (e.g. `--prune`), never a silent fleet-wide behavior change (ops-toolkit/console-labs/family-office already ran the old all-hooks install).

## Quality bar

A consumer who wants just SDD installs the spine and NOTHING else is wired, no heavy-appliance feel, `settings.json` shows only what they run. Optional modules are genuine opt-ins. The manifest records choices so re-install is reproducible; it does not become a monolithic runtime config every module consults.

## How to close the loop

- Define the essential spine (spec/execute/review/ship + gate-ledger + ship-gate + lane-classify + proof-gate + core verifiers) vs optional modules (board, queue/orchestrate, stats, bridge, quiz-gate, weekend-batch, advisor over-suggest, session-*, cosmetic hooks, team-mode).
- Make `install.sh` layered: spine unconditional; `--with <modules>` opt-in; write/read the `kit.toml [modules]` manifest; wire ONLY opted-in hooks (an un-installed module's hook is not written to settings.json).
- Reserve the `team_mode=false` slot.
- Run-table: spine-only temp-HOME install (grep no optional hooks); `--with board,stats` (those wired + manifest updated); re-run reproduces.
- NCs: (a) un-opted hook absent from settings.json; (b) team_mode slot present, false; (c) unknown module → clean error.
- STANDING anti-drift lint (advisor P6): the manifest must NOT become a de-facto runtime registry (Decision B's named anti-pattern). Add a durable check , a lint/CI grep asserting NO hook reads `kit.toml` at runtime (only `install.sh` touches it), e.g. `grep -rl kit.toml hooks/` is empty. A point-in-time NC does not stop a future "read the manifest just this once" hook.
- POST-INSTALL SMOKE (advisor P6, the F-bar's missing "does it run" half): after the temp-HOME install, run `<subsystem> --help` (or an equivalent no-op verb) for EVERY wired module and assert exit 0. A module can have a doc + a firing point yet still fail on first invocation (missing shebang, wrong relative path after the `git mv`); this catches it. Piggybacks on the temp-HOME install already stood up here.

Kit-adopted: record build + review via `bash lib/gate-ledger.sh`.

**Done =** spine-only install wires only the spine, `--with` opt-ins wire exactly those + record them in `kit.toml [modules]`, re-install reproduces, and an un-opted module's hook never reaches settings.json, captured in `docs/proof/kitmod-install-wire.md`.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-05/06 document the install model + the manifest.
3. DECISIONS.md: record the spine/optional split + the `[modules]` schema.
4. Report in records, EXIT.

## Scope edges

**In:** `install.sh` (layered, per-module wire, opted-in-hooks-only); the `kit.toml [modules]` manifest + `feature`/`module` helper; the `team_mode` slot.
**Out:** the command entries (SG-03); docs (SG-06); the operate-contract (SG-05); building team-mode (parked).
**Not:** a runtime feature-registry every hook reads on every event; conditionally-wiring via a big central config; enabling team-mode; installing everything by default.

## Where to look

`install.sh` (the copy + settings.json merge sections), the existing opt-in gates (`boards.txt bridge=on`, `heartbeat.every`), design note Decision B.

## PR body

Layered install: core spine unconditional + per-module opt-in wire (`install.sh --with ...`) recorded in a light `kit.toml [modules]` manifest (+ reserved `team_mode` slot). Install wires only opted-in hooks, a spine-only consumer's settings.json stays quiet.

Verify: spine-only + `--with` temp-HOME installs; manifest reproduce; un-opted-hook-absent NC. Proof: `docs/proof/kitmod-install-wire.md`. Stacked on #<SG-03>.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-modularity/ROADMAP.md`.

## Notes
