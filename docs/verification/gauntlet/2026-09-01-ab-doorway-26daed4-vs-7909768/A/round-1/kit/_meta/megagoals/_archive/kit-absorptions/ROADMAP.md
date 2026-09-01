# Mega-goal: kit-absorptions

**Destination:** The kit + planning layer absorbs the field-guide/harness-audit designs: grill fires only where unknowns actually live (and skips with an auditable reason), every kit command's gate activity is visible to the ledger, the pitch/tiny-lane/remega modes exist, and the run contracts are portable (skill-bundled, no private paths).
**Quality bar:** Never-diverge holds (skill <-> /kit:mega mirror synced in the same run). NO gate-REQUIREMENT changes anywhere (observability + conditioning only). Behavior-bearing sub-goals (04, 05, 06) are OVER-TESTED with load-bearing negative controls.
**Terminus:** non-deployable (commands, templates, skill modes): build + merge IS the terminus, closed by the TIER-4 demo run (grill precheck fixtures live, a real `/kit:pitch` on a shipped rid, a read-only remega DRY-RUN report over two real archived mega-goals). Missing deploy/UAT is intentional.
**Stacking tool:** gh (stacked PRs, two per-repo stacks)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-04 (drafted; launch pending Han's go)

## Sub-goals

- [x] 01-operate-portability, portable OPERATE in the skill bundle survives thin+GUIDE, zero private paths, `gate`, PR #195, merged a0bd8e2 (verification-record PR; outcome pre-shipped in dotfiles #194)
- [x] 02-dotfiles-contracts-batch, five one-liner contracts (handoff-lint, post-condition field, session nudge, unknowns policy, tiny-decompose rule) each with its own check, `auto`, PR #196, merged b3d4ff3 (4/5 items; item-3 session-nudge SKIPPED = wrong repo, follow-up ID-269)
- [x] 03-kit-templates-batch, spec-template References field + change-risk ordering + meta-agent post-condition, `auto`, PR #165, merged c57d5c5
- [x] 04-grill-conditioning, 3-signal unknown-density precheck + blindspot pass + `reason=` skip emit, `auto`, PR #166, merged da00ebd
- [x] 05-emit-sweep, 18 dark commands classified emit-owed vs exempt + no-orphan sweep test, `auto`, PR #168, merged c376abb
- [x] 06-pitch-assembler, `/kit:pitch` outward buy-in doc assembled from run artifacts, `auto`, PR #169, merged 119cb19 (AC1 CI-portability fixed: fixture rid render, 29/29 in scrubbed-HOME)
- [x] 07-lane-de-escalation, ship-time "consider tiny" nudge when the diff stayed small, `auto`, PR #170, merged e0fb95d
- [x] 08-remega-consolidate, Consolidate mode in plan-for-mega-goal + read-only dry-run proof, `gate`, PR #197, merged 051d8a3 (all proof PASS incl. read-only NC byte-identical + scoped chezmoi-clean; dry-run over safari-extension-unlock + safari-ext-enhancements)
- [x] 09-mega-mirror-sync, mirror 07/08 knobs into /kit:mega + never-diverge checklist, `auto`, PR #171, merged 8849467

## Dependencies (only if non-trivial)

- Two per-repo stacks: dotfiles 01 -> 02 -> 08; dwarves-kit 03 -> 04 -> 05 -> 06 -> 07 -> 09.
- 05 depends on 04 (`reason=` grammar must exist before the sweep embeds emits).
- 09 depends on 07 + 08 (it mirrors their knobs).
- **Cross-mega (reader-first):** 04 and 05 HOLD until harness-observatory sub-goal 01
  (`kit_gates` reader) has MERGED, verified via `gh pr view`, a blocker fingerprint
  until then. Everything else in this mega is independent of the other run.

## Assumptions (front-loaded answers, baked at draft time; flip before launch)

1. **Runs IN PARALLEL with harness-observatory** (disjoint repos; this is portfolio
   wave v1 practiced). One conductor each; gate PRs batch to Han's review window.
2. **01 and 08 are `gate`:** the team-facing skill bundle and the remega planning
   machinery get Han's eyes; everything else is machine-verifiable.
3. **ID-258 (portfolio v1) is NOT a sub-goal:** its deliverable is the practice +
   the runbook already written (`research/2026-07-04-megagoal-portfolio-scheduling.md`
   §1); there is nothing to build. This run's parallel launch IS its adoption.
4. **Dotfiles workers:** stage+commit in ONE shell call (S-64 watcher), edit chezmoi
   SOURCE then apply, never `~/.claude` directly. dotfiles is NOT kit-adopted: proof
   in the PR body.
5. **08's proof is a read-only dry-run** over two real archived mega-goals (e.g. the
   safari-net family): a consolidation REPORT (dedupe/merge/re-slice decisions),
   zero writes to the archives.
6. **SPEC numbers conductor-reserved up front** in dwarves-kit; dotfiles has no spec
   namespace.
7. **Launch after the `worktree-benchmark-followup` family PR merges** (same as the
   sibling mega).

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read pr; do
      gh pr view "${pr#PR #}" --json state,reviewDecision,statusCheckRollup
    done
