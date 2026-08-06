# Sub-goal 05R: retire ops-toolkit's ledger-observatory copy

**Merge policy:** auto
**Time budget:** 30-60 minutes
**Proof:** OVER-TEST: assertion + one named negative control (old CLI entrypoint no longer resolves / is clearly banner-redirected) + a grep sweep confirming no remaining ops-toolkit doc points at the old path as canonical
**Design:** commodity (a retire-and-point, same shape as 03R)
**Repo:** ops-toolkit
**Depends on:** 05K MERGED (dwarves-kit) , needs the exact new path + PR SHA for the pointer banner
Model: sonnet
**Branch:** `chore/retire-ledger-observatory`
**PR base:** main

## Outcome

ops-toolkit's `tools/ledger-observatory/` is marked retired (moved to dwarves-kit), NOT deleted (repo-retire convention, preserves `git log --follow`). `MANIFEST.md`'s row updates to point at the new home. Any ops-toolkit doc that named `tools/ledger-observatory` as canonical (README/CLAUDE.md/skills index) gets a one-line pointer update.

## Quality bar

Same shape as 03R: `tool.toml` `status = "moved"` (not `"abandoned"` , the tool is alive, just relocated; distinguish from 03R's Go runner which is genuinely dead code) with a `moved_to` field naming the dwarves-kit path. `README.md` gets a one-line banner at the top: "Moved to dwarves-kit `tools/ledger-observatory/` (2026-07-05, PR #<05K's>). This copy is retained for `git log --follow` only; do not edit." Do NOT delete `src/`/`tests/`/`docs/` , they stay as the historical snapshot. `MANIFEST.md` row: same tool name, `status: moved`, note pointing at the kit path.

## How to close the loop

- Read 05K's merged PR (dwarves-kit) for the exact final path and PR number.
- Edit `tools/ledger-observatory/tool.toml`: `status = "moved"`, add `moved_to = "dwarves-kit/tools/ledger-observatory"`.
- Edit `tools/ledger-observatory/README.md`: prepend the one-line banner above the existing content (existing content stays, historical).
- Edit `MANIFEST.md`'s ledger-observatory row: `status` column -> `moved`, note column -> pointer to the kit path.
- `rg -l "tools/ledger-observatory"` across ops-toolkit docs (excluding the retired tool's own tree and this mega's scaffold) , any hit naming it as a LIVE/canonical location gets a one-line pointer fix to the kit path. A hit that's clearly historical (a completed mega's RUN_REPORT, a dated research doc) is left alone (history is not rewritten).
- NC: `uv run ledger` from the OLD ops-toolkit path either fails cleanly or the README banner is the first thing a reader sees , assert the banner text is present and prepended (not buried).

**Done =** tool.toml + README banner + MANIFEST row updated, grep sweep clean (no stale live-pointer), NC green.

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. HANDOFF: next = whatever's still open per ROADMAP (06/07/08/09 or convergence gate).
3. DECISIONS: nothing new expected here (05K owns the substantive calls); note only if the grep sweep found a surprise reference.
4. Report IN the records, EXIT.

## Scope edges

**In:** tool.toml/README/MANIFEST retire-pointer edits, the doc grep sweep, the NC.
**Out:** anything code-level (05K owns all of that), deleting any file.
**Not:** a second copy of the mega-durations query, re-litigating the move itself.

## Where to look

`tools/mega-runner`'s 03R retire pattern (tool.toml/MANIFEST/README shape, same convention), `MANIFEST.md`, 05K's merged PR for the exact new path.

## PR body

- Outcome: ops-toolkit's `ledger-observatory` copy marked `moved` (retire convention), pointing at its new dwarves-kit home.
- Verification: retire-marker NC + doc grep sweep (no stale live pointer).
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`; dwarves-kit 05K PR.

## Notes
