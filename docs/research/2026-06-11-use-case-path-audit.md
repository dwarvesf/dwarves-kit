# Use-case path audit: research, autoreview, build-experiment (SPEC-075 / ID-065)

Date: 2026-06-11. Method: 3-4 realistic phrasings per loop shape, both classifiers
live, prescribed path read from the loops table + registry, then compared against
the operator's existing skills for the same ground (deep-research, code-review /
security-review, tool-eval-experiment, ops-toolkit research/ + experiments/
conventions). Full trace by a read-only research agent; dispositions here.

## Per-loop verdicts

| Loop | Routing today | Path coherent? | Kit vs operator skill |
|---|---|---|---|
| research | 2/3 phrasings -> research type | YES (grill -> think -> sweep -> verify-claims -> cited report; exit /kit:ship; artifact SPEC + ops-toolkit research/) | kit STRICTLY BETTER (adds gates, proof contract, telemetry); no conflict, skills remain the execution layer |
| autoreview | 0/3 -> all fell to spec-feature | NO , no `review` type exists; /kit:review[-team] commands exist but are UNROUTED from intake | capability present, routing absent; HIGH |
| build-experiment | 1/3 -> eval | YES when routed (eval loop: frame metrics -> seed data -> ladder -> TEST-REPORT) | kit GOOD but under-anchored; complements tool-eval-experiment skill |

## Misfires + dispositions (the SPEC-061 contract)

| # | Phrasing | Got -> expected | Disposition |
|---|---|---|---|
| 1 | deep-dive how Z works across our repos and snapshot it | spec-feature -> research | FIX + pin (deep-dive..snapshot anchor; bare `snapshot` deliberately NOT anchored: `snapshot the database` routes to migration via its own keywords, pinned) |
| 2-4 | review this PR adversarially / multi-lens review the diff / audit branch for security | spec-feature -> (review) | BOARD ROW ID-074: a 12th `review` type is a taxonomy decision (operator gate); lanes/registry/loop row + anchors ship together when approved |
| 5 | spin up a quick experiment to test if X works | spec-feature -> eval | FIX + pin |
| 6 | trial a new library, throwaway code, log findings | spec-feature -> eval | FIX + pin (negatives: `experimental flag` stays spec-feature, `clinical trial data importer` not eval) |

## Comparison conclusions

- No destination conflicts: kit loops orchestrate; operator skills execute. The
  kit's research exit artifact (cited report) is COMPATIBLE with the operator's
  ops-toolkit/research/ convention; the kit makes no structural claim about the
  landing path (review F5: an earlier single-bookkeeping wording overclaimed).
- The kit path is strictly better WHERE ROUTED (phase-0 grill, proof contract,
  ledger telemetry). The gap class is recall, not capability or conflict.
