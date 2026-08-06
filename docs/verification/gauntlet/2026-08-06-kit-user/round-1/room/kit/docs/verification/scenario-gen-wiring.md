# Proof of done: scenario-generation wiring (SPEC-228)

Behavioral claim: all six workflow surfaces carry the `scenario-gen` beat and
reference the shared pattern doc; removing a surface's edit is detectable.

## Recorded runs (gate format)

Command: rg -l "scenario-gen" commands/think.md commands/design.md commands/grill.md commands/spec.md commands/test-plan.md skills/loop-engineering/SKILL.md | wc -l
Exit: 0
Verdict: PASS (6 of 6 surfaces carry the marker)

Command: rg -l "patterns/scenario-generation" commands/ skills/loop-engineering/ | wc -l
Exit: 0
Verdict: PASS (6 files reference the shared pattern doc)

Command: git stash push commands/think.md && rg -l "scenario-gen" commands/think.md
Exit: 1 (no match)
Verdict: PASS as negative control (reverting a surface drops its marker); restored via stash pop, marker count 3 in think.md

Rollback note: prompt-artifact edits only (six marked blocks + two new docs);
revert the commit and every command behaves exactly as before, no state, no
config, no lib code touched.

## Deferred (behavioral acceptance, recorded at first live use)

The next `/kit:think` run produces a brief with a `Survival scenarios` block;
the next spec written from that brief carries the rows into `## Edge Cases`;
the next `/kit:test-plan` on a scenario-less spec writes rows back before
deriving. Each gets appended here when it happens.
