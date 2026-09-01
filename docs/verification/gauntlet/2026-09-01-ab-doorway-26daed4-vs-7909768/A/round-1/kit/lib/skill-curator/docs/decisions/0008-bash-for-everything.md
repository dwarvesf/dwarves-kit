# ADR 0008: bash for everything (no Go, no Python)

**Date:** 2026-06-19
**Status:** accepted (SPEC-103 DEC-001; the "flagged for override at review" was declined)

## Context

Han's stack default is "choose the language by fit; do not reflex-default to Python." The natural
candidates were bash, Go (a static daemon), or Python (matching cc-harvest, which is Python). SPEC-103
DEC-001 picked bash but flagged it for override at review; this ADR records the resolution.

## Decision

bash for the whole tool: hooks, the reviewer/curator wrappers, the two CLIs, install/uninstall. The
work is shell-shaped: Claude Code hooks ARE shell entry points; the reviewer/curator are thin
orchestration around a `claude -p` subprocess + `jq` parsing + `git mv`; there is no daemon and no
perf-critical or long-running path. `jq` (already on both hosts) does the JSON. The override to Go or
Python was considered and declined at review.

## Alternatives considered

- **Go** (single static binary, fast startup). Rejected: no daemon, no perf path; a binary build step
  buys nothing for a hook + `claude -p` + `git` orchestrator.
- **Python** (matching cc-harvest's language). Rejected: the hook surface is shell; the only non-shell
  need was JSON, which `jq` covers. Sharing a language with cc-harvest is not worth a runtime + venv
  for thin glue. (cc-harvest is Python because its dedup/ledger logic earned it; this tool's logic
  does not.)

## Trade-offs

Bash is harder to unit-test than Python, mitigated by the env-seam (ADR-0006) + 58 shell-level
checks. Cross-language with cc-harvest means the transcript parser is reimplemented in bash
(`transcript.sh`) rather than imported; accepted as a small, locked-by-fixture cost.

## Open questions

None. If a future feature needs real perf or stateful concurrency, revisit per-feature, not for the
whole tool.
