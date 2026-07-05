# Sub-goal 02: dotfiles-contracts-batch (five one-liner contracts, each with its own check)

**Merge policy:** auto
**Time budget:** 1-1.5 hours of loop work
**Proof:** run-table with ONE ROW PER ITEM (five rows: grep or fixture-capture each) + `chezmoi apply` clean. This is the principled tiny-batch (per the tiny-work decompose rule itself): five sub-30-minute items, same repo, each keeping its own Done line below.
**Design:** obvious
**Depends on:** 01
Model: sonnet
**Branch:** `feat/contracts-batch`
**PR base:** `feat/operate-portability`

## Outcome

Five contract one-liners land in the dotfiles-managed skill/hook layer:

1. **Handoff-lint (ID-252):** checklist section in the portable `references/OPERATE.md` (+ handoff skill if present): every existence-claim verified THIS session; every PR/commit/file ref resolves; next-actions runnable as written. PreCompact (cc-harvest) reminder line if that hook is dotfiles-managed.
2. **Post-condition field (ID-253, dotfiles half):** `Post-condition:` (how the caller verifies my output) added to the skill-authoring template(s).
3. **Session-age nudge (ID-254):** the existing UserPromptSubmit session-time hook prints one nudge line when elapsed > ~6h OR compactions >= 2. No new hook, no state.
4. **Worker unknowns policy (ID-249 third):** conservative-option + log-under-Deviations + keep-going bullet in the portable OPERATE.md.
5. **Tiny-decompose rule (ID-257, skill half):** plan-for-mega-goal decompose guidance gains: tiny items NEVER become their own sub-goal; batch into ONE sweep sub-goal (each item keeping its own check line) or run as `/kit:assign` lane tiny outside the mega.

## Quality bar

Each item is one insertion in the right file, zero behavior beyond the hook line. If any item turns out NOT to be a one-liner, log it to NOTES ## Proposed additions and skip it rather than growing this batch.

## How to close the loop

- Per-item check (the five run-table rows): `rg -n` for items 1/2/4/5 in the APPLIED copies; a fixture past-threshold hook fire captured for item 3.
- `chezmoi apply` clean + checksums.
- dotfiles NOT kit-adopted: proof in the PR body.

**Done =** all five per-item checks green in one run-table, chezmoi-clean.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 08-remega-consolidate (same stack). 3. `DECISIONS.md`: any item skipped + why. 4. EXIT.

## Scope edges

**In:** dotfiles skill references, skill-authoring templates, the session-time hook script.
**Out:** kit-side halves (03/07); OPERATE portability structure (01, already merged below this).
**Not:** a lint SCRIPT; measuring fidelity post-hoc; new hooks or state files.

## Where to look

`research/2026-07-04-scaling-the-harness-audit.md` §4.2-4.4; `research/2026-07-04-fable-unknowns-absorption.md` Design 3; cockpit rows ID-252/253/254/249/257.

## PR body

Five one-liner contracts (handoff-lint, post-condition field, session nudge, unknowns policy, tiny-decompose rule), one run-table row each. Stacked on operate-portability; review after it. Covers ID-252, ID-254, halves of ID-249/253/257.

## Notes

