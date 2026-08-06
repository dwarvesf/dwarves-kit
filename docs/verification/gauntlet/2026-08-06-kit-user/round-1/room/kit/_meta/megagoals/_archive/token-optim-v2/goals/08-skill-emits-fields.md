# SG-08: teach plan-for-mega-goal to emit model/effort + handoff fields

Merge policy: gate
Time budget: ~1 session
Depends on: SG-02 (handoff contract) + SG-03 (model/effort fields)
Model: sonnet
Effort: medium

## Directional outcome
Close the loop so future mega-goals are orchestrator-ready by construction: the composer skill
emits the fields the orchestrator consumes, instead of them being hand-written.

## Done =
`plan-for-mega-goal`'s sub-goal + roadmap templates emit `Model:` / `Effort:` per sub-goal and
the handoff-completion contract (each sub-goal: on done, flip its ROADMAP box + write the hot
HANDOFF). A sample composed goal file shows the fields. The fields match what SG-02/SG-03
defined. PR opened.

## Close the loop (verification)
```
grep -E 'Model:|Effort:|HANDOFF' <skill>/references/subgoal-template.md   # fields emitted
# compose a throwaway mega-goal (or inspect the template) -> goal files carry the fields
```

## Scope edges
The `plan-for-mega-goal` skill files only. Resolve the skill's repo at execution (dotfiles if
chezmoi-managed, else the skill's source). Don't change the orchestrator (that is SG-02/03).

## Where to look
`~/.claude/skills/plan-for-mega-goal/references/{subgoal-template.md,roadmap-template.md}`; the
field shapes are fixed by SG-02 (handoff) + SG-03 (model/effort) , read their merged PRs first.

## Proof expectation
A diff of the template + a sample emitted goal file carrying the fields. Full reviewable proof.

## PR body
feat(skill): plan-for-mega-goal emits model/effort + the handoff-completion contract, so
composed mega-goals are orchestrator-ready. Gated for review.

## Borrowed from pi-swarm (2026-06-29)
Emit the borrowed wording into the templates: "EXIT IMMEDIATELY after done", "Concrete accomplishment with evidence", "progress every 3-5 tool calls or at milestones", and pair each hard rule with an explicit `Anti-pattern:` line (pi-swarm SKILL.md style: mechanics up top, philosophy + named anti-patterns at the bottom). See `research/2026-06-29-pi-swarm-comparison.md`.
