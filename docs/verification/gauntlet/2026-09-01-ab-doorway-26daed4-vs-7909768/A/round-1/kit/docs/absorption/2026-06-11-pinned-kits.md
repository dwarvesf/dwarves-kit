# Absorption proposal: 2026-06-pinned-kits

Run date: 2026-06-11
Lanes run: B (targeted seed-scan of the two pinned kits) + A (Credits/seed drift on the same sources)
Capability check: gh + git clone available? yes (shallow clones at /tmp, SHAs pinned below)
Board: ID-069. Scan agent independent of this writer; proposal-only per the human merge gate.

Baselines: EveryInc/compound-engineering-plugin @ `4719dc5`; cursor/plugins @ `74dd229`.
Licenses: both MIT; Credits citation suffices.

Correction vs the intake note: the prizes were swapped there , `verify-this` is
cursor's; the parallel-persona JSON merge + apply-class are EveryInc's.

## Candidates (ranked, rubric /16, ADOPT >= 10)

| # | Source | Lane | Interest area | What it is | Rubric /16 | NO-list | 2-phase | Duplicate? | Recommendation | Rationale + absorption sketch |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | EveryInc `ce-code-review` Stage 5 + findings-schema | B | review | Anchored-confidence merge: reviewers return JSON with confidence at 5 behavioral anchors (0/25/50/75/100, each with a self-test); fingerprint dedup (file + line-bucket +-3 + normalized title); cross-reviewer corroboration promotes one anchor step; LATE confidence gate (<75 suppressed, P0 at 50+) so weak findings get a promotion chance first | 15 (4/3/4/4) | pass | review+ship | no (upgrades review-team Step 3) | ADOPT. review-team.md: reviewer prompts gain the JSON contract + anchors; Step 3 dedupe -> fingerprint + promotion + late gate; report gains a Confidence column. Effort M |
| 2 | EveryInc `ce-code-review` action-class rubric | B | review | Apply-class routing: every finding classified by follow-up SHAPE (`gated_auto` with concrete suggested_fix / `manual` needs design / `advisory` report-only) + owner + requires_verification; severity = urgency, class = what to do. NOTE upstream has DEPRECATED `safe_auto` entirely | 15 (4/3/4/4) | pass | review+ship | no | ADOPT. review-team.md report gains a Route column; decision gate routes gated_auto -> responding-to-review, manual -> board row, advisory -> spec ## Review only. Effort S |
| 3 | cursor `verify-this` | B | verification | Falsifiable-claim evidence gate: restate the claim as condition+metric+threshold BEFORE measuring; baseline-vs-treatment artifact pair (same command/data/env); three-valued verdict incl. INCONCLUSIVE. Our verdicts are binary; noisy/baseline-less runs get forced into a fake verdict today | 14 (4/3/4/3) | pass | verify+ship | partial (we own negative controls; absorb the DELTA only) | ADAPT. verify.md Step 5: claim-restatement preamble + INCONCLUSIVE legal verdict; verification README run-record gains optional baseline=/treatment=/delta=/threshold= line for comparative claims; proof-ledger untouched (INCONCLUSIVE is not a pass). Effort S |
| 4 | EveryInc `ce-code-review` Stage 4 | B | review | Model tiering on review dispatch: high-stakes lenses inherit the session model; the rest dispatch mid-tier ("omitting it on Opus sessions silently 3-4x's the cost"); review-team self-describes as 3x tokens, this halves it | 14 (4/2/4/4) | pass | review+ship | no | ADOPT. review-team.md Step 2: security inherits; architecture + test-coverage dispatch `model: sonnet`; one fallback sentence. Effort S |
| 5 | EveryInc `ce-code-review` Stage 5b | B | review | Per-finding validator wave: one independent read-only validator PER surviving finding (batching recreates persona bias); P0/P1 mandatory; validator infra failure never drops a P0/P1 | 13 (4/2/3/4) | pass | review | no | ADOPT (lower priority). review-team.md Step 3b: validate only verdict-driving findings (scaled down: 3 lenses << 9 personas). Effort M |
| 6 | cursor `thermo-nuclear-code-quality-review` (2 rules only) | B | review | Two tripwires worth lifting, not the skill: a PR must not push a file past 1k lines without a stated reason; "weird if statements in random places" = design problem, not a nit | 13 (4/2/4/3) | pass | review | partial (folds into the existing architecture lens) | ADAPT. review-team.md Reviewer 2 prompt: append both rules beside the deep-module vocabulary. Effort S |

## Overflow appendix

(none: 6 gate-passers, all displayed)

## Recommend NOT absorbing

| Artifact | Source | Reason |
|---|---|---|
| ce-dogfood-beta QA-matrix loop | EveryInc | duplicates /kit:execute fix-loop + bounded quality-loop contract |
| ce-demo-reel screenshot/GIF evidence | EveryInc | needs agent-browser + VHS binaries; NO-list; recommend external |
| ce-proof | EveryInc | name collision; a proofeditor.ai integration, not an evidence gate |
| 14-persona catalog wholesale | EveryInc | kit deliberately runs 3 lenses; #1 carries the merge value without the roster |
| review-and-ship | cursor | duplicates /kit:ship + /kit:review-team |
| pr-review-canvas | cursor | static HTML renderer; kit ships no renderer |
| deslop | cursor | 22-line checklist duplicating /simplify + the maintainability lens |
| control-ui / control-cli | cursor | Playwright/CDP + tmux runtimes; recommend external |

## Lane A drift (fixed in this PR)

`docs/ABSORPTION.md` seed line said "apply-class safe/gated/manual"; upstream HEAD
deprecated `safe_auto` (classes now `gated_auto`/`manual`/`advisory`; the apply
decision moved to judgment in Stage 5c). Seed line corrected.

## Gate

Adoption is maintainer-approved (human merge gate). Approved candidates become
board rows -> SPEC -> SDD lanes; nothing in this PR changes behavior.
