# Sub-goal 01: stale-adr-inversion (docs suppress by-design findings, never observed drift)

**Merge policy:** auto
**Time budget:** 1 hour of loop work
**Proof:** diff showing the lens line in each touched surface + one fixture dispatch capture where a seeded code-vs-ADR contradiction is REPORTED as a drift finding while a seeded by-design behavior (matching its ADR) is NOT flagged.
**Design:** obvious
**Depends on:** none (stack head).
Model: sonnet
**Branch:** `feat/stale-adr-inversion`
**PR base:** `master`

## Outcome

Part of ID-264: the shadcn/improve inversion lands in the kit's generic review surfaces. Two-sided rule, both sides stated wherever reviewers are told to read intent docs: (a) a behavior consistent with a spec/ADR/intent doc is BY DESIGN, not a finding; (b) code that has DRIFTED from what a spec/ADR claims is itself a finding (report the drift with the doc line + the code line); a doc can never blanket-mute observed behavior. Each surface edit is its own check row:

1. `agents/advisor.md` (the generic critique lens) gains the two-sided rule.
2. `commands/review.md` reviewer guidance gains it.
3. `commands/review-team.md` dispatch-prompt template gains it (dispatched lenses do not inherit the parent's rules; inject verbatim, the improve lesson).

## Quality bar

Surgical: one rule, stated once per surface, phrased identically (copy-paste, no paraphrase drift). No new agent, no new gate, no severity machinery. If a surface already implies half the rule, complete it rather than duplicating.

## How to close the loop

- Check row per surface: `grep` the rule's key phrase in all three files.
- Fixture capture: tiny fixture repo (or dwarves-kit itself) with one seeded ADR-vs-code contradiction and one seeded by-design match; a review dispatch reports the former as drift, stays silent on the latter.
- Kit-adopted repo: run the lane, record gates before push.

**Done =** the identical rule text present in all 3 surfaces + the two-sided fixture capture committed (drift flagged, by-design not).

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is 02-review-findings-memory (same worktree lineage, stacked). 3. `DECISIONS.md`: the final rule wording verbatim, PLUS the naming convention: stale-ADR-drift findings carry a `stale-adr:` finding-key prefix so 02's pre-flag grep and 04's adapter can see the new lens type distinctly (advisor P6). 4. EXIT.

## Scope edges

**In:** `agents/advisor.md`, `commands/review.md`, `commands/review-team.md`.
**Out:** specialized domain reviewers (security/api/frontend/infra/performance agents), they inherit via review-team's dispatch template; rejected-findings memory (02).
**Not:** a doc-staleness scanner; changing what reviewers MUST do (advisory lens wording only); any gate-requirement change.

## Where to look

`research/2026-07-04-pxpipe-plannotator-improve-absorption.md` §3 (A4); shadcn/improve's playbook wording ("a stale ADR is itself a finding... don't use the doc to suppress it") as the reference phrasing.

## PR body

Stale-ADR inversion in the generic review surfaces: intent docs suppress by-design findings, observed code-vs-doc drift is itself a finding, docs never blanket-mute. Verbatim injection into review-team dispatch prompts (dispatched lenses don't inherit). Covers ID-264 (kit half).

## Notes
