# examples/hello-spec

A small, self-contained example showing what dwarves-kit produces when you run it on a real (tiny) feature.

## What this shows

A hypothetical Python CLI called `spm` ("simple package manager") needs a `--version` flag. This directory contains the three files dwarves-kit would generate or rely on to ship that change end-to-end. Each is a normal output, not a mock.

The point: see what `.planning/SPEC.md` actually looks like; see how `CLAUDE.md` anchors a contractor's session; see how the kit's commands chain.

## The three files

### `CLAUDE.md`
Project anchor. Read by Claude Code at session start, by `/user:spec` for stack detection, by every worker subagent in `/user:execute`. Tells Claude what the project is, what the stack is, where the spec lives, and what code-quality rules apply.

Generated once when the project is set up. Updated by `/user:docs` when the stack drifts.

### `.planning/SPEC.md`
The shared contract. Written by `/user:spec` (with optional adversarial review via `/user:spec-validate`). Read by `/user:execute` to dispatch worker subagents per task. Read by `/user:review` to check spec-compliance. Mutated only by the spec phase; treated as immutable during build.

Status field cycles: `DRAFT` → `VALIDATED` → tasks marked `[x]` as they complete with verification.

### `.planning/` (the directory)
Convention from GSD (per ADR-002). All planning artifacts live under one directory so hooks (`spec-drift-guard`, `context-readiness`) can find them at predictable paths. The kit's `/user:spec` creates this directory; nothing should write outside it during planning.

## How the kit picks it up

```
contractor opens project
   |
   v
SessionStart hook (context-readiness) sees .planning/SPEC.md status=VALIDATED
   |
   v
hook injects "next: /user:execute" into Claude's context
   |
   v
contractor types /user:execute
   |
   v
worker subagent dispatched per task with this CLAUDE.md + this SPEC.md as context
   |
   v
task-verifier subagent checks the worker's output against SPEC.md acceptance criteria
   |
   v
PASS -> next task; FAIL:fixable -> fix-agent (max 2 retries); FAIL:escalate -> human
```

## Reading order

1. Read `CLAUDE.md` first — it's the project anchor a contractor sees first.
2. Then `.planning/SPEC.md` — the actual feature plan.
3. Notice: no `--version` code yet. The spec is the input to `/user:execute`. The example stops at "spec ready to build", not "feature implemented", to keep the example readable.
