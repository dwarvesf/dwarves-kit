# Task Backlog

In-flight or queued work on the kit. Completed cycles live in `docs/handoff/v<version>.md` (build notes) and `docs/retro/v<version>.md` (cycle retros). Per-release CHANGELOG entries are the canonical "what shipped" record.

## In-flight

(none right now; next cycle's spec will land in `.planning/SPEC.md`)

## v2 candidates (pending real usage signal)

Items here are NOT committed; they become real only after a spec is written and `/spec-validate` passes. Listed for visibility.

- Prompt-type anti-rationalization hook (Haiku evaluation instead of grep patterns). Needs ~30 false-positive logs from `~/.claude/dwarves-kit/logs/anti-rationalization.log` to justify the latency cost.
- `/qa` command with headless browser testing (requires Playwright).
- Agent Teams parallel task dispatch in `/execute`. Currently sequential by design (see `docs/PHILOSOPHY.md`, "Shallow and wide beats deep and narrow").
- `SessionEnd` hook for automatic knowledge capture.
- AutoResearch optimization of the `task-verifier` prompt. Needs 30+ real verification transcripts as eval corpus.
- Multi-harness packaging (Codex / Cursor / Gemini / OpenCode). Defer until real cross-harness demand.

## Parking lot (revisit if a real signal arrives)

- L5 orchestration (Nimbalyst integration). Not needed until 3+ concurrent sessions.
- AutoResearch loop for command prompt optimization. Manual iteration is faster at current volume.
- Agent-type hooks for deep verification. Custom subagents handle this today; revisit only if subagents prove insufficient.

## Source

Backlog format matches `ops-toolkit/_meta/BACKLOG.md`. Completed work is NOT mirrored here, to avoid drift with CHANGELOG.md and `docs/handoff/`.
