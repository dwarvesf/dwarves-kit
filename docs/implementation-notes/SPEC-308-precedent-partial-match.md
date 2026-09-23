# Implementation notes: SPEC-308 precedent partial match

Delta from the spec only. The variant table and the decisions it settles are in the spec's Design record.

## 2026-09-23 Build

Decision: the eval ran through a local loop rather than the jev-eval harness. Why: `harness/kit_decisions.py` imports `inventory.py` from the fixed path `~/.claude/dwarves-kit`, so it cannot point at a worktree. The loop reuses the harness's own `kit_data` helpers (`split_row`, `ok_row`, `scrub`, the restricted registry) and the same flat ranking as `lexical_rank`. It reproduced origin/master's published numbers exactly (26/45, 30/45, 12/18, 12/14), which validates it as the same measurement.

Decision: the operator brief asked for "simple stemming or prefix matching". Both were built and measured; neither made the cut (spec, Design record rows 2 to 6). The closed inflection set from SPEC-245 stays. Impact: `records` still does not find `record` from a plural query. No labeled query needed it.

Deviation: the task type classifier returned `learning` for this task. The run records `type=spec-feature ctype=learning`: it is a code change with a behavioral test, not a learning track.

Open: P31 "mini reachability job liveness probe" (5 terms, floor 4) still returns nothing. The gold row `tools/vps-mon/bin/host-job` matches 2 of the 5 words. A lower floor would recover it and flood the negatives (spec, row 2).

Open: the gold file cannot name rows the old index never held. Counting `kit lib/session/observe/bin/session-observe` for P04 and P06 and `kit lib/session/recall/bin/session-recall` for P02 lifts hit@1 to 32/45 and hit@3 to 36/45. The gold file lives in ops-toolkit; relabeling it is the experiment owner's call.
