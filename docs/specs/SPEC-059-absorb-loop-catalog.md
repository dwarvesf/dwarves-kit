# SPEC-059: Absorb wave: feedback-loop-first debug, deep-module lens, skill-routing rule

Status: SHIPPED
Date: 2026-06-10
Lane: normal (lane-classify)
Type: spec-feature / behavioral (task-type-classify + proof-gate)

## Problem

Three gaps surfaced while evaluating mattpocock/skills for absorption:

1. `/kit:debug` opens with root-cause investigation but never tells the agent to BUILD the
   pass/fail signal first. The strongest idea in mattpocock's `diagnose` skill is that a fast,
   deterministic, agent-runnable feedback loop IS most of the debugging skill; reproduction,
   bisection, hypothesis tests, and the Phase-4 failing test all just consume it. Our loop
   assumed the signal exists.
2. `/kit:review-team`'s architecture lens says "review through the ARCHITECTURE lens" with no
   vocabulary. mattpocock's `improve-codebase-architecture` carries a precise, reusable one
   (deep/shallow modules, the deletion test, seams, leverage/locality, after Ousterhout) that
   makes findings concrete instead of vibes.
3. The kit has no written rule for WHERE an absorbed skill should land. This wave's evaluation
   (7 candidate skills) had to re-derive the boundary by hand: the kit owns loop machinery;
   reflex skills and domain procedures live in the operator's skill estate; the type registry's
   owning-skill column is the bridge. PHILOSOPHY should say this once so every future absorb
   routes mechanically.

## Decision

1. **`commands/debug.md`**: insert `## Phase 0: Build a feedback loop` between the ledger
   section and Phase 1. Condensed catalog of loop-construction tactics (failing test, HTTP
   script, CLI + snapshot diff, headless browser, trace replay, throwaway harness, property/fuzz
   loop, bisection harness, differential loop), the iterate-on-the-loop discipline (faster /
   sharper / more deterministic), the non-deterministic guidance (raise the repro rate until
   debuggable), and the honest exit (cannot build a loop -> stop and ask, never hypothesize
   without one). Existing phase numbering untouched (Phase 1-4 headings are pinned by
   SPEC-013 tests; Phase 0 prepends without renumbering).
2. **`commands/review-team.md`**: the architecture reviewer's prompt gains the deep-module
   vocabulary block: deep vs shallow, the deletion test, seams (one adapter = hypothetical,
   two = real), leverage and locality as the terms findings must be expressed in.
3. **`docs/PHILOSOPHY.md`**: new subsection `### Skill routing: what belongs in the kit` under
   §1, stating the three-tier boundary (reflex / domain procedure / loop machinery) and the
   absorb routing rule. The registry's owning-skill/agent column is named as the bridge.

Considered and rejected this wave (recorded so the evaluation is not re-run):
- `grill-me`: already superseded by `/kit:grill` (SPEC-058 absorbed the richer grill-with-docs).
- `triage`: a GitHub-issue-label state machine; the kit's board (SPEC-055) is already the state
  machine. The `ready-for-agent` vs `ready-for-human` distinction may someday become a board
  annotation; not now.
- `teach`: the operator's learning estate (learning-day-process + learning/ tracks) is deeper;
  two ideas (learning-records, ZPD calibration) route to that skill, outside the kit, per the
  routing rule this very spec adds.
- `handoff`, `zoom-out`: reflex tier; land in the operator's skill estate, not the kit.

## Acceptance criteria

- AC1: debug.md carries `## Phase 0: Build a feedback loop` with the catalog (at least the
  bisection-harness and differential-loop tactics named) and the cannot-build-a-loop stop rule.
- AC2: debug.md's pinned SPEC-013 structure (Phase 1-4 headings, iron law, 3-fix wall,
  `## Root cause` literal) is unchanged.
- AC3: review-team.md's architecture reviewer prompt names the deletion test, deep/shallow,
  seams, leverage, and locality.
- AC4: PHILOSOPHY carries `### Skill routing: what belongs in the kit` with the absorb routing
  rule (loop machinery -> kit; reflex/procedure -> operator estate; registry column = bridge).
- AC5: both sources cited (mattpocock `diagnose`, `improve-codebase-architecture`).

## Test plan

| # | Case | Proof | Expected |
|---|---|---|---|
| 1 | Phase 0 present | `grep -F '## Phase 0: Build a feedback loop' commands/debug.md` | match (pin in test-meta) |
| 2 | Catalog load-bearing tactics | `grep -F 'Differential loop' commands/debug.md` + `grep -F 'bisect run' commands/debug.md` | match |
| 3 | SPEC-013 pins unbroken | `tests/test-meta.sh` SPEC-013 block | all PASS |
| 4 | Arch lens vocabulary | `grep -F 'deletion test' commands/review-team.md` | match (pin) |
| 5 | Routing rule present | `grep -F 'Skill routing: what belongs in the kit' docs/PHILOSOPHY.md` | match (pin) |
| 6 | Negative control | revert the PHILOSOPHY subsection -> run pin 5 -> RED -> restore | RED then GREEN |

## Verification

Recorded post-implementation:

- `tests/test-meta.sh`: all pass, including the three new SPEC-059 pins.
- `tests/test-hooks.sh`: all pass (no hook surface touched; regression guard).
- Negative control: `git stash` of the PHILOSOPHY edit flipped the routing-rule pin RED
  (`FAIL PHILOSOPHY missing skill-routing rule`); restore flipped it GREEN. Run recorded in the
  PR body.

## Source

mattpocock/skills: [`engineering/diagnose`](https://github.com/mattpocock/skills/blob/main/skills/engineering/diagnose/SKILL.md)
(the Phase-1 feedback-loop catalog, iterate-on-the-loop, non-deterministic repro-rate guidance,
cannot-build-a-loop stop rule) and
[`engineering/improve-codebase-architecture`](https://github.com/mattpocock/skills/blob/main/skills/engineering/improve-codebase-architecture/SKILL.md)
(the deep-module glossary, after Ousterhout's "A Philosophy of Software Design"). Evaluation of
the full 7-skill candidate set: this spec's rejected list + the operator-side routing (handoff,
zoom-out, learning-day-process updates) recorded in ops-toolkit's LAB_LOG.

## Review

Date: 2026-06-10. Adversarial pass by a reviewer agent (correctness + internal-consistency
lens) on the full diff vs master. Verdict: **FIX-FIRST 7/10**, 2 MEDIUM + 3 LOW, all fixed
in-branch before commit:

1. MEDIUM, debug.md Phase 4 step 1 read as demanding a FRESH failing test, contradicting a
   Phase-0-built one. Fixed: Phase 4 step 1 now promotes the Phase-0 loop when it already is
   the right failing test.
2. MEDIUM, WORKFLOW.md kept three stale "four-phase" references this change created. Fixed:
   prose, ASCII diagram, and command table now carry Phase 0.
3. LOW, `agents/reviewer.md` architecture lens lacked the vocabulary the review-team dispatch
   prompt promises (two dispatch paths, two vocabularies). Fixed: mirrored into the lens.
4. LOW, the `(§6 N1)` cite pointed at a corollary without saying so. Fixed: cite expanded.
5. LOW, review-team.md citation placement inconsistent with debug.md's Source-line pattern.
   Fixed: Source line extended.

Post-fix: `tests/test-meta.sh` 416/416, `tests/test-hooks.sh` 223/223. Negative control run
live: stashing the PHILOSOPHY edit flipped the routing-rule pin RED; restore flipped it GREEN.
Verdict after fixes: SHIP.
