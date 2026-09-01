# Sub-goal 07: UI done-modes + quiescence loop

**Merge policy:** auto
**Time budget:** 3-4 hours.
**Proof:** run-table: a fixture quiescence run CONVERGES (round 2 yields zero NEW >=HIGH and no OPEN >=HIGH -> stops, `[[QL-VERDICT]]` markers + `[resolved in round N | OPEN]` tags in the final critique) · NEGATIVE CONTROL: a never-satisfied critic fixture stops at round cap 3, capped-out findings land in `### Deferred findings` · a re-found unresolved CRITICAL does NOT quiesce (the second NC, the falsely-calm trap) · dotfiles half: template `Done-mode:` field diff captured · plain REVISE still caps at 2 (regression control).
**Depends on:** 06 (quiescence rounds dispatch visual-team WITH the persona lens when the brief carries one).
Model: opus
Effort: high
**Branch:** feat/kit-face-07-donemodes
**PR base:** feat/kit-face-06-persona (stacked on 06)

## Outcome

UI sub-goals declare one of three done-modes, consumed as a `/kit:ui-design` `$ARGUMENTS` flag: **proof** (current default: real-surface flows + 2-3 captures + a11y), **over-test** (proof + `/kit:test-plan` matrix + `/kit:verify` execution + a coverage-delta row , ACs-covered / tests-added before-vs-after , appended to the proof-of-done run-table), **quiescence** (ui-design Phase B EXTENDED: critique -> apply accepted -> re-render -> re-critique; stop when a round yields zero NEW >=HIGH findings AND no OPEN >=HIGH remains, or at round cap 3; the loop lead carries the cross-round dedup ledger in-session; sub-floor + capped-out findings land in a `### Deferred findings` subsection of the spec's `## Visual critique`). Final acceptance stays `gate` in every mode , taste ships past the human eyeball only.

## Quality bar

Quiescence is an EXTENSION of the existing Phase B loop, not a parallel one (visual-team stays single-pass stateless). The stop condition is two-sided by design: "zero NEW" alone falsely quiesces on a re-found unresolved CRITICAL , the NC pins this. Severity floor is >=HIGH (the kit has no MAJOR; one notch stricter than test-plan-review-team's "only LOW remain", stated explicitly). Cap divergence recorded as a DEC: quiescence 3 (test-plan-review-team parity), plain REVISE keeps 2 (fix-agent parity). DOTFILES DISCIPLINE for the template half: source edit -> apply -> stage+commit in ONE call.

## How to close the loop

`/spec` + `/spec-validate` first (spec cites Phase B mechanics + the QL-VERDICT precedent). Then the three fixture runs (converge / cap-out / re-found-CRITICAL) + the plain-REVISE regression + the dotfiles diff. Assumptions: ROADMAP 07 block.

**Done =** all three quiescence fixtures behave (converge, cap at 3 with ledgered deferrals, no false quiescence), plain REVISE unchanged, `Done-mode:` field live in the template, DEC committed.

## Scope edges

**In:** ui-design.md Phase B (quiescence mode + Done-mode arg + Deferred-findings subsection), the cap DEC, the coverage-delta row definition, dotfiles template field, fixtures + tests.
**Out:** visual-team internals (stays stateless; 06 owns its only change); the advisor (its ADR-0028 station is the final boundary, NOT inside this loop).
**Not:** a numeric combined score (ui-design explicitly bans inventing one); unbounded polish loops; auto-accepting critique fixes without the per-round approval Phase B already has.

## Where to look

commands/ui-design.md Phase B (the existing loop: cap 2, user-feedback wrap, re-invoke mechanics), commands/test-plan-review-team.md (QL-VERDICT markers, cap 3, severity-floor precedent), commands/visual-team.md (severity contract), dotfiles source `dot_claude/skills/plan-for-mega-goal/references/subgoal-template.md` (where `Done-mode:` lands, next to `Proof:`).

## PR body

UI done-modes: `proof | over-test | quiescence` as a /kit:ui-design flag. Quiescence extends Phase B , stop = zero NEW >=HIGH AND no OPEN >=HIGH, cap 3 (DEC records the 2-vs-3 divergence), QL-VERDICT audit markers, `### Deferred findings` ledger; over-test defines the coverage-delta proof row. Stacked on #<06's PR>. Fixtures: converge / cap-out / no-false-quiescence. Roadmap: ops-toolkit `_meta/megagoals/kit-face/ROADMAP.md`.

## Notes

<empty>
