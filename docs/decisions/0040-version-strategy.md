# 0040. Version strategy: bump on real usage data, not on a calendar

Date: 2026-10-25
Status: Accepted (moved from `docs/PHILOSOPHY.md`, where it sat as a section)
Relates-to: `docs/PHILOSOPHY.md` section 5 (Evolution strategy), `VERSION`, `docs/CHANGELOG.md`

## Decision (one line)

Version bumps happen when real usage exposes the limits of the current version, not on a calendar schedule, and the plan below is direction only.

## Context

`docs/PHILOSOPHY.md` carried a "Version strategy" list that named v1.2 as current. The kit is far past it, and the `VERSION` file and `docs/CHANGELOG.md` own the current version. The list is a decision about how the kit plans versions, so it lives here and PHILOSOPHY keeps a pointer.

## The plan as written

- **v1.0-v1.1**: Commands + hooks. Manual iteration on prompts. Sequential task dispatch.
- **v1.2**: Verification pipeline (task-verifier + fix-agent + retry loop). Bootstrapping router (/start). Path-scoped rules. Context-readiness v2 with command suggestions.
- **v2.x** (pending real usage data): Prompt-type hooks (anti-rationalization upgraded to Haiku evaluation). /qa command with browser testing. Agent Teams parallel execution. Plugin marketplace packaging.
- **v3.x**: Agent-type hooks for deep verification. Multi-runtime support (Codex, Gemini). AutoResearch-optimized prompts.

The list is historical for v1.x. The v2.x and v3.x lines are direction, not commitments; several landed in other shapes (plugin packaging in ADR-0009, a partial Codex port), and the rest are unscheduled.

## Consequences

- No timeline commitment. A version bump is a release decision (`bin/release`), made when usage data justifies it.
- A doc that needs the current version reads `VERSION`, never a hand-written "(current)" marker.
