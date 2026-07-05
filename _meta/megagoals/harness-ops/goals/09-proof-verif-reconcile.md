# Sub-goal 09: proof-verif-reconcile

**Merge policy:** gate
**Time budget:** 2-3 hours
**Proof:** a per-slug decision table (which version is canonical for each of the 8 divergent slugs) + the folded result + proof-ledger still recognizes them. Rung 2. GATE: the per-slug canonical pick is a content-integrity judgment a human eyeballs before merge.
**Design:** obvious
**Depends on:** none (standalone; Track B)
Model: sonnet
**Branch:** fix/harness-ops-09-proof-reconcile
**PR base:** main

## Outcome

The split-brain between `docs/proof/` and `docs/verification/` is resolved WITHOUT losing content. 8 slugs exist in BOTH dirs with DIVERGENT content (kit-foldin-{hooks,session-tools}, kitmod-{docs,install-wire,mega-status,operate-contract,reconcile,subsystem-commands}). For each, pick the canonical version (verification/ is the home; take the fuller/more-recent content per slug, or merge the two if both carry unique detail), fold into `docs/verification/`, then retire `docs/proof/`. The proof-ledger recognizer already accepts `docs/verification/*` so folding keeps them recognized; leave the `docs/proof/*` recognizer pattern (it's tested) or clean it in the same PR.

## How to close the loop

- For each of the 8 divergent slugs: diff `docs/proof/<slug>.md` vs `docs/verification/<slug>.md`; decide canonical (record the pick + why in the PR). Do NOT blind-overwrite (that was the aborted 2026-07-06 attempt).
- Fold the chosen content into `docs/verification/`; retire `docs/proof/` (the 5 non-divergent proof/ files move cleanly).
- Verify: `bash tests/test-delivery-ratio.sh` + the proof-ledger tests still pass; no proof lost.
- GATE: present the per-slug decision table for Han's eyeball before merge.

**Done =** all 13 docs/proof/ files are folded into docs/verification/ with the divergent 8 reconciled per an explicit per-slug decision (no content lost), proof tests green, and Han has approved the canonical picks.

**Kit-adopted repo? Record the gates** (dwarves-kit cwd, `lane-classify` → normal).

## Handoff on completion

Flip ROADMAP `[x]` + PR #; HANDOFF.md → next Track-B; append DECISIONS.md; report; EXIT.

## Scope edges

**In:** the 13 `docs/proof/` files, their `docs/verification/` counterparts, the proof-ledger recognizer.
**Out:** the other ~140 verification files, the proof format.
**Not:** flattening the verification/<slug>/ dirs (fights the proof-of-done.md filename convention), a general docs move.

## PR body

Resolves the docs/proof/ vs docs/verification/ split-brain: folds the 13 proof files into verification/, reconciling the 8 divergent slugs per an explicit per-slug canonical pick (no content lost). GATE: canonical picks approved by Han. Verify: proof tests green. Part of `harness-ops` (Track B), see ROADMAP.md.

## Notes
