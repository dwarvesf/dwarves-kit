# Test design: pull-kanban prior-art survey (ID-047, research dialect)

Designed BEFORE the sweep, per test-design-standard §5b (research -> claim-verification
matrix). Hypothesis: at least three prior arts exist with directly reusable mechanics for
(a) pull-based work boards driven by agents and (b) dynamic persona/agent selection at
dispatch; falsified if the verified survey finds fewer than three with concrete, citable
mechanics (then the next phase designs from first principles instead).

## Claim-verification matrix (the dialect's core)

Every load-bearing claim in the report MUST appear here with its verification method and
result. Methods: `local-probe` (a command against a repo on this machine), `web` (a fetched
source), `[UNVERIFIED]` (stated honestly, never load-bearing).

| # | Claim (to verify during sweep) | Method | Check |
|---|---|---|---|
| C1 | OpenClaw ships a Workboard: a persistent board agents read/write work items from | local-probe | grep the openclaw tool docs for the Workboard surface + its storage |
| C2 | OpenClaw ships persona catalogs used to select an agent profile at dispatch | local-probe | locate the catalog files + the selection mechanism |
| C3 | GSD v2 is a standalone runtime with its own task DAG/scheduling (the thing PHILOSOPHY hands depth to) | local-probe + web | PHILOSOPHY "GSD v2 disambiguation" + the gsd-build/gsd-2 repo surface |
| C4 | Claude Code natively exposes task/queue surfaces an agent can poll (TaskCreate/TaskList; cron/schedule for recurrence) | local-probe | the harness tool registry visible in this session |
| C5 | The kit's own goal-registry already implements cross-session claims (the pull's collision guard) | local-probe | lib/goal/goal-registry.sh claim/list semantics (exercised live this run) |
| C6 | At least one external multi-agent framework treats role/persona selection as a first-class dispatch concern | web | one citable source; else mark [UNVERIFIED] and exclude from conclusions |

## Coverage notes

- Happy path = the matrix above lands all checks. Boundary = a claim verifying PARTIALLY
  (e.g. Workboard exists but is human-driven, not agent-pulled): record the nuance, do not
  round up. Failure-injection = a source unreachable: mark [UNAVAILABLE: reason], never
  substitute memory for a probe.
- Negative control (falsifiability): C6 is designed to be refutable by absence; if the web
  probe cannot produce a concrete citation, the claim is dropped from the report's
  conclusions, proving the matrix gates content rather than decorating it.
- Each run of this survey is recorded immutably under `runs/`.

Done = every load-bearing claim in the final report traces to a row here with a recorded
result; report lands at docs/research/2026-06-10-pull-kanban-prior-art.md.
