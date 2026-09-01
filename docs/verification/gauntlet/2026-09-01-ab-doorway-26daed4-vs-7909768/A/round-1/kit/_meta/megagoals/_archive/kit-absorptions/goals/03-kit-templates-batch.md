# Sub-goal 03: kit-templates-batch (References field + change-risk ordering + meta-agent post-condition)

**Merge policy:** auto
**Time budget:** 45-90 minutes of loop work
**Proof:** run-table: spec-validate fixture pass with AND without the optional `References:` field (both green, no new gate); grep rows for the ordering instruction + the meta-agent Post-condition line.
**Design:** obvious
**Depends on:** none (dwarves-kit stack head)
Model: sonnet
**Branch:** `feat/kit-template-fields`
**PR base:** master (dwarves-kit repo)

## Outcome

The kit's authoring templates absorb the small field-guide items: (1) the spec template gains an OPTIONAL `References:` field (pointer to source code/doc implementing the wanted semantics + one line on what to imitate; source beats description, cross-language ok; `/kit:spec-validate` treats it as optional, NO new gate); (2) the spec/plan template's Design section instruction: order by likelihood-to-tweak (data models, public interfaces, UX flows first; mechanical refactors last); (3) the meta-agent's draft shape gains the `Post-condition:` line (ID-253 kit half).

Covers: ID-249 kit halves + ID-253 kit half.

## Quality bar

Template prose only; spec-validate behavior changes ONLY by tolerating the new optional field (the with/without fixture pair proves no gate was added).

## How to close the loop

- Fixture spec WITH `References:` -> spec-validate green; WITHOUT -> still green (captured both).
- `rg -n 'References:|likelihood|Post-condition' <templates>` rows.
- Kit-adopted: run the lane, record gates via gate-ledger before push.

**Done =** both spec-validate fixture runs green + all three grep rows present.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 04-grill-conditioning (check the cross-mega hold first: harness-observatory 01 merged?). 3. `DECISIONS.md`: none expected. 4. EXIT.

## Scope edges

**In:** dwarves-kit spec/plan templates, meta-agent draft template, spec-validate tolerance.
**Out:** grill (04), emits (05), mega.md (09).
**Not:** any required field; any new gate.

## Where to look

`research/2026-07-04-fable-unknowns-absorption.md` Design 3; dwarves-kit `commands/spec.md` + `commands/spec-validate.md` + meta-agent template; cockpit rows ID-249/253.

## PR body

Optional References spec field + change-risk plan ordering + meta-agent Post-condition line. No gate changes (with/without fixture pair). Part of mega-goal kit-absorptions. Covers kit halves of ID-249/253.

## Notes

