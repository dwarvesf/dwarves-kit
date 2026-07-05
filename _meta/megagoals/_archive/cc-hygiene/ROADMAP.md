# Mega-goal: cc-hygiene

**Destination:** The measured Claude Code waste from the 2026-06/07 audits is gone and every backlog row in the "CC token/cache/proof hygiene" cluster (ID-209, 219, 234-243, 148, 152) is closed or explicitly parked: context + effort policy and cache-read hygiene live in global CLAUDE.md, the write-only diary tax and bookkeeping-PR habit are retired, the Stop-hook and per-tool taxes are fixed, the proof-gate override leak is closed, planning inventory tells the truth, and the first proof-retrofit batch lands.
**Quality bar:** Every fix traces to a measured number from the three audits, never a vibe. Rules land as one-line contracts where the agent already reads; this mega-goal deletes more process than it adds.
**Stacking tool:** gh (stacked PRs; all sub-goals base `main` in their own repo, no literal stacking needed unless files overlap)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-02

## Sub-goals

- [x] 01-context-policy (dotfiles), Done = rendered global CLAUDE.md carries the model/effort-tier block + the cache-read hygiene block AND settings default effortLevel is medium, `auto`, PR #191 (dotfiles, merged 31fa5f6)
- [x] 02-process-rules (ops-toolkit), Done = CLAUDE.md carries the one-line LAB_LOG default, the bookkeeping-rides-feature-PR rule, and the spec-only-when-gated rule, `auto`, PR #627 (merged c90df739)
- [x] 03-process-plumbing (dotfiles), Done = impl-notes hook fires only for spec work; wrap-session drafts one-liners; plan-for-mega-goal template retires FEEDBACK.md + gains the no-pre-scaffold habit line, `auto`, PR #192 dotfiles (merged f9a284f) + PR #629 ops-toolkit wrap-session (merged a09d1bd5) [split: wrap-session is ops-toolkit-local]
- [x] 04-kit-stop-tax (dwarves-kit), Done = slop-cleaner has resolution memory, session-state-save frequency decided, proof-gate override rejects unproofed source changes; kit tests green, `auto`, PR #116 (dwarves-kit, merged df2315e; review REVISE->3 bypasses fixed, CI green both OS, 449/449)
- [x] 05-tool-tax (ops-toolkit), Done = cc-harvest runs at most once/hour with skip-log + quota claim verified; notion-query-data-sources verdict codified as a rule or fix, `auto`, PR #631 (ops-toolkit, merged d692fd77; cc-harvest throttle pre-existing+verified smoke 21/21, notion rule added)
- [x] 06-planning-sweep (ops-toolkit), Done = shipped specs flipped by script, residue + 8 stale roadmaps + 4 empty folders each have a proposed decision awaiting Han, nothing deleted, `gate`, PR #634 (ops-toolkit, GATE, merged 62b638b0; 2 verified flips, 144 residue + 12 scaffolds proposed for Han)
- [x] 07-skill-prune-trim (dotfiles), Done = prune proposal table (0-fire skills) + top-5 skills split thin-trigger/GUIDE + reasoning-echo audit, disable/delete decisions left to Han, `gate`, PR #193 (dotfiles, GATE, merged 53edbee; 4/5 split lossless, knowledge-capture cross-repo, 46 prune proposals, reasoning-echo clean)
- [x] 08-proof-retrofit-batch1 (ops-toolkit), Done = 5 near-miss tools each have a co-located proof-of-done + ONE runnable check, all green, `auto`, PR #638 (merged 6b581450; 4/5 covered rtk+mac-backup+notion-sync+tg-cleanup, vn-invoice honest dead-stub skip)
- [x] 09-final-review-close (ops-toolkit), Done = review-team + advisor (critique AND over-suggest) ran across the merged set, CRITICAL/MAJOR fixed, cluster board rows closed, LAB_LOG arc entry riding this branch, `gate`, PR #640 (ops-toolkit, merged on Han's approval)

## Dependencies (only if non-trivial)

- 03 depends on 02 (its wrap-session/hook wording mirrors the rules 02 lands; cross-repo, so logical only, both base `main`)
- 09 depends on 01-08 (fan-in; base `main` after they merge or are held)
- 02 and 06 both touch `_meta/BACKLOG.md`; run sequentially, not in parallel

## Assumptions (decisions baked at scaffold time, 2026-07-02)

- Model/effort policy per Han: Fable 5 / Opus default for deep work; GLM/NeuralWatt routes only for stateless glue via claude-nw; default effortLevel `medium`; `xhigh` is a deliberate per-session choice (Han confirmed today's xhigh was deliberate for the planning session only).
- ID-234 + ID-235 sign-off given by Han in-session 2026-07-02 ("proceed"), so 02/03 are `auto`.
- ID-242 resolved as option (b): keep the handoff skill and wire it into the hygiene block as the session-split tool (with /dcompact).
- ID-237 lands as batch 1 only (5 near-miss tools); the remaining ~15 become a successor mega-goal scaffolded ONLY when started (per ID-240's own habit rule).
- ID-209 uses approach (b) thin-trigger + GUIDE.md split (per the row's 2026-06-27 note); any skill disable/delete is proposal-only for Han (never-delete rule).
- ID-148 (umbrella) closes at 09 as satisfied-by the research trilogy (2026-06-25 x2, 2026-06-28, 2026-07-02 x2) + this mega-goal.
- MCP connector prune round 2 (claude.ai UI clicks: Booking.com + unused connectors) cannot be done by the loop; it ships as a checklist in 01's PR body for Han.
- SDD: every sub-goal routes through the dwarves-kit lane with a spec + spec-validate pass before build (Han's directive), recorded via gate-ledger; cross-repo sub-goals drive `lib/` directly, never `/kit:*`.
- Cross-repo worktrees (01/03/07 dotfiles, 04 dwarves-kit): native EnterWorktree cannot cross repos; use the v2/v3 documented exception, `git worktree add <that-repo>/.claude/worktrees/cc-hyg-NN <branch>` run from that repo, removed after merge.

## Audit cheat sheet

Extract PR numbers and audit each:

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read pr; do
      gh pr view "${pr#PR #}" --json state,reviewDecision,statusCheckRollup
    done
