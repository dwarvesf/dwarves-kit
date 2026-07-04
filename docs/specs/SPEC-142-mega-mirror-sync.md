# Spec: Mega-mirror-sync (mega-goal sub-goal 09, mirror the tiny/consolidate/de-escalation knobs)

Generated: 2026-07-04
Status: VALIDATED
Lane: normal (docs-only projection into `commands/mega.md` plus one candidate
`lib/lane-classify.sh deescalate` call site addition at an existing invocation point;
no new lib file, no behavior change to any existing verb)
Design: obvious (ADR-0031 sec 1 -- a documented mirror of already-shipped upstream
knobs, not a new architecture decision)

## Problem

`commands/mega.md` (the kit-native `/kit:mega`) carries an explicit never-diverge contract
with the ops-toolkit `plan-for-mega-goal` skill: "the two must never diverge in checkpoint
semantics -- a drift here is a bug in this file, not a feature." Three knobs landed on the
skill side (and, for the third, on the kit's own `ship.md`/`lane-classify.sh`) after
`mega.md`'s last mirror sync (#164, 2026-07-04 earlier the same day):

1. **The tiny-decompose rule** (sub-goal 02's skill half, dotfiles, already merged upstream):
   a one-liner-scale item never gets its own sub-goal slot; it batches into one sweep
   sub-goal or runs as a `/kit:assign` `tiny`-lane task instead.
2. **Consolidate mode (remega)** (sub-goal 08, dotfiles): `consolidate=<slugA>,<slugB>[,...]`
   re-decomposes 2+ overlapping same-project mega scaffolds into one new scaffold, marking
   the old ones superseded.
3. **The ship-time lane de-escalation nudge** (sub-goal 07, this kit, SPEC-141): an advisory
   `lib/lane-classify.sh deescalate` call fired from `commands/ship.md` Step 8 when a
   `normal`/`full` lane shipped a tiny-sized diff.

`mega.md` is silent on all three. (1) and (2) are pure documentation drift: the skill moved,
the kit-native projection didn't. (3) is more than drift: `mega.md`'s own documented
per-sub-goal ship/close path (Step 5's `gate-ledger` + `mega-merge.sh` calls) never invokes
`commands/ship.md` at all, and per `WORKFLOW.md`'s "Mega-goal delegate execution" (ADR-0032),
a delegated child's session is conductor-invisible by design ("the conductor absorbs one line
per sub-goal; it never reads a child's transcript"). So even in the case where a delegated
child's own full-lifecycle run happens to invoke `/kit:ship` internally, any SPEC-141 nudge it
printed is swallowed inside that invisible child session and never surfaces at the layer a
human operating the mega-goal actually watches.

## Solution

### Approaches considered

1. **Add three documentation-only mirror paragraphs to `commands/mega.md`, plus one
   `lib/lane-classify.sh deescalate` call at the point `mega.md`'s Step 5 already derives
   `LANE`/`RID` for the `mega-merge.sh gate`/`merge` calls. CHOSEN.** Zero new lib files,
   zero behavior change to any existing verb: the deescalate call reuses the SPEC-141 verb
   verbatim, at an existing computed-values site. This is a pure projection: mirror the
   semantics, reference the skill for depth, keep the kit-native scoping already established
   by #164 (never re-derive the skill's own logic in `mega.md`, only name it).
2. **Have the delegated child always run `commands/ship.md` and trust its Step 8 to cover
   the nudge.** Rejected: `mega.md` does not currently document this dependency, the skill's
   own "Kit-adopted repos route through SDD" guidance for delegate mode says a sub-goal
   "drives the lane via `lib/` + `gate-ledger` directly" rather than mandating the `/kit:ship`
   script text, and even if it fired, ADR-0032's own conductor-invisibility rule means the
   nudge would never reach the human watching the mega run. Assuming coverage here would be
   the same "never over-claim portable enforcement" mistake AGENTS.md warns against.
3. **A new `lib/mega-deescalate.sh` or a mega-specific floor.** Rejected: SPEC-141's
   `deescalate()` already takes `--rid`/`--root`/`--base`/`--floor`; nothing about calling it
   from a second site needs a new script or a second floor constant.

### Chosen shape

Three `commands/mega.md` edits, no `lib/` behavior change:

- **Step 1 (Decompose):** one paragraph mirroring the skill's tiny-item rule (batch into one
  sweep sub-goal, keep each item's own check line, or route via `/kit:assign` `tiny` lane
  outside the mega-goal).
- **New `## Consolidate mode (remega, mirrors the skill's mode)` section**, placed after
  Step 5 and before `## What this refuses` (mirroring the skill GUIDE.md's own placement of
  its Consolidate mode section after the normal produce/use flow). Summarizes the seven steps
  and the when-NOT table at kit-native scoping: reuses `lib/dispatch-gate.sh` for `## Touches`
  overlap (the same checker Step 4 already names), reuses `lib/spec-next.sh reserve` for the
  spec-number step, and notes this kit has no separate `release` verb (an unclaimed
  reservation self-expires on its own TTL, so "release" here is a no-op, not a new command),
  and points the archive/supersede step at the kit's own existing goal-draft lifecycle
  (`lib/goal-drafts.sh archive`, `WORKFLOW.md` "Goal drafts (.claude/goals/)") as the nearest
  kit-native analog rather than inventing a new archive mechanism or citing ops-toolkit's
  private `_meta/README.md` (which #164 already declined to mirror for the same reason).
- **Step 5:** one added prose paragraph + one added `bash` line
  (`bash lib/lane-classify.sh deescalate "$LANE" --rid "$RID"`) right after the existing
  `RID=`/`LANE=` derivation, explaining why the mirror needs an explicit call here (conductor-
  visibility, per ADR-0032) rather than assuming ship.md's own copy already covers it.

## Design

### Why the de-escalation call belongs at mega.md's own Step 5, not left implicit

`mega.md`'s per-sub-goal ship/close is NOT a call into `commands/ship.md`; it is its own
documented path (`gate-ledger start` at dispatch, `mega-merge.sh gate`/`merge` at close). The
skill's own delegate-mode guidance ("Kit-adopted repos route through SDD... drive the lane via
`lib/` + `gate-ledger` directly") and this run's own empirical dispatch prompts (every sub-goal
in this stack, this one included, was told to `gh pr create` directly, never "run `/kit:ship`")
confirm the child does not reliably route through `ship.md`'s script text. And even where it
might, ADR-0032's conductor-invisibility rule means the nudge would be swallowed in a child
transcript the conductor never reads. The correct, minimal fix is therefore to add the SAME
advisory call at the ONE place in `mega.md`'s own text where `LANE` and `RID` are already in
hand for every finished sub-goal (the existing `mega-merge.sh gate` call site) -- zero new
computation, one more advisory line the conductor's own visible output now carries.

### Why this is documentation-plus-one-call, not a new mechanism

Every piece of machinery named in the Consolidate mode mirror already exists in this kit:
`lib/dispatch-gate.sh` (disjointness), `lib/spec-next.sh reserve` (SPEC-128), the goal-draft
archive lifecycle (`lib/goal-drafts.sh`), and `lib/lane-classify.sh deescalate` (SPEC-141).
Nothing here invents a checker, a scheduler, or a second floor; it names what already runs.

## Acceptance criteria

1. `commands/mega.md` contains a tiny-item-batching paragraph in Step 1.
2. `commands/mega.md` contains a `## Consolidate mode` section covering all seven steps + the
   when-NOT table, at kit-native scoping (no re-derivation of the skill's own logic).
3. `commands/mega.md` Step 5 contains an added `bash lib/lane-classify.sh deescalate ...` line
   at the existing `LANE`/`RID` derivation site, with prose explaining the conductor-visibility
   rationale.
4. A never-diverge checklist (this spec or the PR body) enumerates every mega.md beat against
   its skill-side (or kit-side, for SPEC-141) counterpart, each marked SYNCED, with a pointer
   to where each lives on both sides.
5. No `lib/` file's existing behavior changes; the only new invocation is the added
   `deescalate` call, which reuses SPEC-141's verb verbatim.

## Review

Self-reviewed (sub-goal worker, no team review requested for this docs-plus-one-call lane;
`lane_rank(normal)` does not require `/kit:review-team`, only the standard single-lens pass,
which this run substitutes with the acceptance-criteria grep table below since the change has
no runtime surface beyond the one added `bash` line, which is unreachable dead prose until an
operator's copy-paste, per `verify` skill guidance for docs-shaped diffs).

## Verification

```bash
rg -n 'tiny|consolidat|deescalate|LANE_DEESCALATE' commands/mega.md
```

Expect: rows in Step 1 (tiny), a `## Consolidate mode` section (consolidat, multiple rows),
and a `deescalate`/de-escalation row in Step 5.

## Test plan

Docs-only change (plus one dead-until-copy-pasted `bash` line reusing an existing, already-
tested verb). No new automated test: `SPEC-141-lane-de-escalation.md`'s own test suite already
covers `deescalate()`'s behavior; this spec adds no second call site with different semantics
to test, only a second *documented* invocation of the same verb.

## Never-diverge checklist (skill <-> mega.md, beat by beat)

Every beat either side carries, so the NEXT skill change has a diff target.

| Beat | Skill-side location | `mega.md` location | Status |
|---|---|---|---|
| Decompose (3-8 items, `Done =`, `Merge policy`, proof expectation) | `references/GUIDE.md` "How to use it" step 3 | Step 1 | SYNCED (pre-existing) |
| Front-load every clarification ONCE | `references/GUIDE.md` step 3's batched question set | Step 2 | SYNCED (pre-existing) |
| Merge config (`merge_mode` / `merge_autonomy` / per-sub-goal tag) | `references/GUIDE.md` "Merge policy & autonomy" | Step 3 | SYNCED (pre-existing) |
| Scaffold fields (`Model:`/`Effort:`/`Design:`/`Done-mode:`, `## Touches`) | `references/subgoal-template.md` | Step 4 | SYNCED (#164) |
| Run mode (subagent-delegate \| delegate \| inline) | `references/invocation-template.md` "Run mode" | Step 5 | SYNCED (#164) |
| Close the run visibly (RUN_REPORT / event log) | `references/GUIDE.md` step 9 + `references/notes-template.md` Event log | Step 5 "Close the run visibly" | SYNCED (#164) |
| Tiny-item batching rule | `references/GUIDE.md` "How to use it" step 3, "Tiny items never become their own sub-goal" | Step 1 (this spec) | SYNCED (this PR) |
| Consolidate mode (remega) | `references/GUIDE.md` "Consolidate mode (remega)" + `SKILL.md` `argument-hint` | `## Consolidate mode` (this spec) | SYNCED (this PR) |
| Ship-time lane de-escalation | this kit's own `SPEC-141-lane-de-escalation.md` + `commands/ship.md` Step 8 bullet 4 (no skill-side counterpart -- kit-originated knob) | Step 5, added `deescalate` call (this spec) | SYNCED (this PR, kit-to-kit mirror for conductor visibility) |
| OPERATE.md RUN CONTRACT pointer | `references/OPERATE.md` | (none) | DELIBERATELY NOT MIRRORED -- private ops-toolkit path, parked on portability re-apply (ID-246), per #164 |

## Out of scope

- Any change to `lib/lane-classify.sh`, `lib/mega-merge.sh`, `lib/orchestrate.sh`,
  `lib/spec-next.sh`, or `lib/goal-drafts.sh` behavior.
- Building the optional `lib/` overlap-report helper the skill's Consolidate mode section
  calls out as "not required" (judgment-driven procedure, no daemon).
- Re-applying the OPERATE.md RUN CONTRACT pointer #164 deliberately left unmirrored (still
  parked on the ops-toolkit portability re-apply, ID-246).
