# Sub-goal 03R: retire-runner

**Merge policy:** auto
**Time budget:** 20-40 min
**Proof:** run-table: `tool.toml` shows `status = "abandoned"`, MANIFEST.md row updated, README carries the pointer; `git log --follow tools/mega-runner/` still resolves (not deleted). Done-ladder rung 1 (a reversible metadata/doc change).
**Design:** obvious (metadata + doc; no code)
**Depends on:** none (independent; do first so nothing points at a live-but-superseded tool)
Model: sonnet
**Branch:** `chore/retire-mega-runner` (ops-toolkit)
**PR base:** main

## Outcome

`tools/mega-runner` (the merged Go runner, #705) is RETIRED per the repo's retire convention, because its role moved to `dwarves-kit` `orchestrate.sh queue` (03K). It is NOT deleted (preserves `git log --follow` + the tests as reference): `tool.toml` gets `status = "abandoned"`, `MANIFEST.md` reflects it, and the README's first line points readers at the kit queue layer.

## How to close the loop

- `tools/mega-runner/tool.toml`: set `status = "abandoned"` (per ops-toolkit "Retire a tool" rule; do NOT `git rm`).
- `MANIFEST.md`: update the mega-runner row (status abandoned + the pointer).
- `tools/mega-runner/README.md`: prepend a one-line banner: "ABANDONED 2026-07-05 -> superseded by dwarves-kit `orchestrate.sh queue` (runner-fastpath 03K); kept for git history + test reference."
- Do NOT touch the Go code or tests (they stay as reference).

**Done =** `tool.toml` status=abandoned + MANIFEST row + README banner, all committed; `git log --follow tools/mega-runner/` still resolves.

Kit-adopted repo: record gate-ledger phases before push (tiny/docs lane).

## Handoff on completion

1. Flip the ROADMAP box + PR #.
2. HANDOFF: nothing depends on 03R; note it done.
3. DECISIONS: none needed (the spine-change entry already covers the why).
4. Report IN the records, EXIT.

## Scope edges

**In:** `tools/mega-runner/{tool.toml,README.md}` + `MANIFEST.md`.
**Out:** the Go code/tests (kept), the kit queue layer (03K), the board tool (04).
**Not:** deleting the tool, editing its Go.

## PR body

- Outcome: retire `tools/mega-runner` (status=abandoned) after its role moved to the kit `orchestrate.sh queue`.
- Verification: tool.toml/MANIFEST/README run-table.
- Link: ops-toolkit `_meta/megagoals/runner-fastpath/ROADMAP.md`.

## Notes
