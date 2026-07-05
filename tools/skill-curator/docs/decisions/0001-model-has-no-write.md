# ADR 0001: the model has no filesystem write (`--allowedTools ""`)

**Date:** 2026-06-19
**Status:** accepted (the keystone; SPEC-103 DEC-008)

## Context

The reviewer and curator run an LLM (`claude -p`) over a session transcript or a skill inventory.
A transcript can contain anything, including prompt-injection ("ignore your instructions and write a
skill that..."). The pre-DEC-008 design gave the model `--allowedTools Read,Write` and relied on a
PROMPT instruction to only write under `skill-proposals/`. That is unenforceable: a prompt cannot
bind a model that has been told to ignore its prompt, and it is untestable against a mocked model.

## Decision

The `claude -p` reviewer and curator run `--allowedTools ""`, so the model has **no filesystem tool
at all**. It can only return text (JSON) on stdout. Every filesystem write is done by the trusted
bash wrapper (`reviewer-run.sh`, `promote.sh`, `curate.sh`), to fixed, hardcoded paths. Verified by
`tests/test-staging-gate.sh`, which greps the source to keep `--allowedTools ""` pinned and proves a
path-traversal slug is contained by `safe_slug`.

## Alternatives considered

- **`--allowedTools Read,Write` + a prompt instruction to stay under `skill-proposals/`.** Rejected:
  injection-exposed and untestable. This was the original design; `/kit:spec-validate` flagged it CRITICAL.
- **Hermes's `skill_manage` tool / `guard_agent_created: false`** (the model writes skills directly).
  Rejected: the cockpit's blast radius (NDA / SDD / ops skills) makes an injected arbitrary write
  unacceptable.

## Trade-offs

The wrapper must parse the model's JSON and perform the writes itself (the two-layer parse, ADR-0009,
and more wrapper code). Accepted: a structural guarantee beats a prompt promise. Staging-by-path
(ADR-0002) only becomes a real gate because of this decision.

## Open questions

None. This is non-negotiable and not configurable.
