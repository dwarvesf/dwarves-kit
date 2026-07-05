# Sub-goal 04: semantic signals (LLM-derived)

**Time budget:** ~4-5h · **Depends on:** none · **Branch:** feat/cc-elev-r3-04-semantic · **PR base:** main

## Outcome

A cheap LLM pass (Claude Haiku via API or `claude -p`, the cc-harvest pattern, NOT mini.ollama)
infers two signals a deterministic parser cannot, emitted as **proposals only**:

1. **topic/domain drift** , cluster session prompts to show what I actually spend Claude Code on (ops vs learning vs trading vs ...), the truth about where my time goes.
2. **self-correction rate** , how often I or the user correct a claim mid-session (a reliability-trend proxy).

Output is a digest section (and/or a `cc-observe semantic`-style command) that **writes nothing
durable**: it proposes, the human reads. Same propose-don't-dispose contract as cc-intel.

## Quality bar

Haiku only (cheap, no mini.ollama per the cc-elevation cost rule). Bounded: cap tokens/run, sample
or window the transcripts rather than feeding everything. Deterministic fallback / clear
`_unavailable_` when no API key. Honest about being an estimate (NLP, noisier than the deterministic
views) , label it as such in the output. Read-only; never writes the ledger/GLOSSARYs/boards.

## How to close the loop

- Build the pass (new module or a cc-intel section). Prompt Haiku over a windowed prompt-set; parse a structured result (topic buckets + correction count).
- Fixtures: a tiny synthetic transcript set with a known topic mix + a known self-correction; a test asserts the parser handles the model's structured output AND the no-API-key path degrades cleanly (negative control = clean fixture yields no false proposals).
- Verify: run once on real recent sessions; eyeball that the topic split is believable and nothing durable was written (`git status` clean except the digest artifact).
- Proof-of-done for the new module (or the cc-intel feature entry); note the token cap + the estimate caveat.

**Done =** an LLM pass proposes topic/domain drift + self-correction rate, propose-only (zero durable writes proven), bounded + degrades without a key, on fixtures + a clean-fixture negative control; on PR #NN.

## Scope edges

**In:** the two semantic signals, the Haiku pass, fixtures, proof, the estimate caveat.
**Out:** acting on proposals (human); delivery (SG-05); deterministic signals (01-03).
**Not:** mini.ollama; auto-writing any durable home; unbounded full-history scans.

## Where to look

cc-harvest (the existing PreCompact Haiku pass: `tools/` or the cc-elevation r1 SG-04 / r2 SG-09 work) for the Haiku-via-`claude -p` pattern + token-bounding, cc-intel's propose-only synthesis section, the research note's "semantic signals (LLM-derived) , skip-as-noise-unless" caveat (Han chose to build them anyway).

## PR body

Outcome: LLM-derived semantic signals (topic/domain drift + self-correction rate), propose-only.
Verify: clean-fixture negative control yields no false proposals; no-key path degrades; nothing durable written.
Roadmap: `_meta/megagoals/cc-elevation-r3/ROADMAP.md` (sub-goal 04).
