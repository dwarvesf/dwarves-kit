# Impl notes: SPEC-203 WORKFLOW.md registration (proposal, not applied)

Delta from SPEC-203. The spec built `/kit:test-write` + `agents/test-writer.md` + test-plan Step 0 but never registered them in `docs/WORKFLOW.md`'s flow census. This note is the proposed fix, for review; nothing in `docs/WORKFLOW.md` has been edited.

## 2026-07-30 classify test-plan-review-team as a side-flow, not a 4th engine

- Decision: do NOT add `test-plan-review-team`'s bounded revise loop to `### The three bounded loops (engines)`. Register it (and `/kit:test-write`) as new rows in `### Opt-in side-flows`, bumping the count 8 -> 10.
- Why: the operative engine/side-flow distinction in the doc is not "bounded loop with a model-evaluated stop" (which the revise loop does satisfy, WORKFLOW.md:1083-1086); it is the enforcer column. All three engines block: the Goal loop's anti-rationalization Stop hook, the Debug loop's guess-fix guard, the Execute pipeline's hard stop (one of the four hard stops, WORKFLOW.md:1250). `test-plan-review-team` is the opposite by its own contract: "Report-only, never blocks /kit:execute" (`commands/test-plan-review-team.md:5`) and "The loop tightens the artifact; it does not gate" (`:53`). The side-flow table header says exactly what it is: "Advisory, never blocking" (WORKFLOW.md:1199).
- Precedent, twice over: the mid-flight amend micro-loop is a bounded in-session loop and the doc explicitly labels it "not a fourth engine" (WORKFLOW.md:1176-1177); and row 4 (`/kit:ui-design`) already carries a bounded revise loop ("max-2 revise") inside a side-flow's Stop column. A bounded loop inside an advisory flow is an established shape here, not a category error.
- Alternatives: (a) promote to a 4th engine -- rejected, it would put a never-blocking flow in the section whose members are defined by their enforcers, and would force renaming the heading plus the "3 bounded loops" census at WORKFLOW.md:1034 for a misclassification; (c) fold everything into row 5's Stop cell -- rejected, `/kit:test-plan` and `/kit:test-plan-review-team` are independently runnable commands with different triggers, writes-to targets, and stop conditions (the same reason `/kit:devs-team` and `/kit:spec` have separate rows), and `/kit:test-write` would still be unregistered.

## Proposed diff (3 hunks, all in docs/WORKFLOW.md)

### Hunk 1: at-a-glance census (line 1034)

Before:

```
table, above), **3** bounded loops (the engines, below), **8** opt-in side-flows,
```

After:

```
table, above), **3** bounded loops (the engines, below), **10** opt-in side-flows,
```

### Hunk 2: heading (line 1197)

Before:

```
### Opt-in side-flows (8)
```

After:

```
### Opt-in side-flows (10)
```

### Hunk 3: table rows (lines 1209-1212)

Insert two rows after row 5 and renumber the old rows 6-8 to 8-10. Row 5 itself is untouched: "matrix written" IS `/kit:test-plan`'s real stop; the critique loop belongs to the next command, which now has its own row.

Before:

```
| 5 | `/kit:test-plan` | before `/execute`; derive a coverage matrix | `## Test plan` in the spec (consumed by `/execute`) | matrix written |
| 6 | `/kit:review-team` | PR-grade review; 3 lenses (security/architecture/test-coverage) in parallel; confidence anchors + fingerprint dedup + per-finding validators (SPEC-081/082) | `## Review` in the active spec (else inline) | SHIP / FIX THEN SHIP / DO NOT SHIP, unsuppressed findings drive it |
| 7 | `/kit:absorb` | maintainer-only external-absorption audit | dated report under `docs/absorption/` | proposal-only report (human merge gate) |
| 8 | `/kit:kit-health` | maintainer self-assessment vs PHILOSOPHY, before tagging | report (stdout) | assessment rendered |
```

After:

```
| 5 | `/kit:test-plan` | before `/execute`; derive a coverage matrix | `## Test plan` in the spec (consumed by `/execute`) | matrix written |
| 6 | `/kit:test-plan-review-team` | after `/test-plan`; 6 test-design lenses + bounded revise loop (max 3 rounds; findings must strictly fall or halt honestly) | `## Test plan critique` in the spec (replace-not-stack) | SOLID / REVISE / RECONSIDER verdict recorded; loop exits early at 0 findings |
| 7 | `/kit:test-write` | after a SOLID `## Test plan critique`; materialize the matrix into test code via `kit:test-writer` (refuses missing/stale/non-SOLID verdicts) | real test files in the repo's own convention | every row covered or reported skipped; written tests execute (assertions passing is `fix-agent`'s job) |
| 8 | `/kit:review-team` | PR-grade review; 3 lenses (security/architecture/test-coverage) in parallel; confidence anchors + fingerprint dedup + per-finding validators (SPEC-081/082) | `## Review` in the active spec (else inline) | SHIP / FIX THEN SHIP / DO NOT SHIP, unsuppressed findings drive it |
| 9 | `/kit:absorb` | maintainer-only external-absorption audit | dated report under `docs/absorption/` | proposal-only report (human merge gate) |
| 10 | `/kit:kit-health` | maintainer self-assessment vs PHILOSOPHY, before tagging | report (stdout) | assessment rendered |
```

## Companion drift (not in this diff, flag only)

- `docs/workflow-map.md` is the standalone rendering of the same census and repeats the "8 side-flows" count (lines 12, 23, 33, 253) and the row 5 stop cell (line 264). Whoever applies the diff above should sweep it in the same commit, per the doc's own "standalone one-page rendering" pointer at WORKFLOW.md:1031.
- No test pins the side-flow count (grepped `tests/` for `side-flow` / `Opt-in side`: zero hits), so this is a docs-only change with no count-assertion bump needed.
