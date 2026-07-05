# Mega-goal: token-optim-v3

> **STATUS: COMPLETE (2026-07-01).** All 7 sub-goals merged. SG-01 #598, SG-03 #599 (merged earlier);
> end-review wave merged bottom-up 2026-07-01: SG-05 dwarves-kit #91, SG-06 #92, SG-02 #90, SG-04
> dotfiles #167, SG-07 ops-toolkit #608, plus the mega-goal gate-contract fix dotfiles #171. Post-merge
> review (2 rounds, adversarial) applied + verified before merge. Archived under `_archive/`.

> Canonical design reference: `research/2026-06-29-token-coherence-design.md` (the principle +
> architecture). Sibling wave: `_meta/megagoals/token-optim-v2/` (orchestrator + levers + proof).
> REFRAME: the objective is COHERENCE over a long run; lower token is the SIDE EFFECT. A lever
> that cuts tokens but hurts coherence (turns-to-green / rework up) is DROPPED, not kept. This
> ROADMAP is the execution plan; the design doc is the why.

**Destination:** A long-running AND interactive Claude Code session stays coherent at lower token
cost via deterministic (no-LLM) context compaction with lossless recall, plus a meta-agent that
drafts agents/sub-goals and (once v2's measurement exists) auto-routes model/effort from real data.
v2 made the orchestrated loop cheap and proved it; v3 makes context engineering deterministic +
adaptive and extends it to daily interactive use.
**Quality bar:** Deterministic: same transcript in, same compaction out. Nothing load-bearing is
ever silently dropped, because recall can always retrieve it. A fresh session never re-discovers
what a past session already decided.
**Stacking tool:** gh (stacked PRs within a repo; cross-repo deps base on the repo's default)
**Merge mode:** open-only (review-at-end, Han 2026-07-01) , the loop opens one PR per sub-goal and
merges NOTHING; it does not halt at each gate but continues to the next runnable sub-goal. Han
reviews + merges the whole set in one end-review session.
**Merge autonomy:** none (the loop never merges; every remaining sub-goal is human-ship)
**Started:** 2026-06-29

## What we adopt (and from where)
- **pi-vcc** (`monotykamary/pi-vcc`): deterministic no-LLM compaction + lossless recall -> SG-01/02/03/04.
- **claude-code-hooks-mastery meta-agent** (`disler/...`): the agent that drafts agents -> SG-05
  (drafter now), SG-06 (data-driven, after v2 SG-09).
- **pi-messenger-swarm overlay**: cross-agent presence view -> PARKED (see NOTES; overlaps v2
  SG-01/10 + vps-mon).
- **rtk** (`rtk-ai/rtk`): deterministic no-LLM INPUT-side filter , compacts dev-command output BEFORE
  it enters context (the front-half pi-vcc/v3 lack; they compact the transcript AFTER). Integrated as
  a global Claude Code hook, SEPARATE from the sub-goals: harness-layer, benefits every session incl.
  `/kit:execute` workers, so the kit needs no rtk code. Ship: ops-toolkit SPEC-124 (config in
  dotfiles/chezmoi + a secret-guard B5 hardening to close the `rtk read` bypass). A standing lever, not
  a sub-goal. Trial gate skipped by Han (finalize-now); measured `rtk gain` ~82% on the eval.

## Non-deployable terminus (intentional)
Tooling + kit + dotfiles + experiments + docs. "Done" = build + merged-or-held; no deploy/UAT gate.
The vps-mon-adjacent observability is parked, so no daemon redeploy is in scope. Missing deploy/UAT
is intentional, not forgotten.

## Sub-goals
- [x] SG-01 vcc-extract-poc: no-LLM extractor compacts a real CC transcript with measured reduction + fidelity (ops-toolkit experiments/) , `auto` , PR #598
- [ ] SG-02 deterministic-handoff: extractor generates v2 SG-02's two-tier handoff deterministically, A/B on cold resume (dwarves-kit) , `gate` , PR #90 (OPEN, held for Han; det generator + orchestrator wiring + 56/56 tests captured; AC8 live turns-to-green A/B deferred to gate) , depends SG-01 (cross-repo)
- [ ] SG-03 cc-recall: lossless turn-grouped recall CLI over ~/.claude/projects JSONL (ops-toolkit tools/) , `auto` , PR #599 , depends SG-01
- [x] SG-04 interactive-dcompact: deterministic compaction as a parallel interactive command + a written graduation plan to replace native /compact (dotfiles/kit) , `gate` , PR #167 (OPEN, held for Han; additive `/dcompact` slash command, native /compact untouched; run-table 99.8% + recall fidelity captured; live-session screenshots deferred to Han's daily-driver gate) , depends SG-01 (cross-repo)
- [x] SG-05 meta-agent-drafter: gated meta-agent + skill verb drafts a subagent/sub-goal file from a description (dwarves-kit) , `gate` , PR #91 (OPEN, held for Han; agents/meta-agent.md + /kit:draft-agent + test-meta-agent.sh 38/38 + 2 golden fixtures; kit guards 508/508; base master)
- [x] SG-06 data-driven-routing: router suggests model/effort from v2 SG-09's measured data (dwarves-kit) , `gate` , PR #92 (OPEN, held for Han; stacked on #91; lib/route-suggest.sh reads SG-09 12-col ledger, suggests cheapest-PASS model, abstains on thin data + excludes failing arms; test-routing 10/10; effort abstained = not in schema) , v2 SG-09 dep CLEARED
- [x] SG-07 proof-ablation: ablation measures deterministic-compaction fidelity vs a pre-registered threshold (ops-toolkit) , `gate` , PR #608 (OPEN, held for Han; v3 arms deterministic-handoff + recall-backed-compaction wired into SG-09 harness + verdict LADDER + pre-registered threshold; pipeline validated 9/9 zero-spend; live Opus run gated on Han) , depends v2 SG-09 + SG-12 + SG-01..04 ALL SATISFIED

> SG-08 (reconcile-mega-systems) was MOVED OUT to its own mega-goal `kit-hardening`
> (`_meta/megagoals/kit-hardening/`, 2026-06-29): it grew past a sub-goal into the kit-side
> counterpart (ADR-0028 + SPEC-088 + 3 sub-goals). v3 stays pure context-engineering.

## Dependencies
- SG-02, SG-03, SG-04 each reuse SG-01's extractor/parser. SG-03 is same-repo (ops-toolkit) so it
  stacks on SG-01's branch if unmerged; SG-02 (dwarves-kit) + SG-04 (dotfiles) are cross-repo, so
  they base on their repo default and PORT the technique (no git-stack across repos).
- SG-06 needs v2 SG-09's measured token+turns data (does not exist until SG-09 runs). BLOCKED until
  then; a data dependency, not caution.
- SG-07 needs v2 SG-09 (threshold methodology) + SG-12 (the fixture, done #595) + SG-01..04 (the
  levers it measures).

## Cross-wave note
This wave is independent of token-optim-v2's open sub-goals EXCEPT SG-06 + SG-07 (need SG-09) and
SG-02 (strengthens SG-02, already done PR #83). The two waves run concurrently.

## Assumptions (from the 2026-06-29 design session)
- **Philosophical reconciliation.** The canonical design says "fresh-window > compaction" and lists
  "self-/clear in the loop" as a non-goal. pi-vcc does NOT violate this: it is lossless-recoverable
  compaction (recall-backed), not destructive /clear. The rule stands: fresh-window stays preferred
  BETWEEN units (the orchestrator); v3's deterministic compaction is for the irreducible WITHIN-unit
  growth and for INTERACTIVE sessions where you cannot just start fresh. v3 complements v2, it does
  not contradict the design doc.
- **Two waves concurrent.** v2 (orchestrator + levers + proof) and v3 (deterministic compaction +
  meta-agent) are independent except the deps named above.
- **Cross-repo worktree reality** (carried from v2 FEEDBACK): native EnterWorktree cannot create a
  worktree in dwarves-kit/dotfiles from an ops-toolkit session; those sub-goals need a manual
  `git worktree add <repo>/.claude/worktrees/<name>` off the repo default.
- **Privacy.** CC transcripts can contain secrets/PII. Every committed seed/fixture transcript MUST
  be scrubbed (repo privacy rule); the recall tool is read-only and local-only.
- **Merge posture** (SUPERSEDED 2026-07-01, see below): originally `auto` for ops-toolkit-owned
  machine-verifiable sub-goals (SG-01, SG-03) and `gate` (per-sub-goal human-ship STOP) for the
  rest. SG-01/SG-03 already merged under that posture.
- **Merge posture v2 , open-only / review-at-end** (Han, 2026-07-01): all REMAINING sub-goals
  (SG-04, SG-05, SG-06, SG-07; SG-02 already open+held #90) run open-only: the loop builds each,
  captures its proof, OPENS its PR, and CONTINUES to the next runnable sub-goal WITHOUT stopping.
  The loop merges NOTHING. Han reviews + merges the whole set in one end-review session. This
  PRESERVES the kit's human-ship rule (the loop never merges a kit PR) while removing the
  per-sub-goal interruption Han didn't want: "I want to review at the end." The skill's
  `auto-bottom-up`/`gated-final` defaults are overridden to `open-only` for this wave.
- **Skill vs kit governance** (kit-orchestration audit, 2026-06-29): the three mega-goal principles
  (stacked + minimal-gate auto-merge, front-loaded questions, deploy+UAT = done) live in the
  `plan-for-mega-goal` SKILL, NOT in dwarves-kit. The kit deliberately human-gates merge, has no
  front-load mechanism, and defines done as verified-tasks (not deploy/UAT); its `/kit:mega`
  (SPEC-034) is VALIDATED-not-shipped. v3 follows the skill but defers to the kit's human-ship on
  kit repos. Reconciling the two systems moved to its own mega-goal `kit-hardening`
(ops-toolkit `_meta/megagoals/kit-hardening`, Han 2026-06-29) with ADR-0028 + SPEC-088 + the
`/kit:think` brief; v3 stays pure context-engineering.

## Audit cheat sheet
    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --json state,reviewDecision,statusCheckRollup
    done

## Before close
Run `/kit:review-team` (+ a focused lens) across the merged set, then append the LAB_LOG arc entry
on the last sub-goal's branch (ops-toolkit SPEC-005), then mark complete.
