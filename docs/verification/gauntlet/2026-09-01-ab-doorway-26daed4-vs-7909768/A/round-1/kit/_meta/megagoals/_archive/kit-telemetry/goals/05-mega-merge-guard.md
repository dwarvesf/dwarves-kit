# Sub-goal 05: mega-merge code-level guard

**Merge policy:** auto
**Time budget:** 1-2 hours.
**Proof:** run-table , the exclusion negative control is the load-bearing row: a gate-tagged sub-goal PR and a held final PR are BOTH refused by `lib/mega-merge.sh` at the code level even when the prompt-level instruction is absent.
**Depends on:** none (independent; slot anywhere).
Model: sonnet
Effort: medium
**Branch:** feat/kit-telem-05-mergeguard
**PR base:** master

## Outcome

The mega-merge PR-routing exclusion (never auto-merge a `gate`-tagged sub-goal PR or the held final PR) is enforced IN CODE in `lib/mega-merge.sh`, not only in `commands/mega.md`'s prompt text , defense-in-depth for the TIER-4 security LOW filed as kit board ID-083. A prompt-rationalizing model can no longer merge past the exclusion.

## Quality bar

The check reads PR STATE (label/base/title marker per the SPEC's pick), not conversation intent. Fail closed: an un-classifiable PR is refused with a reason, never merged on benefit-of-the-doubt. Small diff , this is one guard clause + tests, not a rewrite.

## How to close the loop

SDD: `/spec` + `/spec-validate` first (kit board ID-083 is the brief). Then:

```
cd dwarves-kit && bash tests/test-mega-merge.sh   # NC: gate-tagged refused · held-final refused · unclassifiable refused-with-reason · normal auto PR still merges
```

Proof run-table at `docs/verification/mega-merge-guard.md`. Gate-ledger records per phase.

**Done =** `test-mega-merge.sh` green including all three refusal negative controls AND the normal-PR-still-merges positive control, and kit board ID-083 flipped in this PR.

## Handoff on completion

1. Flip 05's ROADMAP box, PR # + SHA; flip kit board ID-083 -> shipped IN this PR.
2. HOT `HANDOFF.md`: next per roadmap (or the TIER-4 close gate if last).
3. WARM `DECISIONS.md`: which PR-state signal was chosen as the exclusion key and why.
4. Report IN records, EXIT.

## Scope edges

**In:** the guard in `lib/mega-merge.sh`, tests, the proof.
**Out:** the auto-merge flow itself (shipped, SG-08); merge-mode semantics.
**Not:** new merge modes; changing gated-final behavior; GitHub branch-protection config.

## Where to look

`lib/mega-merge.sh` (the comment at ~line 34 marks the hole), `commands/mega.md` (the prompt-level rule to mirror), kit board ID-083, the kit-hardening SG-08 proof for the existing merge-path tests.

## PR body

Code-level gate/final-PR exclusion in `lib/mega-merge.sh` (defense-in-depth over the prompt rule; fail-closed on unclassifiable PRs). Board ID-083, TIER-4 security LOW from the kit-hardening close. Verify: `bash tests/test-mega-merge.sh`. Proof: `docs/verification/mega-merge-guard.md`. Roadmap: ops-toolkit `_meta/megagoals/kit-telemetry/ROADMAP.md`.

## Notes

<empty>
