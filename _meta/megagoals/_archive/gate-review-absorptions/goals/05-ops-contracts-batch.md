# Sub-goal 05: ops-contracts-batch (three one-liners, each with its own check)

**Merge policy:** auto
**Time budget:** 1 hour of loop work
**Proof:** diff + a check row per item (grep each landed line; items 1-2 additionally grep the dotfiles portable-copy mirror; for item 1 additionally one worked example of the contract frame rendered).
**Design:** obvious
**Depends on:** none (ops stack head).
Model: sonnet
**Branch:** `docs/ops-review-contracts`
**PR base:** `main`

## Outcome

ID-264 ops half + A5, three independent one-liners, each its own check row (never collapsed):

1. **Gate-deny feedback contract** in `_meta/megagoals/OPERATE.md` (plannotator's tuned deny discipline, generalized): when a human gate DENIES, the feedback handed to the worker follows the triage-first frame: (a) worker verdicts EVERY finding first (Confirmed / Partly / Not-a-bug / Intended, with file:line evidence) before changing anything; (b) never resubmit unchanged; (c) keep branch + title stable so the re-review diffs against the denial. One compact block in the gate section.
2. **The n-rule line** in OPERATE.md's proof/report discipline: "hypotheses ship as numbers with an n or they get cut" (credit pxpipe), one sentence beside the existing grounded-claims rule.
3. **Measurement principles** appended to the §5 principles list in `research/2026-07-04-scaling-the-harness-audit.md`: counterfactual-in-same-row (billed + free counterfactual in ONE record; no cross-run confound; cache credit only when proven warm) and honest-negative (net-loss reported negative, never filtered), with a one-line pointer from `tools/ledger-observatory/docs/benchmark-followup.md` so the tool's design trail sees them.

## Quality bar

Each line lands where the reader already is (OPERATE.md is BINDING for runs; the research §5 is the observatory's design source). No new files, no new sections beyond the one contract block; match surrounding voice; no em dashes. FACT (resolved pre-launch, advisor P5): ID-246 HAS landed (dotfiles #195): the skill bundles a portable OPERATE copy with a never-diverge contract, while ops-toolkit's `_meta/megagoals/OPERATE.md` remains the full local copy. Items 1-2 are generic contract lines, so mirror them into the dotfiles portable copy (`home/dot_claude/skills/plan-for-mega-goal/references/OPERATE.md`) in the SAME run: edit the chezmoi SOURCE, stage+commit in one shell call, scoped `chezmoi apply` on that single target only (never untargeted; the kit-absorptions env-brick lesson).

## How to close the loop

- Check row per item: grep the key phrase in its destination file.
- Item 1: render the contract frame once against a fabricated denial (three findings, mixed verdicts) and include the output in the PR body as the worked example.
- Docs-only in a kit-adopted repo: tiny lane; record the lane classification before push.

**Done =** all three grep checks green + the worked example in the PR body.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 03-plannotator-gate-trial (its deny path renders THIS contract; hand it the block's anchor). 3. `DECISIONS.md`: final contract wording. 4. EXIT.

## Scope edges

**In:** `_meta/megagoals/OPERATE.md`, `research/2026-07-04-scaling-the-harness-audit.md`, one pointer line in `tools/ledger-observatory/docs/benchmark-followup.md`, the never-diverge mirror of items 1-2 into the dotfiles portable OPERATE copy (one tiny dotfiles commit, see Quality bar).
**Out:** the plannotator wrapper that consumes the contract (03); kit-side command text (01/02).
**Not:** restructuring OPERATE.md; new gates; expanding the research doc beyond the principles list.

## Where to look

`research/2026-07-04-pxpipe-plannotator-improve-absorption.md` §2 (A2b) + §4 (A5); plannotator's deny template + triage-first suffix as reference phrasing; OPERATE.md's existing gate + proof sections for placement.

## PR body

Ops contracts batch: gate-deny triage-first contract in OPERATE.md (verdict-per-finding with evidence before any change; never resubmit unchanged; stable branch/title), the numbers-with-an-n rule, counterfactual-same-row + honest-negative principles into the observatory design trail. Each item its own check; worked deny example included. Covers ID-264 (ops half) + A5.

## Notes
