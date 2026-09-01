# SG-02: two-tier feed-forward handoff

Merge policy: gate
Time budget: ~1 session
Depends on: #81 (orchestrate.sh phase 1)
Model: sonnet
Effort: medium

## Directional outcome
The handoff carries forward not just "files located" but dead-ends, fixed decisions, the exact
next action, and narrow read-pointers, so a fresh sub-goal session skips re-discovery, without
the handoff itself bloating into a new marathon.

## Done =
`lib/orchestrate.sh` writes/injects a HOT `HANDOFF.md` (overwritten each transition; carries
next-sub-goal + exact first-action + read-pointers as `file:line`) and maintains a WARM
`DECISIONS.md` ledger (append-only: invariants + dead-ends, read on demand). The orchestrator
injects the hot handoff in full + a pointer to the warm ledger. The hot handoff is size-capped.
The handoff/ledger contract is documented. `tests/test-orchestrate.sh` covers the tiering +
injection. PR opened.

## Close the loop (verification)
```
bash tests/test-orchestrate.sh         # hot-handoff overwrite + warm-ledger append + injection
```

## Scope edges
`lib/orchestrate.sh` + its test + the handoff contract doc. Cap the hot handoff (e.g. N lines).
Do NOT dump the whole decisions ledger into every prompt (that recreates the problem).

## Where to look
SPEC-087 Mechanism B, `lib/orchestrate.sh`, the 2026-06-29 handoff-optimization discussion
(dead-ends / next-action / read-pointers / hot-warm tiering).

## Proof expectation
A run-table, plus a sample `HANDOFF.md` + `DECISIONS.md` pair committed as a fixture. Full
reviewable proof (behavioral).

## PR body
feat(kit): two-tier feed-forward handoff (hot HANDOFF + warm DECISIONS ledger). Implements
SPEC-087 Mechanism B. Gated for team review.

## Borrowed from pi-swarm (2026-06-29)
- Inject the prompt + handoff via a TEMP FILE, not a shell-interpolated arg (`spawn.ts createArgs --message-file`). Fixes the backtick / ${} / secret-guard bug class we keep hitting when building the session prompt.
- Wording: "Report findings IN the record, not your response text" , the next session reads HANDOFF, not the transcript. See `research/2026-06-29-pi-swarm-comparison.md`.
