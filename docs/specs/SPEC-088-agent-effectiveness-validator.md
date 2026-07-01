# SPEC-088: Agent-effectiveness validator

Status: DRAFT
Date: 2026-06-29
Lane: full (new read-only validator surface + tests)
Type: feature
Relates-to: ADR-0028 (autonomous-loop hardening), ADR-0005 (read-only verifier pattern), ADR-0015 (integration-checker), ADR-0016 (doc-verifier), SPEC-082 (finding-validators), ADR-0025 (diff-keyed proof gate)
Board: kit-hardening mega-goal SG-A (ops-toolkit `_meta/megagoals/kit-hardening`); kit intake ID pending

## Problem
The kit validates an agent `.md`'s STRUCTURE (test-meta: frontmatter, name, model enum) and the OUTPUT of spawned workers (task-verifier, integration-checker, finding-validators). Nothing validates an agent's EFFECTIVENESS: that its tools are minimal-yet-sufficient, its description triggers on the right cases (and not the wrong ones), and its instructions actually produce a good result on a representative task. This is invisible today (predefined agents are trusted as hand-authored) and becomes load-bearing once a meta-agent (ops-toolkit token-optim-v3 SG-05) generates agents from descriptions: a structurally-valid but ineffective generated agent passes every existing check.

## Decision
Add an `agent-effectiveness` read-only validator, a new instance of the ADR-0005 read-only-verifier pattern (same shape as integration-checker / doc-verifier / finding-validators). Given an agent `.md`, it returns a verdict across four lenses, each with file:line evidence:
- **Tools** , minimal AND sufficient for the stated job (flags both over-grant and missing capability).
- **Description / trigger** , would fire on the intended cases and NOT misfire on adjacent ones (refuter framing, per SPEC-082).
- **Instructions** , testable against a named representative task; ambiguous or contradictory instructions flagged.
- **Tier** , model/effort fits the work (not Opus for a mechanical lint, not Haiku for a hard judge).

Read-only (read-only tool subset, no Edit/Write/bare Bash, per ADR-0015). Advisory + fail-safe (SPEC-082): an infra failure never silently passes; the agent stays `unvalidated` and the verdict treats it as live-risk. Diff-keyed (ADR-0025): runs on NEW or CHANGED agent definitions, not every agent every run. Surfaced at the phase + visible at ship; never a mid-flight hard block (ADR-0024 + PHILOSOPHY).

## Acceptance criteria
- AC1 [negative control]: given a deliberately-bad agent (over-granted tools OR a misfiring description OR contradictory instructions), the validator flags the specific defect with file:line.
- AC2: given the existing predefined kit agent roster, the validator passes them with no false-positive defects.
- AC3: the validator uses only read-only tools (assert no Edit/Write/bare-Bash in its definition).
- AC4 [fail-safe]: an injected infra failure leaves the agent `unvalidated`, never silently `passed`.
- AC5 [gated]: an unchanged agent is not re-validated in a run with no agent-definition changes (diff-keyed).

## Tasks
- T1: author the `agent-effectiveness` validator agent `.md` (read-only tools; four-lens refuter framing).
- T2: wire it diff-keyed into the phase where agents are authored/changed; advisory + ship-visible.
- T3: fixtures , one good agent + one planted-bad agent per defect lens.
- T4: `tests/test-agent-effectiveness.sh` covering AC1-AC5.

## Verification
```
bash tests/test-agent-effectiveness.sh   # AC1 planted-bad flagged · AC2 roster clean · AC3 read-only · AC4 fail-safe · AC5 gated
```
Proof-of-done: a table-first run-table (ADR-0026) with the planted-bad catch, the clean-roster pass, and the fail-safe negative control.

## Review
Integration-branch + gated-final (ADR-0028 merge posture): this sub-goal's PR targets `mega/kit-hardening` and auto-merges past its OWN ship-gate (V-model phase reviews recorded + green checks + proof-of-done), NOT a per-PR human ship. The single human review (`/kit:review-team`) runs once at the final `mega/kit-hardening -> master` PR. Per ADR-0028 this implements only AFTER the ADR is team-blessed.

## Out of Scope
- A hard pre-use gate on agents (stays advisory + ship-visible, like its sibling validators).
- Validating agent OUTPUT (task-verifier / integration-checker already do that).
- Generating or fixing agents (that is the meta-agent, ops-toolkit SG-05; this only validates).
- Batch validation frameworks (one-at-a-time, like finding-validators).
