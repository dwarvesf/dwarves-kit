# SPEC-056: Per-type test-design dialects, test-first by default

Status: SHIPPED ([Unreleased])
Lane: normal
Backlog: ID-046
Branch: feat/north-star-04-dialects
Relates-to: PHILOSOPHY §6 N3 (the criterion this realizes), test-design-standard (the spine), SPEC-052 (test-plan critique lane), SPEC-054 (the type registry the dialect keys on)

## Problem

Test design was one-size and opt-in: `/kit:test-plan` always wrote a feature-shaped BDD matrix,
whatever the work's type, and the cycle table marked the phase "opt-in", so most work skipped
design-first entirely. An eval's tests are metrics + seeds, a research task's tests are claim
verification, a migration's tests are inventory + rollback rehearsal; forcing them through a
feature checklist produces ceremony, and ceremony gets skipped.

## Solution shape

1. **One spine, six bodies**: `test-design-standard.md` §5b maps each registry type to its
   test-design dialect (spec-feature BDD matrix; eval metrics + hand-verified seeds +
   falsifiability controls; research claim-verification matrix; migration/cleanup inventory +
   rollback rehearsal; data-tool recorded live run + negative control; doc doc-verifier match).
   Dialects specialize the standard; they never fork it (every dialect still owes §1
   traceability, §3 falsifiability, §5 recorded runs).
2. **Type-aware test-plan**: `/kit:test-plan` Step 1b classifies the type and designs in that
   dialect; the spec section stays `## Test plan` (same heading, same AC-traceability).
3. **Default, not opt-in**: the WORKFLOW cycle table flips test-plan to "default for
   normal/full" (tiny exempt). Advisory default: the cycle names it, nothing hard-blocks
   ("Detect, don't dictate"; blocking stays the ship-gate's job).

## Acceptance criteria

- AC1: §5b covers all six types; every dialect line names a falsifiable element.
- AC2: test-plan.md classifies the type before enumerating and routes non-feature types to §5b.
- AC3: the cycle table shows test-plan as default for normal/full; tiny exempt; advisory.
- AC4: the registry cross-references §5b; meta pin guards the three legs; suites green.

## Test plan

| # | Case | Proof |
|---|---|---|
| 1 | dialect table complete | `awk '/^## 5b/,/^## 6/' docs/verification/test-design-standard.md \| grep -cE '^\| (spec-feature\|eval\|research\|migration\|data-tool\|doc) \|'` == 6 |
| 2 | test-plan wired | `grep -c 'task-type-classify' commands/test-plan.md` >= 1 AND `grep -c '5b' commands/test-plan.md` >= 1 |
| 3 | default flip | `grep -c 'Test plan (default' WORKFLOW.md` >= 2 (cycle table + matrix) |
| 4 | suites + negative control | both suites green; delete the §5b research row -> pin RED (recorded during build) |

## Rollback

`git revert`. Docs + command prose only; no lib change, no host state.
