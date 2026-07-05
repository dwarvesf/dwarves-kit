# Sub-goal 01: vcc-extract-poc

**Merge policy:** auto (ops-toolkit-owned, machine-verifiable)
**Time budget:** ~1 session
**Proof:** run-table , reduction % on a real transcript + a fidelity check (extracted form contains
the seed's hand-labeled load-bearing anchors) + a determinism check (same input twice = identical
output, `cmp`-clean) + a negative control (a known-absent anchor is NOT hallucinated in).
**Depends on:** none
**Branch:** `experiment/v3-vcc-poc`
**PR base:** ops-toolkit `main`

## Outcome
A deterministic, no-LLM extractor reads a real Claude Code transcript JSONL
(`~/.claude/projects/.../*.jsonl`) and emits a compacted view (session goal, files+changes,
decisions, commits, outstanding context, collapsed tool calls), proving pi-vcc's technique ports to
Claude Code's transcript schema. Same input always yields the same output.

## Quality bar
Pure extraction + formatting, zero model calls. Same transcript in, byte-identical compaction out.
The compacted view keeps every load-bearing fact a fresh session would need; if something is
dropped, recall (SG-03) can still get it. Reduction is the side effect; fidelity is the bar.

## How to close the loop
Build the extractor as an ops-toolkit experiment (`experiments/cc-deterministic-compaction/`).
Verify against a SCRUBBED seed transcript with hand-labeled anchors:
```
python3 -m pytest tests/ -q                 # or the chosen stdlib runner
./extract <seed-transcript.jsonl> > /tmp/out1.txt
./extract <seed-transcript.jsonl> > /tmp/out2.txt
cmp /tmp/out1.txt /tmp/out2.txt             # determinism: identical
# fidelity: every hand-labeled anchor present; negative control absent
```
Capture a run-table: reduction % (input vs output tokens via token-forensic or tiktoken), fidelity
(N/N anchors present), determinism (`cmp` clean), negative control (absent anchor not present).

**Done =** the extractor compacts a real CC transcript deterministically (`cmp`-clean on a re-run),
retains all hand-labeled load-bearing anchors, hallucinates none, and the run-table records the
reduction % plus all four checks.

## Scope edges
**In:** the no-LLM extractor + its tests + a SCRUBBED seed transcript fixture under
`experiments/cc-deterministic-compaction/`.
**Out:** the orchestrator handoff (SG-02), the recall CLI (SG-03), the interactive command (SG-04).
**Not:** any LLM call in the extraction path; a config system; non-CC transcript formats; a
"framework". Port the technique, not pi's code.

## Where to look
pi-vcc (`monotykamary/pi-vcc`): the normalize/filter/extract/merge pipeline + sticky-vs-volatile
sections. CC transcript schema: `~/.claude/projects/<slug>/*.jsonl` (the `cc-observe` tool already
parses these, reuse its schema knowledge). `tools/token-forensic/` for token counting. Design:
`research/2026-06-29-token-coherence-design.md`.

## PR body
feat(experiment): deterministic no-LLM CC-transcript compaction PoC (ports pi-vcc technique).
Verification: see close-the-loop run-table (reduction% + fidelity + determinism + negative control).
Part of token-optim-v3 (`_meta/megagoals/token-optim-v3/ROADMAP.md`).

## Notes
