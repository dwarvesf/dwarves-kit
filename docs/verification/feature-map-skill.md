# Proof of done: feature-map-skill (SPEC-218)

## Acceptance criteria

| AC | Claim | Status |
|---|---|---|
| AC-1 | SKILL.md with frontmatter + four-slot table | MET |
| AC-2 | Tier 1 mechanical: freshness refusal + both-directions cross-check | MET (live run below) |
| AC-3 | Tier 2 delta-only subagent, no delta = no dispatch | MET (stated; live run had zero delta, zero dispatch) |
| AC-4 | PR-gated apply | MET (this PR is the gate) |
| AC-5 | README table + header count, audit-loop Known instances | MET |
| AC-6 | BACKLOG: ID-458 shipped row + ID-407 registry-source note | MET |
| AC-7 | real Tier-1 run green + negative control RED | MET (runs 2 and 3) |

## Confirmation runs

| # | Check | Command | Result |
|---|---|---|---|
| 1 | freshness gate exercised for real | `bash lib/registry/feature-registry.sh generate /tmp/feat-check.md; cmp` | STALE on branch start (concurrent #322 drift), regenerated + committed, then clean |
| 2 | Tier-1 cross-check, live estate, green run | the skill's step 3 recipes, all four kinds, both directions | zero mismatches; counts 34 commands, 26 agents, 8 skills, 25 hooks on each side (the 8th skill is feature-map itself, see Run detail) |
| 3 | negative control | remove the `/kit:wayfind` line from a COPY of workflow-paths.md, re-extract, `comm -23` | `wayfind` surfaces as only-in-FEATURES (RED), real file untouched |
| 4 | registration pins | `bash tests/test-meta.sh` | green; README skills header/table pins pick up the 8th skill (output in Run detail) |

## Run detail

Run 2 is the green run required by AC-7: presence parity holds across the whole live estate, so Tier 2 dispatched nothing (the delta-only rule exercised on the zero case). One secondary finding, listed not fixed, per the skill's UNSURE rule: `skill-review` trigger class is `[I]` by frontmatter (`disable-model-invocation: false`) but `[H]` in the hand-derived path index; operator call.

Run 3 is the injected-defect control: deleting one index line makes exactly that feature name surface in the only-in-FEATURES column. The mutation was made on `/tmp/w-mutated.md`, never on the tracked file.

Run 1 is incidental but load-bearing: the staleness refusal fired on genuine drift (concurrent merge #322) before this skill's first commit, proving the refusal path against reality rather than a fixture.

Review round exercised the loop a second time: the initial ship candidate registered feature-map in FEATURES.md but NOT in the path index, so the skill's own Tier 1 (re-run by the reviewer) flagged feature-map itself as the one delta (7 vs 8 skills). Fixed by adding its three workflow-paths.md lines (section 2 estate cadence, section 3 learn-side skills, section 5 index) exactly as the skill's Tier 2 prescribes for a new feature; the run table above records the post-fix state.

## Reproduce

```
bash lib/registry/feature-registry.sh generate /tmp/f.md && cmp /tmp/f.md docs/FEATURES.md
# then the step 3 recipe block in skills/feature-map/SKILL.md
grep -v '/kit:wayfind' docs/workflow-paths.md > /tmp/w-mutated.md   # NC input
bash tests/test-meta.sh
```
