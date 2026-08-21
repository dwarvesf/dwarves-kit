# Sub-goal 01: context-policy

**Merge policy:** auto
**Time budget:** 1-2 hours of loop work
**Proof:** run-table (chezmoi apply + grep of the rendered ~/.claude/CLAUDE.md for both block headers + `jq .effortLevel` on the applied settings), committed with the PR
**Depends on:** none
Effort: low
**Branch:** feat/cc-hyg-01-policy (repo: tieubao/dotfiles)
**PR base:** main

## Outcome

Global CLAUDE.md (chezmoi source `home/dot_claude/modify_CLAUDE.md.tmpl`) carries two new short blocks, and the default settings stop paying for effort nobody asked for:

1. **Model + effort tier policy** (closes ID-219): Fable 5 / Opus is the default for interactive deep work (prompt caching works, cache-read is 10x cheaper); GLM / NeuralWatt routes are for stateless glue only, reached via claude-nw, never as a long-session daily driver (0% cache = full price every turn). Default `effortLevel` is `medium`; `xhigh` is a deliberate per-session choice via /model, never the saved default. Apply the settings change too (chezmoi source for settings.json): effortLevel back to `medium`.
2. **Cache-read hygiene block** (closes ID-236, ~20-30 lines): /clear between unrelated tasks; split mega-sessions at natural boundaries using the handoff skill or /dcompact (this line is ID-242's option-b wiring, it makes handoff earn its slot); avoid same-file re-read churn (read slices, remember offsets); avoid non-caching router models for long interactive sessions; keep dispatching fresh-context subagents freely (measured cheap: median dispatch ~1.2x one human turn).

Evidence base: research/2026-06-28-claude-token-cost-attribution.md (cache_read = 58.5% of Opus cost; corrected lever ranking) + research/2026-07-02-process-effectiveness-audit.md R5 (485:1 cache-read ratio, 238M-token re-read session).

## Quality bar

Reads like the rest of global CLAUDE.md: terse contracts, no lecture. A cold agent obeys it without needing the research files.

## How to close the loop

- Edit the chezmoi SOURCE in ~/workspace/<owner>/dotfiles (never the rendered file); `chezmoi apply`; then capture a run-table: `grep` the rendered ~/.claude/CLAUDE.md for the two block headings (exit 0 each) + `jq -r .effortLevel ~/.claude/settings.json` prints `medium`.
- Dotfiles watcher reverts uncommitted tracked changes: stage+commit in ONE shell call; use `cmp`, not `diff` (aliased).
- Kit routing: dotfiles is a cross-repo sub-goal; classify via `bash ~/.claude/dwarves-kit/lib/lane-classify.sh classify "<task>"`, draft the spec, run spec-validate lenses on it, record phases via `lib/gate-ledger.sh` (never /kit:* from the ops-toolkit session). If dotfiles lacks the kit markers, record the lane in the PR body instead.

**Done =** rendered ~/.claude/CLAUDE.md contains both policy blocks AND applied settings effortLevel is `medium`, proven by the committed run-table.

## Handoff on completion

1. Flip this sub-goal's ROADMAP.md box to `[x]` and record its PR #. 2. Overwrite HANDOFF.md with the next sub-goal + exact first action + read-pointers. 3. Append durable invariants to DECISIONS.md. 4. Report in the records, then exit immediately.

## Scope edges

**In:** the two CLAUDE.md blocks, the settings effortLevel default, the connector-prune checklist in the PR body (Booking.com + unused claude.ai connectors, Han clicks, the loop cannot).
**Out:** any skill file edits (07 owns skills), ops-toolkit CLAUDE.md (02 owns it), ccr/claude-nw config (ID-210 is a separate spec).
**Not:** no new hooks, no tier-router changes, no re-litigating the model choice (decided 2026-07-02).

## Where to look

dotfiles `home/dot_claude/` (the CLAUDE.md template + settings source); the two research files named above for the numbers the blocks cite.

## PR body

One-line outcome; the run-table; the manual connector-prune checklist for Han; link back to `_meta/megagoals/cc-hygiene/ROADMAP.md` (ops-toolkit); note it closes ID-219 + ID-236 + ID-242(b).

## Notes

