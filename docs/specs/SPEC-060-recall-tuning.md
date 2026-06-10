# SPEC-060: Classifier recall tuning from a live-session truth table

Status: SHIPPED
Date: 2026-06-10
Lane: normal
Type: spec-feature / behavioral

## Problem

SPEC-057's truth table tested INVENTED phrases ("plan next week priorities"). A live probe of
8 REAL asks from one working arc (2026-06-10) found 7/8 falling to the `spec-feature` default:

| Real ask | Was | Should be |
|---|---|---|
| evaluate mattpocock skills + absorb into kit | eval | spec-feature (eval imposes the wrong metrics+seeds dialect on absorb work) |
| merge the 6-PR stack sequentially | spec-feature | operate |
| untangle stranded branches/PRs | spec-feature | reconcile |
| wrap up session + LAB_LOG entry | spec-feature | operate |
| scaffold mega-goal roadmap + goal loop | spec-feature | planning |
| review workflow setup + explain | spec-feature | (chat; correct to leave) |
| add handoff/zoom-out skills | spec-feature | spec-feature (correct) |
| update learning-day skill | spec-feature | spec-feature (correct) |

Two failure modes: spec-feature over-absorbs as fallback (harmless but loses the type loop),
and the eval misfire imposes a WRONG proof dialect (harmful). No new type is needed; the 11
cover the semantics. Real session phrasing is the better truth table.

## Decision

`lib/task-type-classify.sh`, four narrow extensions (SPEC-057 review lesson: anchors, not
broad words):

1. **planning** gains `mega-?goal | scaffold .{0,25}roadmap | (draft|write) (the )?roadmap`.
2. **operate** gains `merge (the )?.{0,25}(stack|merge train|pr queue) | wrap.?up .{0,25}session |
   wrap.?up,? (and )?(commit|push|merge) | session (close|wrap) | lab.?log entry`.
3. **4b absorb guard** (new, above eval): `absor(b|ption)` co-occurring with
   `\bkit\b|\bskill|\bcommand\b|operator estate` -> spec-feature. Absorb-into-kit work is
   implementation with pins; the evaluation prologue is /kit:absorb's job (proposal-only) and
   PHILOSOPHY's "Skill routing" rule. Co-occurrence required so "absorb the loss into the q2
   budget" falls through untouched.
4. **reconcile** gains `untangle .{0,30}(branch|pr|backlog|estate|stack) |
   stranded .{0,25}(branch|pr|spec) | orphan(ed)? .{0,20}(branch|pr|worktree)`.

`goal loop` was considered for planning and dropped: "run the goal loop on the parser feature"
is execution, not planning; `mega-goal`/roadmap anchors carry the real case.

## Acceptance criteria

- AC1: all 8 real asks classify per the Should-be column (chat row classifies spec-feature,
  acceptable: the classifier only runs on task intake).
- AC2: 6 adjacent negative phrasings do NOT flip (functions-merge, code-untangle,
  feature-scaffold, response-wrap, budget-absorb, model-eval).
- AC3: the SPEC-057 11-type table + its 12 negative pins unchanged.
- AC4: precedence documented in the script header.

## Test plan

14 new pins in `tests/test-hooks.sh` (8 positive real-session rows incl. the bonus
"wrap up, commit, merge" phrasing; 6 negative). Negative control: comment the 4b absorb
guard -> the absorb pin goes RED (falls to eval) -> restore.

## Verification

- `tests/test-hooks.sh`: 237/237 (223 prior + 14 new).
- `tests/test-meta.sh`: 416/416 (regression).
- 12-probe live run recorded in the PR body; negative control run below.

## Review

(filled after the adversarial pass)
