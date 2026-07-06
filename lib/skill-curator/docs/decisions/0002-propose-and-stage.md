# ADR 0002: propose-and-stage, not auto-apply

**Date:** 2026-06-19
**Status:** accepted (SPEC-103 DEC-003)

## Context

Hermes auto-applies skills it authors (`guard_agent_created: false`): a self-improvement pass writes
straight into the live skill set. On Han's Claude Code cockpit, a wrong or injected skill that
auto-loads could mis-shape NDA / SDD / ops work across every future session. The blast radius is too
large to let the loop write the live library unattended.

## Decision

The reviewer stages drafts under `~/.claude/skill-proposals/<slug>/SKILL.md`, a path Claude Code does
NOT auto-load. The only writer of `~/.claude/skills/` is `bin/skill-review` (the `/skill-review`
human gate), which moves a draft in only after the operator vets it against
`superpowers:writing-skills`. Reject moves the draft to `_rejected/` (never `rm`). The staging path
IS the gate, and it is enforced structurally because the model has no write (ADR-0001).

**Scoped exception:** an optional `auto_promote` knob (default OFF) lets `skill-review auto` write a
`references/<topic>.md` INTO an existing umbrella under `skills/`, and only for a draft explicitly
tagged `cc-si-kind: references-add`. Never a new skill, never a SKILL.md-body/trigger edit. This is
the single automated path that touches `skills/`, deliberately limited to the lowest-risk class.

## Alternatives considered

- **Hermes-style auto-apply.** Rejected: cockpit blast radius.
- **No automated path at all (manual promote only).** Rejected as the sole option: the `auto_promote`
  knob exists for users who want closer Hermes parity, but it is off by default and references-only.

## Trade-offs

A human is in the loop for every real skill (more friction than Hermes). Accepted: the surfacing line
(ADR none; see architecture.md) keeps the backlog visible so drafts do not rot unseen.

## Open questions

Whether to widen `auto_promote` beyond references-add (e.g. to patches of agent-created umbrellas) is
deferred until the references-add path has real-world mileage.
