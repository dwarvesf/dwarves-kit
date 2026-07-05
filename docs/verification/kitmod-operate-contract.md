# Verification: operate-contract refresh (kit-modularity SG-05)

Flat back-compat proof shape for the ship-gate. Canonical proof:
`docs/proof/kitmod-operate-contract.md`.

## What was verified

`AGENTS.md` + `WORKFLOW.md` refreshed to the post-modularity surface. Retired-surface
tokens carry zero live references; the new surface (standalone `<subsystem> <verb>`,
`stats`, layered `install.sh --with` + `kit.toml [modules]`, subsystem modules) is
positively referenced in both files.

## Green run (retired tokens -> zero, the negative control)

```
$ grep -nE 'ledger-observatory|bash tools/|tools/[a-z]|all-hooks install|wires everything' AGENTS.md WORKFLOW.md
(no output)

per-token counts across both files:
  ledger-observatory  0
  bash tools/         0
  tools/[a-z]         0
  all-hooks install   0
  wires everything    0
```

## Positive control (new tokens present, both files)

```
stats:            AGENTS=3 WORKFLOW=2
<subsystem> <verb>: AGENTS=1 WORKFLOW=1
--with:           AGENTS=1 WORKFLOW=1
[modules]:        AGENTS=1 WORKFLOW=1
subsystem module: AGENTS=2 WORKFLOW=1
kit.toml:         AGENTS=1 WORKFLOW=1
```

## Path existence (SG-01 restructure did not leave a dangling path)

All 19 unique `lib/<subsystem>/*.sh` paths referenced in the two files resolve on disk
(board, classify, gate, goal, queue, session, spec, telemetry subsystems).

## doc-verifier

`kit:doc-verifier` over both files vs the live codebase: PASS, 0 contradictions.

## Result

PASS. Zero stale references; new command/install surface correctly represented;
lane/gate semantics unchanged (surgical).
