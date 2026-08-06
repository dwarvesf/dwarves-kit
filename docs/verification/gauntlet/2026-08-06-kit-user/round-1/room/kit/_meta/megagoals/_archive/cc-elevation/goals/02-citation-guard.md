# Sub-goal 02: Citation guard (file:line verification)

**Time budget:** ~1-2 hours loop work
**Depends on:** none
**Branch:** feat/cc-elevation-02-cite
**PR base:** main

## Outcome

A `Stop` hook reads the session transcript, extracts every `path:line` (and bare `path`) reference in my final message, and verifies each resolves: the file exists and has at least that many lines. Unresolved refs are logged by default so I never trust a hallucinated citation; a strict env flag (`CC_CITATION_STRICT=1`) promotes logging to a block.

## Quality bar

Fast and quiet: pure shell/grep over the transcript, no model call, no perceptible delay. Zero false positives on code-fenced examples and URLs. Log-only until tuned, so it never blocks a legit Stop on day one.

## How to close the loop

- The hook script in `tools/cc-citation-guard/`, given a sample Stop payload whose `transcript_path` points at a fixture with one BAD ref (`nope/missing.py:999`) and one GOOD ref (a real file:line in this repo): logs exactly the bad ref, passes the good one.
- With `CC_CITATION_STRICT=1`, the same bad-ref fixture makes the hook emit a block (exit 2 or `{"decision":"block"}`); without it, exit 0 + a log line.
- Fixtures + a test live under `tools/cc-citation-guard/tests/`. Confirm no false positive on a fixture whose message contains a URL and a fenced code path.
- Wiring runbook explains adding it to the dotfiles Stop array (post-merge deploy).
- Lane via lane-classify; owes `tools/cc-citation-guard/docs/proof-of-done.md`.

**Done =** `tools/cc-citation-guard/` ships a Stop-hook that, on the fixtures, logs a bad file:line and passes a good one in default mode and blocks in strict mode with no URL/code-fence false positives, with tests + runbook + proof-of-done, on PR #NN with green CI.

## Scope edges

**In:** the Stop-hook script, transcript parsing, fixtures, tests, runbook, proof, under `tools/cc-citation-guard/`.
**Out:** installing it into ~/.claude (runbook's post-merge step); semantic verification of whether the cited line *means* what was claimed (that is Path B / on-demand `/verify`).
**Not:** rewriting my message, a model call, blocking-by-default, touching other hooks.

## Where to look

The Stop hook JSON shape (`transcript_path`), the existing style-guard hooks for the script + exit-code convention, the transcript JSONL last-assistant-message format.

## PR body

Outcome: a Stop hook that verifies file:line citations in the final message; log-only by default, blocks under `CC_CITATION_STRICT=1`.
Verify: run the hook against `tests/fixtures` (bad + good ref); see the log in default mode, the block in strict mode, no false positive on URL/code-fence.
Roadmap: `_meta/megagoals/cc-elevation/ROADMAP.md` (sub-goal 02).

## Notes
