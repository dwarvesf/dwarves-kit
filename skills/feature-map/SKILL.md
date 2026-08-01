---
name: feature-map
description: Maintainer-only (dwarves-kit repo dev only). Use to audit THIS KIT's OWN feature estate against its path map, "run the feature-map loop", "is the workflow path map still complete", "does every feature appear in workflow-paths", "feature inventory drift", or after a batch of merges that added/removed commands, agents, skills, or hooks. Cross-checks the generated docs/FEATURES.md registry against the docs/workflow-paths.md path index both directions, then re-places only the DELTA features on the topology diagrams. An audit-loop instance (docs/patterns/audit-loop.md), sibling to /kit:features. REFUSES to run while FEATURES.md is stale (regenerate first). NOT for a consumer/adopter repo (this schema is dwarves-kit-specific; it has nothing to check against there), NOT for auditing a target project you point the kit at (that is /kit:features), NOT for regenerating the registry itself (that is lib/registry/feature-registry.sh, pinned by test-meta), NOT for whole-doc prose drift (that is doc-drift), NOT for one known-missing feature (just add its line).
disable-model-invocation: false
---

# Feature map

Maintainer-only, dwarves-kit repo development only: this skill audits the KIT'S OWN
`docs/FEATURES.md`/`docs/workflow-paths.md` pair, which only exists in this repo. It
is not something a consumer/adopter repo would ever have a reason to invoke. To
inventory the features of a project the kit is POINTED AT (a migration source, a
codebase you want documented), use `/kit:features` instead -- see
`docs/patterns/audit-loop.md` for how the two relate.

## Overview

Audit the live feature estate (every command, agent, skill, hook) against the workflow path map and ship fixes as a PR. This is the feature-inventory instance of `docs/patterns/audit-loop.md`: the generated registry `docs/FEATURES.md` (SPEC-219) is the machine truth; `docs/workflow-paths.md` section 5 is the hand-derived path index that drifts when features land or leave. Tier 1 is pure shell; Tier 2 spends model time only on the delta.

## The four slots (per the audit-loop pattern)

| Slot | This instance |
|---|---|
| Item set | every row of `docs/FEATURES.md` plus every line of `docs/workflow-paths.md` section 5 (both sides enumerate; the diff is the queue) |
| Contract | (a) FEATURES.md is fresh (regenerating changes nothing); (b) every registry row has exactly one path-index line and vice versa, all four kinds; (c) trigger classes agree between the two (secondary, listed not auto-fixed) |
| Evidence class | Tier 1: the repo itself via the generator diff + sed/comm name extraction. Tier 2: a model re-reads only the delta features' definitions to place them on the topology |
| Apply mechanics | FIX on an isolated branch; new features get a path-index line AND a placement on the section 2/3 diagrams; removed features get their line deleted; PR body lists every verdict; UNSURE never auto-resolved |

## Process

1. **Freshness gate, REFUSE if stale.** Regenerate to a temp file and compare:

   ```
   bash lib/registry/feature-registry.sh generate /tmp/feat-check.md
   cmp -s /tmp/feat-check.md docs/FEATURES.md || echo STALE
   ```

   STALE means the committed registry itself lags the tree (test-meta is already RED). STOP and tell the operator: run `bash lib/registry/feature-registry.sh generate`, commit, then re-run this skill. Auditing the path map against a stale registry produces false verdicts.

2. **Branch first.** All edits ride an isolated branch, per the pattern.

3. **Tier 1, mechanical cross-check, zero model cost.** Extract names from both files and diff both directions per kind (BSD sed: keep `/` as the delimiter; `|` cannot be both delimiter and literal):

   ```
   W=docs/workflow-paths.md; F=docs/FEATURES.md
   sed -n '/^## Commands/,/^## Agents/p' $F | sed -nE 's/^\| `\/kit:([a-z0-9-]+)`.*/\1/p' | sort > f-cmd
   sed -n '/^### Commands/,/^### Agents/p' $W | sed -nE 's/^\| `\[[^]]+\] \/kit:([a-z0-9-]+).*/\1/p' | sort > w-cmd
   sed -n '/^## Agents/,/^## Skills/p' $F | sed -nE 's/^\| `([a-z0-9-]+)`.*/\1/p' | sort > f-agt
   sed -n '/^### Agents/,/^### Skills/p' $W | sed -nE 's/^\| `\[D\] ([a-z0-9-]+).*/\1/p' | sort > w-agt
   sed -n '/^## Skills/,/^## Hooks/p' $F | sed -nE 's/^\| `([a-z0-9-]+)`.*/\1/p' | sort > f-skl
   sed -n '/^### Skills/,/^### Hooks/p' $W | sed -nE 's/^\| `\[[HI]\] ([a-z0-9-]+).*/\1/p' | sort > w-skl
   sed -n '/^## Hooks/,$p' $F | sed -nE 's/^\| `([a-z0-9._-]+)\.sh`.*/\1/p' | sort > f-hks
   sed -n '/^### Hooks/,/^## 6/p' $W | sed -nE 's/^\| `\[E\] [^>]*-> *([a-z0-9._-]+).*/\1/p' | sort -u > w-hks
   for k in cmd agt skl hks; do comm -3 f-$k w-$k; done
   ```

   Empty `comm -3` output for all four kinds = presence parity holds. Any name in column 1 (only in FEATURES) is a NEW/unmapped feature; column 2 (only in the path index) is a REMOVED/ghost feature. Each is a finding with the name as evidence. Secondary pass, same evidence class: compare trigger classes for matched names; a disagreement (e.g. `skill-review` frontmatter-derived `[I]` vs the index's hand-judged `[H]`) is a listed UNSURE for the operator, never auto-flipped, because either side may be the wrong one.

4. **Tier 2, delta only, model-read.** ONLY when step 3 produced deltas: dispatch ONE `kit:audit-scanner` (the shared read-only scanner, preferred: it physically cannot write; fall back to a general-purpose subagent only where the kit agent roster is unavailable, e.g. a frozen plugin snapshot) with the delta list. Its scope, exactly: read each delta feature's definition file and return, per delta, the section 5 path-index line to add/remove (matching the existing line grammar: `entry -> ... -> terminal`, trigger mark from the registry) and the feature's real attach point on the section 2 flow-topology and section 3 system-topology diagrams, with the definition evidence quoted. It must invent no edge the feature's definition does not show (regeneration rule 5 of workflow-paths.md). Apply its returned placements HERE, on the branch (the scanner proposes, this skill applies). Zero deltas = zero dispatch; report CLEAN and stop.

5. **Verdict each finding** with the audit-loop grammar: OK / FIX / REMOVE / UNSURE / DANGER. A ghost line whose feature file is gone is REMOVE with the deletion commit as evidence. A trigger-class disagreement is UNSURE.

6. **Verify.** Re-run steps 1 and 3: freshness green, `comm -3` empty all four kinds. Run `bash tests/test-meta.sh`: green, or the run is not done.

7. **Ship.** Commit, push, open a PR whose body lists every verdict with evidence and every UNSURE for the operator. Nothing to change: no branch, report CLEAN with the four counts.

## Cadence

Run after any merge batch that touched `commands/`, `agents/`, `skills/`, or `hooks/` (the test-meta freshness pin going RED is the loudest trigger), or on a schedule per the audit-loop driver ladder.

## Red flags

- Auditing against a stale FEATURES.md: the step 1 refusal exists for exactly this.
- Dispatching Tier 2 with an empty delta: pure spend, the cheap-first split exists to prevent it.
- Auto-flipping a trigger-class disagreement: either side may be wrong; it is the operator's call.
- Rewriting whole topology diagrams for one delta feature: place the delta, leave the rest.
