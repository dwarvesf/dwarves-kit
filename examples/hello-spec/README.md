# examples/hello-spec

A small, self-contained example showing what dwarves-kit produces when you run it on a real (tiny) feature.

## What this shows

A hypothetical Python CLI called `spm` ("simple package manager") needs a `--version` flag. This directory contains the files dwarves-kit would generate or rely on to ship that change end-to-end. Each is a normal output, not a mock.

The point: see what `docs/specs/SPEC-001-version-flag.md` actually looks like; see how `AGENTS.md` is the tool-agnostic front door a downstream repo inherits; see how `CLAUDE.md` anchors a contractor's session; see how the kit's commands chain.

## The files

### `AGENTS.md`, `WORKFLOW.md`, `docs/verification/README.md`, `.kit.toml`
What `/kit:adopt` writes into a repo today, copied from a real run. `AGENTS.md` is a small pointer (four rules plus the location of the full contract), not a copy of it. `WORKFLOW.md` is a pointer to the lanes and gate matrix in the installed kit. `docs/verification/README.md` is the proof marker: its presence opts the repo into the proof-of-done ship-gate. `.kit.toml` seeds the project's gate and module settings (`proof_of_done` and `lane_gates` start on). Claude Code enforces every hook and the verifier. Codex enforces the five hard controls. Under other runtimes `AGENTS.md` is advisory.

### `CLAUDE.md`
Project anchor. Read by Claude Code at session start, by `/kit:spec` for stack detection, by the builder subagent in `/kit:execute`. Tells Claude what the project is, what the stack is, where the spec lives, and what code-quality rules apply. The block at the bottom, between the `kit:adopt` markers, is what adopt appends: it imports `AGENTS.md` and points at the lane classifier.

Written once when the project is set up. Updated by `/kit:docs` when the stack drifts.

### `docs/specs/SPEC-001-version-flag.md`
The shared contract. Written by `/kit:spec` (with optional adversarial review via `/kit:spec-validate`). Read by `/kit:execute`, which hands the whole spec to one builder subagent. Read by `/kit:review` to check spec-compliance. Mutated only by the spec phase; treated as immutable during build.

Status field cycles: `DRAFT` → `VALIDATED` → tasks marked `[x]` as they complete with verification. The `Lane:` header is required: in an adopted repo the ship-gate refuses a push for a spec without one.

### `docs/specs/` (the directory)
Convention from GSD (per ADR-002). All planning artifacts live under one directory so hooks (`spec-drift-guard`, `context-readiness`) can find them at predictable paths. The kit's `/kit:spec` creates this directory; nothing should write outside it during planning.

## How the kit picks it up

```
contractor opens project
   |
   v
SessionStart hook (context-readiness) sees docs/specs/SPEC-001-version-flag.md status=VALIDATED
   |
   v
hook suggests "tasks in progress; say 'continue' (or /kit:execute, /kit:next)"
   |
   v
contractor types /kit:execute
   |
   v
ONE builder subagent gets this CLAUDE.md + this SPEC.md and builds every task
   |
   v
end verifiers run once over the whole build (task-verifier, then integration and
acceptance verifiers), checked against the SPEC.md acceptance criteria
   |
   v
PASS -> done; FAIL:fixable -> fix-agent (max 2 retries), re-verify; FAIL:escalate -> human
```

## Reading order

1. Read `AGENTS.md` first; it's the tool-agnostic front door (four rules and a pointer to the full contract).
2. Then `CLAUDE.md`: the Claude-Code project anchor that sits under the front door.
3. Then `docs/specs/SPEC-001-version-flag.md`: the actual feature plan.
4. Notice: no `--version` code yet. The spec is the input to `/kit:execute`. The example stops at "spec ready to build", not "feature implemented", to keep the example readable.

---

*Synthetic demo. The `spm` package and the feature it describes are fabricated for documentation purposes; there is no real `pip install spm`. The adopt files are real `/kit:adopt` output, and the spec follows the template in `commands/spec.md` (a normal-lane spec leaves the optional sections out).*
