# Task-type registry (SPEC-044)

The second axis of the verification gate. `lib/task-type-classify.sh` maps a task
description to a **task type**; this table maps that type to the **proof artifact** it
owes, the **skill** that owns the methodology, and a **default proof class** (the rigor,
which `lib/proof-gate.sh` may override per the task's risk). `proof-gate.sh contract
"<desc>"` composes the two axes: the type's artifact, produced at the class's rigor.

**This is the extension point.** A new kind of work = one new row here (plus, if its
phrasing is novel, one keyword rule in `task-type-classify.sh`). No other code changes.

The table is parsed by `proof-gate.sh`: keep it a pipe table, one row per type, the
first column the exact type string emitted by `task-type-classify.sh`.

| task-type | artifact | owning skill | default class |
|---|---|---|---|
| eval | TEST-REPORT (5 pillars) + PROVENANCE | tool-eval-experiment | behavioral |
| research | cited report + verified sources | deep-research | behavioral |
| doc | doc-verifier confirms docs match code | /docs (doc-verifier) | inert |
| migration | dry-run on a copy + recorded run + rollback path | (kit native, stateful) | stateful |
| data-tool | recorded live run of the real commands (e.g. prove.py to docs/proof-of-done.md) | ops-tool-shape Done gate | behavioral |
| spec-feature | the real primary flow run end to end + tests/acceptance met | /execute task-verifier | behavioral |

Human override always wins; the type + class are suggestions. The class column is the
DEFAULT only; `proof-gate.sh` still upgrades to `stateful` when the task touches data or
deploys, and downgrades to `inert` for a cosmetic/tiny change, regardless of type.
