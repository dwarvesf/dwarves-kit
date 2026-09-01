# Sub-goal 04: interactive-dcompact

**Merge policy:** gate (touches the daily driver; taste + safety)
**Time budget:** ~1 session
**Proof:** 2-3 screenshots/GIF of the command running in a real interactive session (before /
compact / after) + a run-table of token-before vs token-after + a written graduation plan doc.
**Depends on:** SG-01 (the extractor; cross-repo)
**Branch:** `feat/v3-dcompact`
**PR base:** dotfiles `main` (RESOLVED, Han 2026-07-01: ~/.claude commands are chezmoi-managed)
**Mechanism:** an additive `/dcompact` SLASH COMMAND (RESOLVED, Han 2026-07-01: NOT a hook; manual
opt-in; native /compact strictly untouched)

## Outcome
Deterministic compaction is available in daily interactive Claude Code sessions as a PARALLEL
command/hook (e.g. `/dcompact`) alongside the native `/compact`, so Han can A/B it on real sessions
without risking the built-in path. Ships with a written graduation plan: the criteria + steps to
later replace the native `/compact` once trusted.

## Quality bar
Safe to run on the daily driver from day one because it is additive, not a hijack. When it compacts,
the session keeps every load-bearing fact (recall via SG-03 backs it up). The graduation plan makes
"replace native" a deliberate, criteria-gated later step, not a leap.

## How to close the loop
Wire the SG-01 extractor as the `/dcompact` slash command (mechanism resolved). Verify in a real session:
```
# capture session token count, run /dcompact, capture again
# screenshots: before (token count) / running / after (compacted + reduced count)
```
Capture: 2-3 screenshots or a GIF (before / action / after); a run-table (token before/after +
fidelity spot-check); and a `dcompact-graduation-plan.md` (criteria to replace native /compact: e.g.
N sessions A/B'd, zero load-bearing drops, recall covers any gap).

**Done =** `/dcompact` (or the chosen mechanism) deterministically compacts a live interactive
session additively (native /compact untouched), the screenshots + run-table show the before/after
reduction, and a graduation-plan doc states the criteria + steps to later replace native /compact.

## Scope edges
**In:** the parallel interactive command/hook + its wiring + the graduation-plan doc.
**Out:** replacing the native /compact (that is the graduation plan's FUTURE step, not this
sub-goal); the orchestrator handoff (SG-02); recall (SG-03).
**Not:** hijacking or disabling the built-in /compact now; a settings UI; auto-firing the compaction
without Han invoking it (phase 1 is manual/opt-in).

## Where to look
SG-01's extractor. Claude Code slash-command authoring (`~/.claude/commands`, chezmoi-managed in the
dotfiles repo). The native /compact behavior (to stay strictly additive).

## PR body
feat: deterministic interactive compaction as an additive /dcompact command (+ graduation plan to
replace native /compact later). Ports pi-vcc to daily sessions. Verification: before/after
screenshots + token run-table. Gated (daily-driver). token-optim-v3 sub-goal 04.

## Notes
