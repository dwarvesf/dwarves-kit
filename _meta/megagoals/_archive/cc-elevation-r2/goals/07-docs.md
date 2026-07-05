# Sub-goal 07: Round-2 research update + Monitor/LSP usage cheatsheet

**Time budget:** ~1-2h (docs)
**Depends on:** none
**Branch:** feat/cc-elev-r2-07-docs
**PR base:** main

## Outcome

Capture this session's round-2 analysis durably and the two "habit" items so they are not lost: (a) append a "Round 2" section to `research/2026-06-14-claude-code-events-tools-elevation.md` (the expanded event surface, the coverage matrix, the ranked frontier, what shipped); (b) a concise cheatsheet for the two habits, use the `Monitor` tool for reactive CI/PR/log watching instead of poll loops, and use the `LSP` tool for code/symbol navigation instead of grep-guessing, with one concrete example each, cross-linked from the research note.

## Quality bar

Docs match reality (the tools exist + the examples run). Concise; no narrative. Privacy: keep the no-account-ID / no-NDA hygiene (private research, but stays clean for a future til distill).

## How to close the loop

- Append the Round-2 section + write the Monitor/LSP cheatsheet (in the research note or a linked til-candidate); cross-link.
- doc-verifier pass: the tool names + example invocations are correct against current Claude Code.
- Lane via lane-classify (docs lane).

**Done =** the research note has a Round-2 section (surface growth + coverage matrix + ranked frontier + shipped status) and a Monitor/LSP usage cheatsheet with a worked example each, cross-linked; doc-verified; on PR #NN.

## Scope edges

**In:** the research-note Round-2 section + the Monitor/LSP cheatsheet.
**Out:** building anything (Monitor + LSP are existing tools); publishing to til (privacy-strip later if it graduates).
**Not:** re-documenting the shipped tools (their own READMEs hold that).

## Where to look

This session's round-2 tables, the Monitor + LSP tool docs, the existing research note structure.

## PR body

Outcome: Round-2 elevation analysis appended to the research note + a Monitor/LSP usage cheatsheet (the two habit items captured).
Verify: tool names + examples correct (doc-verifier); cross-links resolve.
Roadmap: `_meta/megagoals/cc-elevation-r2/ROADMAP.md` (sub-goal 07).

## Notes
