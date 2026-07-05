# Sub-goal 03: Prose-RAG semantic retrieval

**Time budget:** ~3-5 hours loop work (new tool)
**Depends on:** none
**Branch:** feat/cc-elevation-03-rag
**PR base:** main

## Outcome

A new `tools/prose-rag/` builds a local semantic index over my prose corpus (`tieubao/til`, `ops-toolkit/research/`, `ops-toolkit/_meta/learned-ledger.md`) using a local embedding model on the Air (fastembed, ONNX/CPU), stored in sqlite-vec. A `UserPromptSubmit` hook embeds the incoming prompt, retrieves the top-k most relevant prior notes above a relevance floor, and injects them as `additionalContext`, so I stop re-deriving things I have already written.

## Quality bar

Nothing private leaves the Air: embeddings are local, no cloud call. The injector adds well under ~100ms on a warm index, and a relevance floor keeps it silent when nothing is genuinely related (no noise injection). Index rebuild is one command.

## How to close the loop

- `prose-rag index` builds the sqlite-vec index over the three corpora; `prose-rag query "<text>"` returns ranked notes with scores.
- Seeded check: query a phrase you know is in `research/` (e.g. from the elevation note) and confirm that note ranks top-1; query a nonsense string and confirm the relevance floor returns nothing.
- The `UserPromptSubmit` hook, given a sample prompt payload, emits `additionalContext` containing the matched note title for an on-topic prompt and emits nothing for an off-topic one (negative control).
- Latency: `query` on a warm index returns well under the budget; record the number in the proof.
- Lane via lane-classify; as a new tool it owes `tools/prose-rag/docs/proof-of-done.md` with a recorded index+query run.

**Done =** `tools/prose-rag/` indexes til+research+ledger locally via fastembed into sqlite-vec, `query` ranks a seeded note top-1 and a nonsense query returns nothing, the UserPromptSubmit hook injects matched context on-topic and stays silent off-topic, with proof-of-done + wiring runbook, on PR #NN with green CI.

## Scope edges

**In:** `tools/prose-rag/` (indexer, query CLI, the UserPromptSubmit hook script, tests, runbook, proof).
**Out:** activating the hook in ~/.claude (post-merge deploy); the Obsidian `.smtcmp` DB (do not touch); Voyage AI; the vault corpus.
**Not:** re-implementing codebase-memory/Serena (code-structure, wrong tool, see the note's Q1); a daemon to auto-reindex (later sweep territory).

## Open knobs (do NOT flip without Han)

- Cloud embedder (Voyage AI) instead of local fastembed: OUT for v1 (would send private prose off the Air).
- Including the Obsidian vault in the corpus: OUT for v1 (til + research + ledger only).

## Where to look

fastembed (ONNX embedding models, e.g. bge-small), sqlite-vec, the corpora paths above, the UserPromptSubmit hook payload shape + the `additionalContext` contract, `tools/tide/` for tool voice + shape.

## PR body

Outcome: a `tools/prose-rag/` tool that semantically indexes my prose (til+research+ledger) locally and injects relevant prior notes per prompt via a UserPromptSubmit hook.
Verify: `prose-rag index` then `prose-rag query` (seeded note ranks top-1, nonsense returns nothing); hook injects on-topic, silent off-topic; local-only, no cloud call.
Roadmap: `_meta/megagoals/cc-elevation/ROADMAP.md` (sub-goal 03).

## Notes
