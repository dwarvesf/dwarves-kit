# Sub-goal 08: proof-retrofit-batch1

**Merge policy:** auto
**Time budget:** 4-8 hours of loop work
**Proof:** per-tool run-table (the ONE check green with real stdout + a negative control where cheap), five of them
**Depends on:** none
Effort: medium
**Branch:** test/cc-hyg-08-proof-batch1 (repo: tieubao/ops-toolkit)
**PR base:** main

## Outcome

The five easiest wins from the coverage gap land (advances ID-237, batch 1 of the ~20 first-party tools with neither proof nor tests; 29 of 90 tools have neither):

- **rtk** (near-miss: has docs/verification/ but no canonical proof-of-done.md) and **mac-backup** (near-miss: manual restore-tests.md exists, formalize it) first.
- Plus 3 picked at execution from the neither-list (candidates: notion-sync, tg-cleanup, llm-bench, wisp, vn-invoice, bot-fleet), chosen by: first-party, still used, cheapest honest check. State the pick + reasoning in the spec.

Per tool: a minimal co-located `tools/<name>/docs/proof-of-done.md` in the table-first format (SPEC-016) + ONE runnable check, ponytail-sized (an assert-based selftest or one test file; no frameworks). The done-gate then protects them via the existing `proof-of-done.md` filename match.

## Quality bar

Each check is the smallest thing that fails if the tool breaks, not a test suite. A tool that turns out to be third-party-deploy-only or dead gets a one-line note and is skipped honestly (graceful degradation), never a fake proof.

## How to close the loop

- Same-repo: kit lane from this cwd (spec + spec-validate + gate-ledger). One spec covering the batch; per-tool acceptance criteria.
- Run each tool's new check live; capture command + exit code + stdout slice per tool into its proof-of-done. Negative control where cheap (break an input, watch it fail, restore).
- Graceful degradation: Done holds at >=4 of 5 tools covered, the remainder marked with reason in the PR body; blocked >3 rounds on one tool = note and move on.

**Done =** >=4 of 5 tools have committed proof-of-done + one green check each, proven by the per-tool run-tables.

## Handoff on completion

1. Flip the ROADMAP box + PR #. 2. Overwrite HANDOFF.md (next: 09, the final review round; name the merged-set PR list). 3. Append to DECISIONS.md (the 3 picks + any skips). 4. Exit immediately.

## Scope edges

**In:** 5 tools' proof-of-done + one check each; their tool.toml/gitignore only if the check requires it.
**Out:** the other ~15 tools (successor mega-goal, scaffolded only when started), refactoring any tool's source, third-party deploy bundles.
**Not:** no test frameworks, no CI wiring, no fixing bugs the checks uncover (file them as board rows; a red check on a real bug is a finding, not a blocker to hide).

## Where to look

`tools/{rtk,mac-backup}/docs/` first; `_meta/INVENTORY.md` + research/2026-07-02-process-benchmark.md section 2 for the neither-list; worked examples `tools/{zedra-deploy,spec-to-cli}/docs/proof-of-done.md` (single-feature format).

## PR body

The five run-tables (or four + skip reason); link to ROADMAP.md; advances ID-237 (batch 1; remainder stays queued).

## Notes

