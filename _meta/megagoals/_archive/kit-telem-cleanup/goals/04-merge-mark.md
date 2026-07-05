# Sub-goal 04: auto-mark gate/gated-final PRs at creation

**Merge policy:** auto
**Time budget:** 2-3 hours.
**Proof:** run-table , a gate/gated-final PR opened via the mega flow is created as a DRAFT + `do-not-merge` label, and `lib/mega-merge.sh`'s `_merge_exclusion` then REFUSES it (the two halves meet: the mark is guaranteed present, the guard catches it). Negative control: a normal `auto` PR is opened un-marked and the guard clears it.
**Depends on:** none (independent; complements SG-05/SPEC-100 from the prior wave).
Model: sonnet
Effort: high
**Branch:** feat/kit-clean-04-mergemark
**PR base:** master

## Outcome

The SPEC-100 merge-guard loop is closed. That guard (prior wave) refuses to auto-merge a held PR that CARRIES a mark (draft / hold-label / title marker), but it cannot synthesize a mark , an UN-marked gate/gated-final PR slips through (security review B1, ID-089). Fix the complementary half: `commands/mega.md`'s PR-open step ALWAYS opens a `gate`-tagged sub-goal PR or the held final PR as a **draft** AND with the **`do-not-merge`** label. Now the state the guard keys off is guaranteed present, so a prompt-rationalizing model cannot merge a held PR even by skipping the routing , and GitHub itself refuses to merge a draft (a second, intrinsic layer).

## Quality bar

The mark goes on at the ONE place PRs are opened (`commands/mega.md`), not scattered. Draft is the primary signal (GitHub-intrinsic, blocks merge natively); the `do-not-merge` label is the belt-and-suspenders the code guard also reads. Ensure the label exists (create it idempotently) so `gh pr create --label` does not fail. Do NOT weaken or change the SPEC-100 guard itself , this is the mark half only.

## How to close the loop

Kit-adopted repo: read `AGENTS.md` first; classify + record gates before push.

```
cd dwarves-kit
grep -n 'do-not-merge\|--draft' commands/mega.md    # AFTER: the PR-open step marks held PRs
# proof: the mark + guard meet. Inject a fake PR-state (as tests/test-mega-merge.sh does)
bash tests/test-mega-merge.sh                        # extend: a marked held PR is refused end-to-end
```

Proof run-table at `docs/verification/merge-mark.md`. Pin: (1) `commands/mega.md` opens a gate/gated-final PR with `--draft --label do-not-merge`; (2) fed that PR-state, `_merge_exclusion` returns refuse; (3) a normal `auto` PR is un-marked + cleared (negative control).

**Done =** `commands/mega.md` opens every gate/gated-final PR as draft + `do-not-merge`, a test proves the resulting PR-state is refused by the SPEC-100 guard end-to-end (and a normal PR is not), and the gates are recorded.

## Handoff on completion

1. Flip 04's ROADMAP box, PR # + SHA. On merge, this closes the ID-083/ID-089 guard pair , note it.
2. HOT `HANDOFF.md`: next = 05 (edit-vs-mention) if unmerged, else the TIER-4 close gate.
3. WARM `DECISIONS.md`: draft vs label precedence + where the label is ensured-to-exist.
4. Report IN records, EXIT.

## Scope edges

**In:** the PR-open marking in `commands/mega.md` (draft + label), label-ensure, the end-to-end test.
**Out:** the `_merge_exclusion` guard itself (shipped, SPEC-100); merge-mode semantics.
**Not:** GitHub branch-protection config; a new PR-labeling framework; changing gated-final behavior.

## Where to look

`commands/mega.md` (the PR-open / gated-final step), `lib/mega-merge.sh` (`_merge_exclusion`, `_pr_info` , the guard the mark feeds), `tests/test-mega-merge.sh` (extend), dwarves-kit board ID-089, `docs/specs/SPEC-100-mega-merge-guard.md` (threat model / B1 , the gap this closes).

## PR body

Auto-mark gate/gated-final PRs as draft + `do-not-merge` at creation in `commands/mega.md`, closing the SPEC-100 guard loop (the guard defends a marked PR; this guarantees the mark). ID-089 (`#kit-telem-followup`), completes the ID-083 security pair. Verify: `bash tests/test-mega-merge.sh`. Proof: `docs/verification/merge-mark.md`. Roadmap: ops-toolkit `_meta/megagoals/kit-telem-cleanup/ROADMAP.md`.

## Notes

<empty>
