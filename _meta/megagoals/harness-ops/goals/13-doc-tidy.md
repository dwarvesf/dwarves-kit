# Sub-goal 13: doc-tidy

**Merge policy:** auto
**Time budget:** 1-2 hours
**Proof:** the moved files at their new homes + `docs/README.md` map matches the real tree + nothing load-bearing broke. Rung 1-2 (mostly safe doc-moves; a check that no reader referenced a moved path).
**Design:** obvious
**Depends on:** none (Track B; but land after 09/11 so the README map reflects the final tree)
Model: sonnet
**Branch:** fix/harness-ops-13-doc-tidy
**PR base:** main

## Outcome

The remaining safe doc-tidy lands: a `docs/audits/` home for one-off reports (the 90KB `skillspector-report-2026-06-25.md` moves there), the `kit.toml.example` placement decision is settled (either it stays at repo-root as the shipped-default source per 04, or moves to `docs/config/` if 04 makes a live `kit.toml` the source), and `docs/README.md`'s subfolder map is refreshed to match the real tree (it currently omits proof/runs/releases and won't reflect 09/11). Verified-safe moves only , the 2026-07-06 audit found most "cheap wins" were actually load-bearing (research/architecture.md is a generated /kit:spec target, the proof/verification fold is 09's integrity job), so this sub-goal is deliberately narrow.

## How to close the loop

- Move `docs/verification/skillspector-report-2026-06-25.md` → `docs/audits/` (no code reads it; verify with grep).
- Settle `kit.toml.example`: if 04 promoted a repo-root `kit.toml` as the default, the `.example` is redundant → remove or keep as `docs/config/` reference; update the 2 references in the config brief.
- Refresh `docs/README.md`'s subfolder map to the final tree (add audits/, reflect 09's proof-fold + 11's runs→generated, add briefs/ from 10).
- Verify: grep proves no reader references a moved path; the README map matches `ls docs/`. Capture the check.

**Done =** the one-off report is in `docs/audits/`, `kit.toml.example` placement is resolved, and `docs/README.md` map matches the real `docs/` tree (captured check, no dangling reference).

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `bash lib/classify/lane-classify.sh classify "..."` → tiny/normal).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; this may be the LAST sub-goal , note the mega is at TIER-4 close; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** the skillspector one-off, kit.toml.example, `docs/README.md` map.
**Out:** the proof/verification fold (09), briefs move (10), runs move (11) , this only refreshes the README to reflect them.
**Not:** the risky/load-bearing moves (those are 09/12), renaming generated targets (research/architecture.md stays), deleting anything (relocate, never rm).

## PR body

Final safe doc-tidy: `docs/audits/` for one-off reports, settles `kit.toml.example` placement, refreshes `docs/README.md`'s map to the real tree. Deliberately narrow , the audit found most "cheap wins" were load-bearing (handled in 09/12). Verify: no-dangling-reference check + README-matches-tree. Part of `harness-ops` (Track B), see ROADMAP.md.

## Notes
