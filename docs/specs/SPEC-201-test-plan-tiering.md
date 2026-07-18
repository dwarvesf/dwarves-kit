# SPEC-201: cost-tier taxonomy for AI-in-the-loop test plans

Status: Draft · 2026-07-18 · Owner: Han
Lane: normal
Relates-to: docs/briefs/DECISION-BRIEF-behavioral-test-tiering.md (verdict: BUILD, v1 scope
SG-1/SG-2), test-design-standard.md §5b (the dialect this augments), SPEC-052
(test-plan-review-team, the lane this adds a lens to), SPEC-056 (per-type dialects, the
precedent this follows)

## Problem

The kit's `/kit:test-plan` enumerates a coverage matrix for every work type, but has no
opinion on COST when the work under test is AI-in-the-loop (an agent, a bot, an LLM
feature): a behavioral case that triggers a real model has a wall-time and flake-tax cost a
mechanical assertion does not. Without guidance, every consumer either re-derives the
tiering by hand (the neko-anon permtest suite did, PR #145, four green-while-broken
incidents before the floor rule settled) or skips it and lets the suite go slow/flaky enough
that it stops running, silently losing the regression net. `/kit:test-plan` should teach the
tiering once so every AI-app plan it produces inherits it, and the test-plan review lane
should catch a plan that mis-tiers a claim.

## Solution shape

1. **A 3-tier taxonomy, additive to the existing dialect.** `mechanical` (no model call:
   config asserts, dependency-baked checks, deterministic parser/engine output),
   `smoke` (a cheap proxy model, grading-rule iteration only, never a ship gate), `behavioral`
   (the real model, asked in natural language, judged against the claim). This is orthogonal
   to the type-keyed dialect in test-design-standard.md §5b (SPEC-056): it augments the
   `spec-feature` BDD matrix (and any other dialect) with a `Tier` column when the spec under
   test is AI-in-the-loop; it does not replace the dialect or the category matrix.
2. **`/kit:test-plan` Step 1c: AI-in-the-loop detection + tiering.** After the existing
   Step 1b dialect pick, a new step judges whether the spec's objective/AC describe
   AI-in-the-loop behavior (agent, bot, LLM, prompt, conversational/NL response, "the model
   does X"). When it does, Step 2's enumeration tags each case with a tier + a one-line
   honesty reason, and Step 3's written `## Test plan` carries the floor rule and the two hard
   don'ts VERBATIM plus a `Tier` / `Smoke-eligible` / `Retry-eligible` column on the matrix.
   The floor rule: "config asserts lie; a behavior claim keeps a real-model probe." The two
   hard don'ts: never delete or downgrade a behavior/security claim below the `behavioral`
   tier to cut cost; never let a `smoke`-tier run gate a ship. Smoke/retry doctrine: a case is
   `smoke-eligible` only to iterate on grading rules (never a gate); a case is
   `retry-eligible` only for a benign-phrasing miss on an explicit allowlist, defaulting to
   NOT eligible, and a security/side-effect verdict is never retry-eligible regardless of
   allowlist.
3. **`/kit:test-plan-review-team` gains a 6th lens: Tiering & floor.** Dispatched alongside
   the existing 5 lenses; when the plan under critique carries no `Tier` column it reports
   N/A (not an AI-in-the-loop plan) and contributes no findings. When the plan does carry a
   `Tier` column, it flags (a) a behavioral-shaped claim (a live-model NL judgment, or a
   security/abuse case) parked at `mechanical` or `smoke`, CRITICAL, and (b) any plan text
   that uses a `smoke`-tier run as the sole or gating proof for a case, CRITICAL.
4. **v1 ships guidance only (SG-3 deferred).** No reference runner (selection, parallelism,
   retry execution). The permtest implementation stays the worked example a consumer points
   at until a second consumer justifies building one, per the brief.

## Non-goals

- No new runner, CLI, or lib script. This is prompt/doc guidance in two command files plus
  one doc annotation, matching the brief's v1 scope exactly.
- No change to the existing type-keyed dialect table in §5b (rows, columns, or type list are
  untouched); the tiering is an additive column when AI-in-the-loop applies, independent of
  which of the 12 registry types the spec falls under.
- No ADR (per the brief: guidance + a review lens, no done-definition change).

## Acceptance criteria

- AC1: `commands/test-plan.md` carries a Step 1c that (a) states the AI-in-the-loop detection
  signal, (b) names all three tiers with a one-line definition each, (c) states the floor rule
  verbatim, (d) states both hard don'ts verbatim, (e) states the smoke/retry doctrine
  (smoke = grading-iteration only, never a gate; retry = allowlisted benign-phrasing misses
  only, security/side-effect never retryable).
- AC2: Step 3's written `## Test plan` template shows the `Tier` / `Smoke-eligible` /
  `Retry-eligible` columns and an "AI-in-the-loop doctrine" block carrying the floor rule +
  both hard don'ts, gated on Step 1c applying.
- AC3: `commands/test-plan-review-team.md` dispatches 6 lenses (not 5) in every mention of the
  lens count (title description, Step 2 heading, the lens list, the scores template), and the
  new lens's text names both the CRITICAL triggers (a behavioral/security claim below the
  `behavioral` tier; a smoke run used as a gate).
- AC4: `docs/verification/test-design-standard.md` §5b keeps its existing 12-row dialect table
  byte-identical (the SPEC-056/057 meta-test parity check still passes) and gains a
  cross-reference paragraph pointing at the new Step 1c, placed after the table.
- AC5: `tests/test-meta.sh` pins the new content added under AC1-AC4 with a positive assertion
  per fact and at least two negative controls: the stale "5 subagents"/"5 angles" framing must
  not linger (would silently drop lens 6), and the brief's pre-registered negative control (a
  plan that puts a boundary claim in the config tier must match the lens's CRITICAL trigger
  language) is named explicitly in the lens text.

## Test plan

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|--------------|----------|-------|
| 1 | Step 1c present with all 5 doctrine facts | happy-path | AC1 | grep finds tier names, floor rule, both don'ts, smoke/retry doctrine in test-plan.md | `tests/test-meta.sh` SPEC-201 block, assertions 1-4 |
| 2 | Step 3 template carries the new columns + doctrine block | happy-path | AC2 | grep finds `Tier \| Smoke-eligible \| Retry-eligible` + `AI-in-the-loop doctrine` in the written-template block | `tests/test-meta.sh` SPEC-201 block, assertion 5 |
| 3 | test-plan-review-team lens count is 6 everywhere it's stated | happy-path | AC3 | title description, Step 2 heading, and scores template all say 6 | `tests/test-meta.sh` SPEC-201 block, assertions 6-7, 9 |
| 4 | 6th lens present, N/A-gated when no Tier column | happy-path | AC3 | grep finds "Tiering & floor" + "not an AI-in-the-loop plan" | `tests/test-meta.sh` SPEC-201 block, assertion 6 |
| 5 | §5b dialect table untouched (12-row parity) | regression | AC4 | row count over the awk `## 5b`..`## 6` range is exactly 12 | `tests/test-meta.sh` SPEC-201 block, assertion 11 |
| 6 | §5b gains the cross-reference paragraph | happy-path | AC4 | grep finds "Step 1c" inside the same awk range | `tests/test-meta.sh` SPEC-201 block, assertion 12 |
| 7 | negative control: stale 5-lens framing does not linger | failure-injection | AC5 | `grep -qE '5 (subagents\|angles)'` on test-plan-review-team.md is FALSE | `tests/test-meta.sh` SPEC-201 block, assertion 8 (NC) |
| 8 | negative control: brief's pre-registered boundary-in-config-tier case is named | failure-injection | AC5 | lens 6 text co-locates "config tier" with a boundary/mechanical pairing | `tests/test-meta.sh` SPEC-201 block, assertion 10 (NC) |
| 9 | full suite still green after the change | regression | AC1-AC5 | no unrelated FAIL introduced | `bash tests/test-meta.sh` (710/710 confirmed) |

### Coverage notes
- Categories skipped: none. Boundary/edge is realized as negative control 8 (case 8 above)
  since this is a docs/prompt change with no runtime input space of its own; the boundary being
  tested is the mis-tiering pattern itself, which is the crux the brief names.

## Verification

`bash tests/test-meta.sh` green, run from the repo root (698/698 before this change, 710/710
after: 12 new SPEC-201 assertions, no regressions).

## Rollback

`git revert`. Docs + command prose only; no lib change, no host state, no runner.
