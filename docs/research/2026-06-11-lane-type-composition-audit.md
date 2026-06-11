# Lane x type composition audit (SPEC-074 / ID-066)

Date: 2026-06-11. Method: enumerate every routing surface, probe suspect pairs
live, classify findings per the disposition contract (fix+pin / board row /
accepted+documented).

## Surface inventory

| Surface | Count | Check |
|---|---|---|
| Lanes (depth matrix, `gate-ledger.sh plan <lane>`) | 5 (tiny 1, normal 8, full 13, bug 6, backfill 5 phases) | all non-empty, parser-derived |
| Types (loops table, WORKFLOW `## Type loops`) | 11 | parity-pinned vs registry |
| Types (registry, `task-types.md`) | 11 | artifact + skill + default class + agent per row |
| Types (classifier rules) | 11 | each anchored, SPEC-057/060/072 truth tables |

## Pair probes (live)

| Phrasing | Lane | Type | Verdict |
|---|---|---|---|
| fix the crash in the prod gateway, alert firing now | bug | incident | composition fact 2: incident content, bug gates |
| fix a typo in the incident runbook | tiny | incident | composition fact 1: inert short-circuit, coherent |
| migrate the ledger schema to the new column layout | full | migration | coherent (stateful dialect, full gates) |
| run the monthly payroll close | normal | operate | coherent |
| research prior art for pull-based kanban | normal | research | coherent |
| reconcile the drifted plist estate against repo templates | normal | reconcile | coherent |
| evaluate which OCR model is fastest on the mini | normal | eval | coherent |
| write its AGENTS.md (+ for the legacy repo) | ~~normal~~ backfill | spec-feature | F2: regex missed its own documented example; FIXED |

## Findings + dispositions

- **F1 composition undefined** -> fix: `WORKFLOW ### Lane x type composition`
  (type = content contract, lane = evidence contract, skip-with-loop-note mapping,
  3 precedence facts). Pinned.
- **F2 backfill self-example miss** -> fix + 2 failing-first pins.
- **F3 tiny+heavy-type** -> verified already coherent via the SPEC-071 proof-class
  order; pinned as a composition fact so the order change would surface here.

No 55-cell table: the two-axis rule covers every pair; a per-pair table would
fossilize and drift (decision recorded in SPEC-074).
