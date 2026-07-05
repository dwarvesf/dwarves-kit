# Sub-goal 03: Controlled prose-rag auto-inject

**Time budget:** ~2-3h
**Depends on:** none (prose-rag tool already merged, PR #265)
**Branch:** feat/cc-elev-r2-03-rag-inject
**PR base:** main

## Outcome

prose-rag already ships a UserPromptSubmit hook (opt-in, ~250ms). Activate it in a controlled way: gate it so it fires ONLY on recall/research-shaped prompts (e.g. "have I", "did I already", "what did I conclude", question-shaped research), not on every operational prompt, so the ~250ms tax is paid only when retrieval is likely useful. Tune the relevance floor, and keep it behind an opt-in env flag.

## Quality bar

No latency tax on operational prompts (file edits, git, lookups): the gate skips them. On a recall prompt it injects the top relevant prior notes above the floor; on an off-topic recall prompt it stays silent. Local only, no cloud embedder, no vault.

## How to close the loop

- Add the prompt-shape gate + opt-in flag to the prose-rag hook; calibrate the floor.
- Given a recall-shaped on-topic prompt, the hook injects matched note context; given an operational prompt OR an off-topic recall prompt, it injects nothing (two negative controls); record latency on a gated-out prompt (~0ms) vs a fired prompt.
- Lane via lane-classify; extend `tools/prose-rag/docs/proof-of-done.md`.

**Done =** the prose-rag UserPromptSubmit hook fires only on recall/research-shaped prompts (behind an opt-in flag), injects relevant prior notes above the floor, and stays silent on operational + off-topic prompts, with latency + two negative controls recorded; proof updated; on PR #NN.

## Scope edges

**In:** the prompt-shape gate + opt-in flag + floor tuning in `tools/prose-rag/`, the dotfiles one-line wire, proof.
**Out:** a re-indexing daemon, cloud embedder (Voyage), the Obsidian vault, changing the index format.
**Not:** always-on injection (the gate is the point).

## Open knobs (do NOT flip without Han)

- Cloud embedder / vault corpus: OUT (privacy).

## Where to look

The existing prose-rag hook (PR #265), the UserPromptSubmit `additionalContext` contract, the recall-phrase set (mirror the prose-rag skill's triggers), the 0.55/0.62 floors.

## PR body

Outcome: activate prose-rag auto-inject, gated to recall/research prompts (opt-in), so prior notes surface without taxing operational prompts.
Verify: fires on recall on-topic; silent on operational + off-topic; latency recorded; local-only.
Roadmap: `_meta/megagoals/cc-elevation-r2/ROADMAP.md` (sub-goal 03).

## Notes
