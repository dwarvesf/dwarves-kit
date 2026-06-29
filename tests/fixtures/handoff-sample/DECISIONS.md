# WARM LEDGER (append-only: invariants + dead-ends, read on demand)

Never inlined into the prompt; the orchestrator injects only a pointer to this file.

## Invariants
- The driver stays non-LLM (DEC-004). Do not add an LLM coordinator.
- A sub-goal advances ONLY when it flips its own ROADMAP box (grounded completion).

## Dead-ends
- 2026-06-29: tried capping subagent returns in `/kit:execute` prose -> every dispatcher would
  need the same edit. Belongs in `agents/*.md` instead.
- 2026-06-29: passing the prompt as an argv arg tripped secret-guard on `${}` in a handoff body.
  Fixed by stdin temp-file injection.
