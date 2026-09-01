# Sub-goal 04: cheap-tier defaults (three surfaces, one stance)

**Merge policy:** auto
**Time budget:** 1-2 hours.
**Proof:** run-table: execute.md worker-dispatch text carries the mid-tier default + the optional spec `Model:` header escape hatch · NEGATIVE CONTROL: an explicit spec `Model:` overrides the default in a fixture dispatch · meta-agent.md Mode B now writes sonnet-on-abstain (grep) · dotfiles half: subgoal-template defaults `Model: sonnet` with OMIT documented as deliberate inherit (diff captured) · test-meta agent-frontmatter lint still green.
**Depends on:** none.
Model: sonnet
Effort: medium
**Branch:** feat/kit-face-04-tiers
**PR base:** master

## Outcome

The cheap-first stance is CONSISTENT across all three tier surfaces: (1) `commands/execute.md` workers dispatch mid-tier (sonnet) by default, with an optional bare `Model:` header on the SPEC as the hard-reasoning escape hatch (verifiers keep their frontmatter tiers); (2) the plan-for-mega-goal subgoal-template defaults `Model: sonnet` (dotfiles half); (3) `agents/meta-agent.md` Mode B writes sonnet-on-abstain instead of omitting , reversing its recorded "human's call" stance deliberately and in the same change, so drafts do not drift from the template.

## Quality bar

One stance, three surfaces, zero contradictions left on record (grep proves it). The `sonnet|haiku|opus` lint stays untouched; one spec sentence acknowledges fable-tier sessions inherit via the SPEC-078 wording. DOTFILES DISCIPLINE: edit the chezmoi source, `chezmoi apply`, then stage+commit in ONE shell call (the S-64 watcher reverts uncommitted tracked changes).

## How to close the loop

`/spec` + `/spec-validate` first. Then the fixture dispatch override NC + greps (`rg "sonnet-on-abstain\|Model: sonnet"` across the three surfaces) + `bash tests/test-meta.sh`. Assumptions: ROADMAP 04 block.

**Done =** all three surfaces agree (greps green), override NC passes, dotfiles half applied + committed atomically, test-meta green.

## Scope edges

**In:** execute.md worker template, meta-agent.md Mode B wording, dotfiles subgoal-template + one spec sentence on fable.
**Out:** the frontmatter lint regex; per-agent tier changes (all already sonnet/haiku); route-suggest internals.
**Not:** a fourth tier surface; auto-detecting "hard reasoning" (the header is explicit by design); touching review-team's SPEC-078 block.

## Where to look

commands/execute.md:145-213 (worker dispatch 2b), agents/meta-agent.md:85-88 (the stance to reverse), commands/review-team.md:24-29 (SPEC-078 pattern), dotfiles source `dot_claude/skills/plan-for-mega-goal/references/subgoal-template.md`, WORKFLOW.md:193+ (cheap-first routing prose).

## PR body

Cheap-tier defaults unified: execute workers default sonnet (spec `Model:` header = escape hatch, NC-proven), meta-agent Mode B writes sonnet-on-abstain, template defaults `Model: sonnet` (dotfiles half, applied atomically). Verify: fixture override NC + surface greps + `bash tests/test-meta.sh`. Roadmap: ops-toolkit `_meta/megagoals/kit-face/ROADMAP.md`.

## Notes

<empty>
