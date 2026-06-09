---
description: "Adopt the current (or a target) repo into the dwarves-kit operate-contract: inject AGENTS.md + a CLAUDE.md loader + a WORKFLOW pointer + the proof marker, idempotently, and wire the lane/loop-type/proof classifiers so the ship-gate engages."
---

You are adopting a repo into the dwarves-kit operating layer. This installs the operate-contract
so that, from now on, an agent working in that repo classifies the work and picks a lane before
coding, and the ship-gate engages on push.

## Run

`$ARGUMENTS` may name a target dir (default: the repo root) and/or `--check` (status only).

1. Resolve the target: default `.` (`git rev-parse --show-toplevel`).
2. Run the driver (idempotent, non-destructive):

   ```
   bash "${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/dwarves-kit}/lib/adopt.sh" [--check] <target>
   ```

3. Report what it created (or that the repo was already adopted). Tell the user the one next
   step: open a session in the adopted repo and run `/kit:start` to classify the first task.

## What adoption installs

- `AGENTS.md` -- the operate-contract (read-first).
- a `CLAUDE.md` loader pointer (Claude Code auto-loads CLAUDE.md, not AGENTS.md).
- `WORKFLOW.md` -- a pointer to the installed kit's lane x phase matrix (not a 49KB copy).
- `docs/verification/README.md` -- the proof marker that makes the ship-gate engage.

The classifiers (`lane-classify`, `task-type-classify`, `proof-gate`) run from the installed kit;
adoption wires the contract to reference them. It never copies the engine.

## Do NOT

- Overwrite an existing AGENTS.md / CLAUDE.md (the driver guards this; never force it).
- Copy `lib/` or the full `WORKFLOW.md` into the consumer.
