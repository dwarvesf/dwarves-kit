# SPEC-054: Right-sized loops per work type

Status: SHIPPED ([Unreleased])
Lane: normal
Backlog: ID-044
Branch: feat/north-star-02-type-loops
Relates-to: PHILOSOPHY §6 N1 (the criterion this realizes), SPEC-044 (task-type registry), SPEC-050 (lane classifier)

## Problem

The kit routes CODE work superbly: five lanes, a deterministic classifier, a floor guard.
Everything else, research, evals, tool comparisons, test-design passes, cleanup sweeps, doc
work, is classified (`lib/task-type-classify.sh` knows six types) and owes a proof artifact
(`docs/verification/task-types.md`), but has NO defined cycle: no entry, no phases, no exit, no
named executor. In practice non-code work runs as unstructured chat, which is exactly the
"important work gets the full cycle, everything small runs shallow" gap PHILOSOPHY §6 N1 names.

## Solution shape

One source per fact, three small surfaces:

1. **WORKFLOW.md owns the loops** (it already owns the lane paths): a `## Type loops` table,
   sibling of "Size the work first", one row per non-code type: entry -> phases -> exit.
   spec-feature's row points at the lane table (no duplication).
2. **The registry owns the executor**: `docs/verification/task-types.md` gains an `agent`
   column (column 6; `proof-gate.sh` reads columns 3/4/5 by index, so appending is parser-safe).
   Values are `preassigned: <who>` or `dynamic: <selection rule>`.
3. **Intake names the loop**: `/kit:assign` classifies the type early and, for non-spec-feature
   work, writes the type's loop + agent into the goal draft instead of assuming the code cycle;
   `/kit:start` suggests the type loop when the detected work is non-code.

## Acceptance criteria

- AC1: every registry row carries an `agent` entry; `_registry_field` still returns
  artifact/skill/class unchanged (parser regression-proof).
- AC2: WORKFLOW.md `## Type loops` table defines entry -> phases -> exit for the five non-code
  types; spec-feature row defers to the lane table.
- AC3: `/kit:assign` routes by type (non-code drafts name loop + agent); `/kit:start` mentions
  the type loop for non-code work.
- AC4: meta pins guard the registry agent column, the WORKFLOW table, and the assign wiring;
  both suites green.
- AC5: chat-vs-task coexistence stated where the loops are defined (loops engage on task
  execution, not on conversation).

## Test plan

| # | Case | Proof |
|---|---|---|
| 1 | registry parser unchanged | `bash lib/proof-gate.sh contract "benchmark X vs Y"` prints the eval artifact + skill exactly as before the column add |
| 2 | agent column complete | `awk -F'\|' '/^\|/ && $2 !~ /task-type|^[- ]+$/ {n++; if ($6 ~ /preassigned|dynamic|per lane/) ok++} END {exit !(n==ok && n==6)}' docs/verification/task-types.md` exits 0 |
| 3 | WORKFLOW table present | `grep -c '^## Type loops' WORKFLOW.md` == 1 AND >= 5 rows with `->` phases |
| 4 | assign wired | `grep -c 'task-type' commands/assign.md` >= 1 |
| 5 | suites | `bash tests/test-meta.sh` + `bash tests/test-hooks.sh` green; negative control: drop the agent column from one row -> pin RED |

## Rollback

`git revert` the squash commit. Docs + command prose + one appended registry column; no lib
behavior change, no host state.
