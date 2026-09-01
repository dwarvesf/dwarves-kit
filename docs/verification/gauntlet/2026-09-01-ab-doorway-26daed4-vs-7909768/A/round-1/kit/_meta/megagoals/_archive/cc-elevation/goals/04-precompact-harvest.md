# Sub-goal 04: PreCompact auto-harvest

**Time budget:** ~2-4 hours loop work
**Depends on:** none
**Branch:** feat/cc-elevation-04-harvest
**PR base:** main

## Outcome

A `PreCompact` hook (and a `SessionEnd` twin) reads the session transcript and uses a cheap Claude model (Haiku via API or `claude -p`) to extract durable decisions, gotchas, and concepts as candidate rows for `_meta/learned-ledger.md`, dedups them against the existing ledger + the learning GLOSSARYs, and appends only the new ones as `status: queued`. It never writes to a durable home; the existing manual flush stays the gate.

## Quality bar

Auto-stage, manual-flush: the hook only ever adds `queued` rows, never touches GLOSSARY/til/research. No new privacy exposure (the transcript is already in an Anthropic session). Noise-controlled: a dedup gate + a relevance threshold so trivial turns add nothing.

## How to close the loop

- The harvest script, given a fixture transcript with one clear decision + one concept already present in a fixture ledger: stages the new decision as a `queued` row and does NOT re-add the known concept (dedup proven).
- It writes nothing to any GLOSSARY/til/research path (assert those are untouched in the test).
- A trivial fixture transcript (chit-chat, no learnings) stages zero rows (negative control).
- Reconcile with backlog ID-033 (the SessionEnd knowledge-capture idea) so the two do not double-capture; document the boundary in the tool README.
- Lane via lane-classify; owes `tools/cc-harvest/docs/proof-of-done.md`.

**Done =** `tools/cc-harvest/` ships a PreCompact+SessionEnd harvest hook that, on fixtures, stages a new queued ledger row, dedups a known one, writes nothing to durable homes, and stages nothing for a trivial transcript, with proof-of-done + runbook, on PR #NN with green CI.

## Scope edges

**In:** `tools/cc-harvest/` (harvest hook script, the Haiku call, dedup against ledger + GLOSSARYs, fixtures, tests, runbook, proof).
**Out:** the flush step (stays manual / learning-ledger skill); activation in ~/.claude (post-merge); any write to a durable home.
**Not:** a local model (use Haiku); changing the learning-ledger schema; the cross-session synthesis (that is 06).

## Where to look

The PreCompact + SessionEnd hook payload shapes (`transcript_path`), `_meta/learned-ledger.md` schema + the learning-ledger skill, the learning GLOSSARYs for the dedup set, the Anthropic Haiku API / `claude -p` headless.

## PR body

Outcome: a `tools/cc-harvest/` PreCompact+SessionEnd hook that auto-stages deduped `queued` learnings into the ledger using Claude Haiku, never writing to durable homes.
Verify: run the harvest on fixtures (new decision staged, known concept deduped, trivial transcript stages nothing, durable homes untouched).
Roadmap: `_meta/megagoals/cc-elevation/ROADMAP.md` (sub-goal 04).

## Notes
