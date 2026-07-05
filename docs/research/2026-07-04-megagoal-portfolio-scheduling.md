---
title: "Mega-goal portfolio: parallel scheduling + reconsolidation (remega)"
date: 2026-07-04
purpose: >
  Design note for running multiple mega-goals per day. Three answers by case:
  cross-repo portfolio waves (schedule, v1, zero new infra), same-repo but
  provably-disjoint domains (reserve + isolate + merge-queue), and the common hard
  case Han named: multiple mega-goals of the SAME project drafted at different times
  with incomplete information, where the answer is not scheduling but
  RECONSOLIDATION: re-decompose the union of their sub-goals into one new mega-goal
  and let its waves create the parallelism. Design source for ID-256..259.
source_repos: [ops-toolkit, dwarves-kit, dotfiles]
refresh_cadence: none
next_review: null
status: active
---

# Mega-goal portfolio: scheduling + reconsolidation

**Problem.** A mega-goal takes ~2h wall (pre-advisor estimate; ID-245's
time-to-done advisor is the real meter). Same-project mega-goals collide (file
overlap, spec numbers, merge trains), so a day currently fits few of them. And the
root cause Han identified: mega-goals for one project are AUTHORED AT DIFFERENT
TIMES with incomplete information, so their decompositions overlap by accident,
not by necessity.

## The decision tree

```
2+ queued mega-goals. Can they run in parallel?
│
├─ DIFFERENT repos
│    → §1 portfolio wave v1. Safe today, zero new infra.
│
├─ SAME repo, DIFFERENT domains (monorepo case, e.g. two unrelated tools/)
│    → run both: spec-number block reserve (shipped, kit-run-integrity)
│      + worktree per mega + ONE merge queue per repo
│      (_meta bookkeeping serializes even when code is disjoint).
│
└─ SAME project, overlapping scope        ← the common hard case
     → §2 RECONSOLIDATE (remega): do not schedule around the overlap,
       re-plan it away, then one mega-goal's own waves parallelize.
```

Deliberately NOT built: a cross-mega DAG scheduler (the GSD v2 tripwire in
SPEC-034 stays), and blind same-project parallelism (proving disjointness between
scaffolds authored blind to each other is exactly the wrong place to spend
effort; consolidation deletes the problem instead).

## 1. Portfolio wave v1 (cross-repo, run today)

The cockpit already computes the queue: `_meta/board-all next` = top queued item
per repo. Portfolio wave = pick 2-3 mega-goals from DIFFERENT repos, one conductor
each (tmux/cmux pane, or a background subagent conductor), cap 2-3.

The real cap is not CPU, it is **Han's gate attention**: every `gate` PR stops for
him. So schedule around attention, not cores:

| Slot | What runs |
|---|---|
| Daytime, Han online | 1-2 `gated-final` mega-goals, gate-staggered (start the second when the first reaches mid-chain, so gate-stops do not pile up) |
| Review window (morning/evening, ~30 min) | Batch-process ALL held gate PRs in one sitting |
| Overnight | FULL-AUTO mega-goals (e.g. vibe-dex-saas ID-244) via `claude -p` + cron/launchd |

Cheap intra-mega knob while waiting for advisor data: `WAVE_CAP` defaults to 2;
a chain with many dep-independent sub-goals can raise it to 3-4.

## 2. Reconsolidation (remega): merge same-project mega-goals into one

**Insight (Han, 2026-07-04):** when mega-goals of one project overlap, the
overlap is an artifact of drafting them at different times with partial
information. The fix is a re-planning pass, not a scheduler.

### Procedure

1. **Inventory.** Read every candidate mega-goal's ROADMAP + goals/NN files:
   status (done/claimed/queued), Touches, deps, `Done =`, merge policy. Done
   sub-goals import as `[x] ... PR #N` rows, NEVER re-run. An in-flight sub-goal
   (open PR) finishes under its old mega first (cheapest), or imports as claimed.
2. **Overlap analysis.** Pairwise Touches intersection (reuse
   `lib/dispatch-gate.sh`, no new checker) + a semantic pass: near-duplicate
   sub-goals across megas are DEDUPED; same-module sub-goals become MERGE
   candidates.
3. **Re-decompose.** One new ROADMAP from the union: dedupe, merge, then re-derive
   the dependency graph from ACTUAL code/interface dependencies (the original
   chain orders encoded authoring sequence, not true deps). Re-slice `## Touches`
   so each new sub-goal owns a disjoint module slice: this re-slicing is the step
   that CREATES wave parallelism.
4. **Front-load clarifications ONCE, again.** A fresh unified question set over
   the union. This directly repairs the original sin (each mega was drafted with
   incomplete info; the union sees the whole picture).
5. **Spec-number block reserve** for the new roadmap (shipped mechanism); release
   the old megas' unclaimed numbers.
6. **Provenance.** Every consolidated sub-goal lists its origins (`from:
   mega-A/SG-03 + mega-B/SG-01`), so nothing dangles at audit time.
7. **Supersede, do not delete.** Old mega-goal folders get `superseded_by:
   <new-slug>` in the ROADMAP header and archive per the lifecycle rule; their
   backlog rows collapse into the new mega's row (old rows moved to Recently
   closed with the pointer).

### When NOT to consolidate

- One mega is >=80% done: just finish it, import nothing.
- Different merge postures / different tenants: keep separate.
- Fewer than ~2 megas x 3 remaining overlapping sub-goals: the consolidation
  session (~30-60 min planning) costs more than it saves.

### Landing spots

- `plan-for-mega-goal` skill: a **Consolidate mode** section (input = 2+ scaffold
  dirs; output = one new scaffold + superseded markers). The skill already owns
  decompose + front-load-once + Touches authoring; consolidation is those same
  beats over a union input.
- `/kit:mega` gains the mirror paragraph (kit-native projection, same
  never-diverge contract as the rest of mega.md).
- Optional later: a small lib helper printing the pairwise-overlap report
  (dispatch-gate reuse); manual-first, no new daemon.

## 3. How this composes with the rest of the family

- ID-245's time-to-done advisor supplies the DATA (which megas are slow, where
  waves were serial); this note supplies the ACTIONS (schedule cross-repo,
  consolidate same-project).
- ID-247's spec-race fix + kit-run-integrity's number reserve are prerequisites
  already shipped.
- Gate-visibility sweep (ID-256) makes RUN_REPORT trustworthy enough to compare
  portfolio runs.

## Backlog map

| Row | Scope |
|---|---|
| ID-256 | gate-visibility sweep: 18 dark commands, emit-owed vs utility |
| ID-257 | tiny-work decompose rule + lane de-escalation |
| ID-258 | portfolio scheduler v1 (cross-repo waves, attention-aware) |
| ID-259 | remega: consolidate mode in skill + /kit:mega mirror |
