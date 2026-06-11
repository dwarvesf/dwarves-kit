# Task-type registry (SPEC-044)

The second axis of the verification gate. `lib/task-type-classify.sh` maps a task
description to a **task type**; this table maps that type to the **proof artifact** it
owes, the **skill** that owns the methodology, and a **default proof class** (the rigor,
which `lib/proof-gate.sh` may override per the task's risk). `proof-gate.sh contract
"<desc>"` composes the two axes: the type's artifact, produced at the class's rigor.

**This is the extension point.** A new kind of work = one new row here (plus, if its
phrasing is novel, one keyword rule in `task-type-classify.sh`). No other code changes.

The table is parsed by `proof-gate.sh` (columns 3/4/5 by index): keep it a pipe table, one
row per type, the first column the exact type string emitted by `task-type-classify.sh`;
new columns append AFTER `default class` so the indices stay stable.

The **agent** column names the executor (PHILOSOPHY §6 N1): `preassigned: <who>` for a fixed
owner, `dynamic: <rule>` when the executor is selected at dispatch. Each type's CYCLE (entry ->
phases -> exit) lives in `WORKFLOW.md` `## Type loops` (one source: WORKFLOW owns loops the same
way it owns lane paths; this registry owns artifact/owner/rigor/agent).

| task-type | artifact | owning skill | default class | agent |
|---|---|---|---|---|
| eval | TEST-REPORT (5 pillars) + PROVENANCE | tool-eval-experiment | behavioral | preassigned: tool-eval-experiment runner (main session, /goal loop) |
| research | cited report + verified sources | deep-research | behavioral | dynamic: parallel research subagents, one persona per sweep angle |
| review | review report / spec `## Review`: verdict + findings (severity + Route per SPEC-078), each citing file:line | /kit:review (single) or /kit:review-team (multi-lens) | inert | preassigned: reviewer; review-team dispatch per the SPEC-069 escalation rule |
| doc | doc-verifier confirms docs match code | /docs (doc-verifier) | inert | preassigned: doc-verifier agent |
| migration | dry-run on a copy + recorded run + rollback path | (kit native, stateful) | stateful | preassigned: main session + task-verifier |
| data-tool | recorded live run of the real commands (generated run ledgers under docs/runs/; the hand-authored proof-of-done.md indexes them) | ops-tool-shape Done gate | behavioral | preassigned: ops-tool-shape owner (main session) |
| spec-feature | the real primary flow run end to end + tests/acceptance met | /execute task-verifier | behavioral | per lane: /execute workers + task-verifier |
| incident | INC-NNN incident record + verified recovery (the fired signal now silent) | incident-workflow (consumer) + /kit:debug | stateful | preassigned: main session + debug evidence ledger |
| reconcile | inventory with a verdict per item + reference-fix diff; a seeded drifted item is caught | doc-compaction / migrate-convention family | behavioral | preassigned: main; dynamic: parallel inventory subagents for estate-wide sweeps |
| operate | append-only run-ledger entry + a liveness/monitoring line | the procedure's owning runner skill + job-monitoring-onboarding | stateful | preassigned: the procedure's runner |
| planning | the plan/digest + the enqueued/re-ranked board rows | plan-for-goal / plan-for-mega-goal | inert | preassigned: lead session |
| learning | workbook + scored self-check (>= the track's bar) | consumer learning skills (learning-day-process etc.) | inert | preassigned: consumer learning skills |

Each type's TEST-DESIGN dialect lives in `test-design-standard.md` §5b (one spine, six
bodies); `/kit:test-plan` picks it from the type. Human override always wins; the type + class are suggestions. The class column is the
DEFAULT only; `proof-gate.sh` still upgrades to `stateful` when the task touches data or
deploys, and downgrades to `inert` for a cosmetic/tiny change, regardless of type.
