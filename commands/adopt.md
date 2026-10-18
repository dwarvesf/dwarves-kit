---
description: "Adopt the current (or a target) repo into the dwarves-kit operate-contract: write a small AGENTS.md pointer (never over a repo's own file) + a CLAUDE.md loader + a WORKFLOW pointer + the proof marker, idempotently, and wire the lane/loop-type/proof classifiers so the ship-gate engages."
---

You are adopting a repo into the dwarves-kit operating layer. This installs the operate-contract
so that, from now on, an agent working in that repo classifies the work and picks a lane before
coding, and the ship-gate engages on push.

## Run

`$ARGUMENTS` may name a target dir (default: the repo root), `--check` (status only),
`--with <a,b,c>` (seed these modules `true` in a FRESH `.kit.toml`; ignored once one exists),
or `--single-source` (see below).

1. Resolve the target: default `.` (`git rev-parse --show-toplevel`).
2. Run the driver (idempotent, non-destructive):

   ```
   bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/adopt.sh" [--check] [--with <a,b,c>] <target>
   ```

3. Report what it created (or that the repo was already adopted). Tell the user the one next
   step: open a session in the adopted repo and run `/kit:start` to classify the first task.

## What adoption installs

- `AGENTS.md` -- a small pointer (about 1KB: four rules plus where the full contract lives), not a
  copy of the 18KB contract. A repo's own `AGENTS.md` is never overwritten; an unmodified old kit
  copy is replaced only by `--refresh --swap-agents`, and an edited file gets a drift line.
- a `CLAUDE.md` loader pointer (Claude Code auto-loads CLAUDE.md, not AGENTS.md).
- `WORKFLOW.md` -- a pointer to the installed kit's lane x phase matrix (not a 49KB copy).
- `docs/verification/README.md` -- the proof marker that makes the ship-gate engage.
- `.kit.toml` -- an OPT-IN starter override of the kit-root defaults. Created
  only on a fresh adopt (never overwritten afterward); `--with` seeds the named modules
  `true` instead of inheriting the kit-root default. `--with` names the exact set, so a core module
  you leave out starts `false` (`install.sh --with` differs: it adds to the core set). Without `--with`
  only `core` modules, today `board`, start `true`; every other module is opt-in. Edit `[modules]` any time and re-run
  `/kit:adopt` (or `--refresh`) to re-wire. Its `[gate]` block is where the blocking quality
  gates are set for this repo. A fresh seed turns `proof_of_done` and `lane_gates` ON (the kit
  root keeps them off for a raw install, so a repo adopted before this change keeps whatever its
  file says); an operator `kit.toml` that names either key still wins. `understanding_gate` and
  `commit_format` are seeded with the values that resolved at adopt time (off by default), and
  `board_row_gate`, `fixture_identities` and `review_verdict` default ON. Every key gets a comment,
  and the block says how to turn each seeded gate off: set `proof_of_done = false` or
  `lane_gates = false` and commit. Changes apply from the next hook fire (no re-adopt). Adopt only
  seeds a fresh file: an existing `.kit.toml` is never touched, so a key the repo set or deleted
  stays as it is. Safety gates have no key. Detail: `lib/gate/README.md` "Turning a gate on".
- A one-time move of old kit logs into the durable ledger root (`lib/telemetry/kit-migrate.sh`),
  which `install.sh` also runs. It is the only place logs are copied; a hook or resolver never
  copies. `--check` and `--dry-run` skip it.
- `.claude/settings.json` hook entries for this project's currently-enabled hook-bearing
  modules -- a targeted jq MERGE, re-wired on every adopt run from the project's CURRENT
  `.kit.toml`, never a wholesale file rewrite. The module list and each module's hooks come from
  `lib/config/modules.tsv`, the one table `install.sh` reads too; a module with no hook there
  (`queue`, `stats`, ...) needs no settings.json entry. On a machine with the kit plugin installed
  adopt leaves the project's `settings.json` alone (it adds no hooks and strips none), because the
  plugin's `hooks.json` already registers every hook under a different command string, a second set
  would fire twice, and the project file is committed and shared; the output line says so. A hook your
  own `~/.claude/settings.json` also wires is fine: Claude Code runs an identical handler once.

To adopt several repos at once, use `bin/wrap adopt <repo>...` instead of running the driver per repo. It dry-runs by default, and with `--apply` it opens and lands one adoption PR per repo. See the `adopt` bullet in `commands/wrap.md`.

The classifiers (`lane-classify`, `task-type-classify`, `proof-gate`) run from the installed kit;
adoption wires the contract to reference them. It never copies the engine.

## `--single-source`

For a repo that wants to keep exactly one agent guide instead of a CLAUDE.md/AGENTS.md pair.
An existing `CLAUDE.md` (and no `AGENTS.md`) folds into `AGENTS.md` via `git mv`; `CLAUDE.md`
becomes a one-line `@AGENTS.md` import (still auto-loaded by Claude Code, still importing the
single source), and the operate-contract block lands in `AGENTS.md` instead of `CLAUDE.md`.
Already in that shape: a no-op. Both files exist and genuinely differ, or neither exists:
refuses (exit 1) and writes nothing, so the operator merges by hand. The root-only knob
`adopt.single_source` (default `false`) turns this mode on without the flag; `--no-single-source`
overrides a `true` knob back off.

## Overlays and seams

Adoption installs the engine alone; no `[modules]` entry requires a companion kit. Two overlays
exist today. context-kit is the data plane: it owns the context tree and recall over it, and
fills `[knowledge] root` plus the `PROSE_RAG_BIN` binary. learning-kit is a study overlay on the
engine; it fills `[wrap] before` with its concept flush.

A seam is a key in the operator `kit.toml`, never this repo's `.kit.toml`, that the engine reads
with `kit_config_get_root`. `bash "$KIT/bin/config" seams` lists every seam with its state
(`default`, `filled`, `unresolved`, `absent`); `--check` exits 1 on an unresolved row, for an
installer. With nothing filled, every seam reads `default` or `absent` and the adopted repo works
the same. Table: `lib/config/module-registry.md` under `## Seams`.

## Do NOT

- Overwrite an existing AGENTS.md / CLAUDE.md / `.kit.toml` (the driver guards this; never
  force it; `--with` on an existing `.kit.toml` is a no-op with a note).
- Copy `lib/` or the full `WORKFLOW.md` into the consumer.
