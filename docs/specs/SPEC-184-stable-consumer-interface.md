# SPEC-184: stable consumer interface (bin/ entrypoints, no deep-lib-path reaches)

Status: SHIPPED (code + tests)
Lane: full
Backlog: harness-ops sub-goal 05 (`_meta/megagoals/harness-ops/goals/05-stable-interface.md`)
Branch: feat/harness-ops-05-interface
Relates-to: `docs/briefs/DECISION-BRIEF-config-layer.md` (open question 2, "stable consumer interface")

## Problem

Consumers of the kit reach into `$DWARVES_KIT/lib/<subsystem>/<file>.sh` DEEP paths.
That coupling is fragile: the kit-modularity regroup moved `lib/board.sh` ->
`lib/board/board.sh` with no flat compat shim, which SILENTLY broke every consumer that
hard-referenced the old path (ops-toolkit's `_meta/board` / `board-all` shims; fixed
pointwise 2026-07-06). The same class of bug lives in the adopt contract itself: the
CLAUDE.md block `lib/adopt.sh` injects into EVERY adopted repo references two deep lib
paths (`lib/classify/lane-classify.sh`, `lib/gate/gate-ledger.sh`), so the next internal
reorg breaks every adopted repo at once.

There is no stable, contract-guaranteed path a consumer can point at. The internal
`lib/<subsystem>/` layout is an implementation detail that consumers were forced to
depend on.

## Design

**Pick: per-subsystem installed command shims under a stable `bin/` dir. Rejected: a
`kit <subsystem> <verb>` uber-dispatcher.**

The goal named two approaches. The pick is forced by the kit's already-committed
architecture, not a free choice:

- **AGENTS.md ("How the kit composes") is explicit: "There is no `kit` uber-dispatcher,
  each command's own `--help` is the discovery surface."** The kit is a toolbox of
  self-contained subsystem modules, each exposing a standalone `<subsystem> <verb>`
  command (`board next`, `gate ledger ...`, `classify ...`). Introducing a `kit`
  uber-dispatcher would contradict that source-of-truth architecture statement (an
  AGENTS.md zone-4 "architecture direction / source-of-truth" decision, not a worker's
  to flip). So the stable interface EXPOSES the existing per-subsystem commands at a
  stable path; it does not introduce a new dispatch layer on top of them.
- **The subsystem entries already exist** (`lib/classify/classify.sh`,
  `lib/gate/gate.sh`, and `lib/board/board.sh` which self-dispatches). They own the verb
  grammar. What was missing is only a STABLE PATH to reach them from outside the kit.

**Mechanism.** A new top-level `bin/` dir holds one thin forwarder per consumer-facing
subsystem:

| Stable entrypoint | Forwards to | Consumer of it |
|---|---|---|
| `bin/board` | `lib/board/board.sh` | ops-toolkit `_meta/board`, `board-all` (and every adopted repo's board shim) |
| `bin/classify` | `lib/classify/classify.sh` | the adopt-injected CLAUDE.md block (lane classify) |
| `bin/gate` | `lib/gate/gate.sh` | the adopt-injected CLAUDE.md block (gate ledger) |

Each wrapper resolves its target relative to its OWN location
(`SELF_DIR/../lib/<sub>/<entry>.sh`), so the same file works in the kit repo (dev) and in
the copied install (`$DWARVES_KIT/bin` sits next to `$DWARVES_KIT/lib`). `install.sh`
copies `bin/` into the install alongside `lib/` (and symlinks it on a plugin-compat
machine), and uninstall removes it.

**The invariant.** A consumer references `$DWARVES_KIT/bin/<name>`, NEVER a deep lib
path. When the internal `lib/` layout is reorganised, the blast radius is the ONE
kit-owned wrapper line inside `bin/<name>`, not every consumer. The internal reorg is
absorbed BELOW the stable interface (and, for `classify`/`gate`, one layer lower still,
inside the subsystem entry `classify.sh` / `gate.sh`, so even the `bin/` wrapper is
untouched by a leaf rename).

**Not a flat alias shim.** The kit-modularity directive "NO ALIAS SHIMS" forbade leaving
flat `lib/board.sh -> lib/board/board.sh` back-compat symlinks at the lib root after the
regroup. `bin/` is not that: it is a deliberate, documented, forward stable interface
dir (a real seam), not a legacy back-compat symlink at the old path.

## After state

- `bin/board`, `bin/classify`, `bin/gate` exist, are executable, and forward to their
  subsystem entries.
- `lib/adopt.sh`'s injected CLAUDE.md block references `$KIT_ROOT/bin/classify lane
  classify "<task>"` and `$KIT_ROOT/bin/gate ledger`, not the two deep lib paths.
- `install.sh` deploys `bin/` (copy in bash install, symlink in plugin-compat) and
  removes it on uninstall.
- The WORKFLOW pointer block in `lib/adopt.sh` is UNCHANGED (it already points at the
  stable `$KIT_ROOT/WORKFLOW.md`, not a deep lib path; left untouched to keep the
  cross-track seam with sub-goal 12-root-slim clean).
- Docs record the new top-level dir (WORKFLOW doc-impact map, README project structure,
  architecture.md).

## Out of scope (boundary)

- The subsystems' internal logic and the config resolver (owned elsewhere).
- Rewriting every internal `bash lib/<sub>/<file>.sh` call-site; those are kit-internal
  and move WITH lib, so they are not the fragile consumer reach this spec fixes.
- Installing the `bin/` shims onto the system `PATH`; consumers reference
  `$DWARVES_KIT/bin/<name>` explicitly (the same `$DWARVES_KIT` they already resolve).
- The ops-toolkit `_meta/board` / `board-all` repoint itself: that lives in ANOTHER repo
  and ships as a documented follow-up (see the PR body), not in this dwarves-kit change.

## Verification

```
bash tests/test-stable-interface.sh
```

Proves: (1) each `bin/` shim resolves and forwards; (2) the adopt-injected block
references `bin/` not deep lib paths; (3) NEGATIVE CONTROL: with a consumer pointing at
the stable `bin/board`, renaming the internal `lib/board/board.sh` (and updating only the
one kit-owned wrapper line) keeps the consumer call GREEN, while a consumer pointing at
the deep lib path goes RED on the same rename.

Co-located proof: `docs/verification/SPEC-184-stable-interface/proof-of-done.md`.

## Design record

Design-bearing: 2 approaches (uber-dispatcher vs per-subsystem shims). Pick + rationale
recorded in `## Design` above; the pick is constrained by AGENTS.md's "no uber-dispatcher"
architecture statement.
