# Spec: Mega-goal lane (sequenced multi-goal decomposition) (ID-037)
Generated: 2026-05-22
Status: VALIDATED

> Synthesized from **plan-for-mega-goal** (`zvadaadam/az-skills`,
> `skills/productivity/plan-for-mega-goal`), the multi-objective sibling of
> `plan-for-goal`. The kit already ships the `plan-for-goal` analog as `/kit:assign`;
> this spec adds the `plan-for-mega-goal` analog as `/kit:mega`. Sibling to **SPEC-032
> (ID-035)**: that spec owns the parallel/independent case (`/kit:dispatch`); this spec
> owns the sequential/dependent case. Supersedes the abandoned **ADR-0017** (no
> PHILOSOPHY amendment is needed; see DEC-004).
>
> **Revised after `/kit:spec-validate` 2026-05-22** (5-lens adversarial pass + a
> claude-code-guide verification of `/goal`). The core mechanism changed; see DEC-006.

## Problem

The kit handles one goal at a time. `/kit:assign` turns ONE backlog item into ONE
goal draft; SPEC-032's `/kit:dispatch` fans out N INDEPENDENT specs in parallel.
Neither covers one destination reached through 3-8 DEPENDENT sub-goals worked in
order, each its own PR: the "rewrite auth in five stacked steps" shape. Today you
decompose by hand, run the normal lane N times, and babysit the hand-offs; nothing
links the sub-goals to a shared destination or audits "are all N done?". This is the
plan-for-mega-goal shape: bigger than one `/goal` objective, smaller than a DAG.

Loop-mechanics correction (the reason ADR-0017 was wrong): this is NOT the rejected
unbounded outer loop. It is the kit's blessed **bounded in-session Stop-hook loop**
(PHILOSOPHY §3, the same primitive as the goal loop and the debug loop) walking a
disk-resident roadmap, because the multi-sub-goal objective exceeds a single
goal-draft cap. No new runtime, no scheduler.

### Verified activator behavior (load-bearing, shapes the design)
Confirmed via claude-code-guide against `code.claude.com/docs/goal`: the kit's
activators (the built-in `/goal`, `ralph-loop`) re-inject **only the literal
objective text** each turn, capped at **4000 chars**, and do **NOT** auto-re-read
files the goal text references. The model re-reads a file only if it chooses to. A
naive "pointer points at ROADMAP, the loop re-reads it each turn" is therefore
unreliable. The fix is **dynamic injection** (DEC-006): a tiny skill that runs
`` !`cat ROADMAP + next sub-goal draft` `` so the live next sub-goal is injected into
the prompt every turn. `/goal` does survive `/resume` (counters reset), so a bounded
multi-turn session is sound once the roadmap is re-surfaced via injection.

## Solution

### Approaches considered

1. **New `/kit:mega` planning command (chosen).** Decompose one intent into 3-8
   sub-goal drafts + a roadmap + a pointer prompt. Planning-only; execution is the
   existing bounded `/goal` loop, with the roadmap re-surfaced each turn by a small
   dynamic-injection skill (DEC-006), shipping a PR per sub-goal. Tradeoff: linear /
   simple-chain ordering only.
2. **Extend `/kit:assign` to a multi-goal mode (rejected as primary surface).**
   Overloads the single-goal mutator with an N-sub-goal scaffold; conflates one
   goal-draft with N. Mirror the upstream split: a separate command. See DEC-001.
3. **Reuse `/kit:dispatch` for sequenced sub-goals (rejected).** Dispatch is
   parallel/independent behind a disjointness gate; forcing it to sequence dependent
   sub-goals re-introduces ordering = a scheduler = the DAG line. Wrong tool.

### Chosen approach + why

Approach 1. A planning-only command that produces the scaffold and hands the pointer
to whatever activator is present (the built-in `/goal`, `ralph-loop`, or `goal-craft`),
exactly as `/kit:assign` does for single goals. The new build is thin: (1) the
decomposition + sub-goal drafts, (2) the roadmap (the completion audit), (3) the
roadmap-walking pointer convention, and (4) the small dynamic-injection skill that
re-surfaces the live next sub-goal each turn (forced by the verified activator
behavior). No execution primitive, no gate, no worktrees: those are SPEC-032's.

### The three-way boundary (load-bearing)

```
INDEPENDENT, parallel, tab-away        ──>  /kit:dispatch  (SPEC-032)
ONE destination, DEPENDENT, sequenced  ──>  /kit:mega      (this spec) one bounded loop, PR per sub-goal
RICH dependency graph (waves, topo)    ──>  gsd-2          (external, parked)
```

- A fully-independent set is `/kit:dispatch` territory; do not `/kit:mega` it.
- **"Lightly-ordered" defined (DEC-008):** `/kit:mega` permits only a *total order or
  a single chain* of sub-goals (1 → 2 → 3 ...). No fan-in (a sub-goal depending on two
  others) and no fan-out (two sub-goals consuming one then diverging). The first
  fan-in/fan-out is the **gsd-2 handoff tripwire**, not a reason to grow a scheduler.

### Extensibility & boundaries

- Load-bearing dimension = number of sub-goals (3-8). Below 3 it is one goal (use
  `/kit:assign`); above ~8 the loop loses coherence (the upstream rule).
- The roadmap is the source of truth for done-state + PR#s, walked top to bottom. No
  topological sort, no wave scheduler. The moment ordering needs a graph, hand off to
  gsd-2.

### Architecture

```
YOU ── /kit:mega "<intent>" ──┐
                              │ decompose → show plain-text list → APPROVE before write
                              ▼
   .claude/goals/<slug>/NN-*.md  (sub-goal drafts, /kit:assign-shaped)
   .claude/goals/<slug>/ROADMAP.md (sub-goal · Done= · order · PR# slot)   (DEC-002)
   POINTER_PROMPT (raw text; "complete the sub-goal surfaced by <next skill>
                   until ROADMAP fully checked"; ≤4000 chars)
                              │  paste pointer into /goal
                              ▼
   BOUNDED /goal LOOP (one long session, under the kit safety hooks)
     each turn: <next-subgoal skill> injects `!`cat ROADMAP + next draft``  (DEC-006)
       → pick first unchecked sub-goal
       → branch goal/<slug>/NN off goal/<slug>/NN-1  (DEC-007 plain-git chain)
       → normal lane → /kit:ship (open PR) → record PR# + check box
       → on CI-red / CHANGES_REQUESTED: fix on THIS branch, repush, do not advance
     before success: COMPLETION AUDIT (DEC-009) — every roadmap PR# is a real open PR
     stop on: all checked-with-verified-PR · blocked (Pause-if) · budget out
   HUMAN merges the chain bottom-up at ship. The loop never merges.
```

## Technical Design

### Interfaces (I/O contract)

- **Consumes:** one multi-objective intent (freeform, or an epic backlog item); the
  existing goal-loop activator; AGENTS.md zone 4 "Pause if" (the blocker contract).
- **Produces:** `.claude/goals/<slug>/ROADMAP.md` (the working roadmap, DEC-002); N
  sub-goal drafts (`.claude/goals/<slug>/NN-*.md`, each `/kit:assign`-shaped per
  SPEC-005); a pointer prompt saved as raw text and handed to the activator; a small
  dynamic-injection skill that surfaces the next unchecked sub-goal (DEC-006).
- **Invariants:**
  - `/kit:mega` is planning-only: it opens no PR, dispatches no worker.
  - Each sub-goal is a normal-lane unit shipped as its own PR by the loop, on a branch
    `goal/<slug>/NN` chained off `goal/<slug>/NN-1` (DEC-007).
  - The roadmap records a PR# per sub-goal as soon as the PR opens; a checked box has a
    PR# or it is not checked (the upstream mechanical rule).
  - **The loop runs under the kit's safety subset** (push-to-main blocker, safety-gate,
    anti-rationalization) and **never merges** (DEC-009). Merge is the human's gate at
    `/kit:ship`.
  - **Before claiming success the loop runs a completion audit** (DEC-009): for each
    `PR #N` on the roadmap, `gh pr view N` confirms it exists and is open; any checked
    box whose PR fails the check is unmarked and worked again.
  - Linear / single-chain ordering only; no DAG, no scheduler, no worktree fan-out.
  - No roadmap artifact in `_meta/` (the BACKLOG charter rule holds).

### Data model changes

The roadmap (`.claude/goals/<slug>/ROADMAP.md`, gitignored working index, DEC-002): a
checkbox list of sub-goals, each with an id, a one-line `Done =`, chain position, and a
PR# slot. **Build-state, not PM** (no story points, velocity, or sprint dates).
Durability lives in the per-sub-goal PRs + branches + CHANGELOG, not in the roadmap
file (mirrors SPEC-032's "the branch commits ARE the state"). Sub-goal drafts reuse the
SPEC-005 goal-draft contract, namespaced under the per-mega subfolder.

### API changes

New command `/kit:mega` + one small dynamic-injection skill (the next-sub-goal
surfacer, DEC-006). No change to `/kit:assign`, `/kit:execute`, or `/kit:dispatch`.

### UI / Infrastructure changes

None / none (CLI + markdown only). No new binary. Branch chaining uses plain `git` +
`gh` (no `ghstack`).

## Task Breakdown (firmed at validate 2026-05-22)

### Phase 1: Convention
- [ ] TASK-001: Document the roadmap home `.claude/goals/<slug>/ROADMAP.md` + the
  build-state-not-PM framing (DEC-002), respecting the "no ROADMAP in `_meta/`" rule.
  AC: the home is named in one place; a meta-test asserts no roadmap lands in `_meta/`.
- [ ] TASK-002: Define sub-goal-draft namespacing under `.claude/goals/<slug>/` + the
  branch-chain naming `goal/<slug>/NN` (DEC-007). AC: drafts reuse the SPEC-005
  contract; the subfolder does not collide with single-goal drafts; chain naming
  documented.

### Phase 2: The command + the injection skill (deps: TASK-001, TASK-002)
- [ ] TASK-003: Write `commands/mega.md`. Flow: decompose the intent to a sub-goal
  list, show it as plain text, get approval BEFORE writing disk (upstream: "the wrong
  decomposition is the most expensive failure"); enforce the 3-8 gate AND the
  single-chain rule (reject fan-in/fan-out, route to gsd-2); write each sub-goal as an
  `/kit:assign`-shaped draft + the roadmap + the pointer. AC: a <3, >8, or
  non-chain intent is rejected with a clear redirect; nothing is written before
  approval.
- [ ] TASK-004: Write the dynamic-injection skill that surfaces the next unchecked
  sub-goal via `` !`cat .claude/goals/<slug>/ROADMAP.md` `` + the next draft, so the
  loop re-reads live state each turn (DEC-006). AC: invoking it prints the current
  first-unchecked sub-goal; editing the roadmap between calls changes the output.
- [ ] TASK-005: The pointer-prompt convention. ≤4000 chars; "complete the sub-goal
  surfaced by <skill> until the roadmap is fully checked." Encode the "trust the agent
  on HOW, not WHAT" split: hard constraints (one PR per sub-goal; branch-chain off the
  prior sub-goal; "CI green" = the PR's CI; do not merge; box = PR# or unchecked; no new
  sub-goals mid-loop; on CHANGES_REQUESTED/CI-red fix on THIS branch and do not advance)
  vs good-defaults (retry tactics, left to judgment). AC: the pointer references the
  injection skill, is ≤4000 chars, and separates hard constraints from good defaults.

### Phase 3: Wiring + guards (deps: Phase 2)
- [ ] TASK-006: Register `/kit:mega` + the injection skill per the doc-impact map:
  `.claude-plugin/plugin.json` (marketplace inherits), README command table,
  `MANUAL.md`. AC: all surfaces updated; test-meta sees both.
- [ ] TASK-007: Tests. `tests/test-meta.sh`: `/kit:mega` + the skill exist + registered;
  the 3-8 + single-chain gate; the no-roadmap-in-`_meta/` guard; the pointer references
  the injection skill and is ≤4000 chars; the completion-audit + safety-subset language
  is present in the pointer convention. AC: `bash tests/test-meta.sh` passes.

## After state
- [ ] A maintainer turns one multi-objective intent into a single-chain roadmap of 3-8
  sub-goals + a pointer, pastes it, tabs away, and gets one chained PR per sub-goal
  until the roadmap is done. (Today: decompose by hand, run the normal lane N times.)
- [ ] The roadmap is re-surfaced every turn by the injection skill, not assumed
  re-read. (Verifiable: the skill output tracks roadmap edits.)
- [ ] Before success the loop audits every roadmap PR# against `gh pr view`. (Today:
  no audit; the "done with zero PRs" failure is possible.)
- [ ] The loop runs under the safety hooks and never merges. (Verifiable: no merge in
  the loop's git history; push-to-main blocker active.)
- [ ] `/kit:mega` opens no PR and runs no worker itself. (Verifiable: `git diff` after a
  run shows only scaffold writes.)
- [ ] The three-way boundary (mega vs dispatch vs gsd-2) is documented.

## Acceptance Criteria (global)
- [ ] `bash tests/test-meta.sh` passes with the new assertions.
- [ ] `/kit:mega` rejects a <3-sub-goal intent (route to `/kit:assign`), a >8 one, and a
  fan-in/fan-out intent (route to gsd-2), each with a clear message.
- [ ] The produced pointer is ≤4000 chars and references the dynamic-injection skill.
- [ ] The injection skill re-surfaces the live next sub-goal (roadmap edits change its
  output).
- [ ] The pointer convention contains the completion-audit rule and the safety-subset +
  no-merge rule.
- [ ] No roadmap artifact lands in `_meta/`.
- [ ] No execution primitive, gate, or worktree logic is duplicated from SPEC-032.

## Verification
```bash
bash tests/test-meta.sh \
  && test -n "$(grep -l 'kit:mega' .claude-plugin/plugin.json)" \
  && ! ls _meta/ | grep -qi roadmap \
  && grep -q 'completion audit\|gh pr view' commands/mega.md
```

## Edge Cases
1. **Intent is really one goal (<3 sub-goals).** Reject; point to `/kit:assign`.
2. **Sub-goals turn out fully independent.** Point to `/kit:dispatch` (parallel).
3. **Sub-goals need fan-in/fan-out (not a single chain).** The gsd-2 tripwire; reject
   at decompose, do not grow a scheduler.
4. **Loop blocked on a sub-goal.** AGENTS.md Pause-if: commit WIP + blocker note +
   stop; the human resumes by re-handing the pointer (`/goal` survives `/resume`).
5. **A sub-goal's PR gets CI-red / CHANGES_REQUESTED.** Fix on that sub-goal's own
   branch, repush, reply on the PR; do NOT check the box or advance until green-or-blocked.
6. **Activator only re-injects text (verified).** Handled by the dynamic-injection
   skill (DEC-006); the loop never relies on the goal text auto-re-reading the roadmap.
7. **Activator absent.** The scaffold is still a usable plain set of drafts + a roadmap
   (activator-agnostic, like `/kit:assign`); the human walks it manually.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Mega-goaling a small task | the 3-8 gate at decompose | reject, route to `/kit:assign` |
| Fan-in/fan-out smuggled in | the single-chain gate at decompose | reject, route to gsd-2 |
| Loop drifts (stale roadmap) | next-sub-goal output lags the file | dynamic-injection skill re-reads each turn (DEC-006) |
| Marked done, zero real PRs | completion audit: a roadmap PR# fails `gh pr view` | unmark the box, re-work; audit gates success (DEC-009) |
| Dependent sub-goal can't see prior code | build/test fails for missing prior work | branch-chain off `goal/<slug>/NN-1` (DEC-007) |
| Loop merges or pushes to main | safety hooks fire | safety subset is hard-hooked; loop never merges (DEC-009) |
| Roadmap rots into PM | story-point/velocity columns appear | the build-state-only rule; reject |

## Out of Scope
- **Parallel fan-out of independent sub-goals** → `/kit:dispatch` (SPEC-032).
- **A DAG / topological / wave scheduler / crash-recovery durability** → gsd-2.
- **A multi-day walk-away DURABLE loop.** The loop is bounded in-session (a long single
  session protected by session-state-save + post-compact-reinject), not respawning.
- **plan-for-mega-goal's NOTES.md + FEEDBACK.md artifacts.** For a bounded in-session
  loop the session transcript IS the event log; the roadmap holds blocker/PR state.
  Re-add only if a real run shows the in-session log is insufficient.
- **`ghstack` / codex specifics.** Replaced by the plain-git branch chain + the kit's
  activator.
- **Auto-merge.** Merge stays human, at `/kit:ship`.

## Decision Log
- DEC-001: **New `/kit:mega` command, not a `/kit:assign` mode.** Mirrors the upstream
  plan-for-goal vs plan-for-mega-goal split. **Confirmed by maintainer 2026-05-22.**
- DEC-002 (revised at validate): **Roadmap home = `.claude/goals/<slug>/ROADMAP.md`**
  (gitignored working index). Rationale: the original recommended an umbrella SPEC in
  `docs/specs/`, but that collides with the hooks that parse spec `- [ ]` task-state
  (context-readiness, spec-drift-guard). Durability instead lives in the per-sub-goal
  PRs + branches + CHANGELOG (SPEC-032's "branch commits ARE the state"). **Confirmed
  by maintainer 2026-05-22.**
- DEC-003: **Mega-goal is the sequential/dependent complement to SPEC-032's
  parallel/independent dispatch; gsd-2 is the DAG case.** Mutually exclusive by
  ordering shape.
- DEC-004: **No PHILOSOPHY amendment.** The lane is the blessed bounded in-session loop
  (§3). ADR-0017 (proposed an amendment) is rejected and superseded by this spec.
- DEC-005: **Port plan-for-mega-goal's "trust the agent on HOW, not WHAT" framing + the
  cite-the-failure rule style** into the pointer convention (TASK-005).
- DEC-006 (added at validate): **The roadmap is re-surfaced via a dynamic-injection
  skill (`` !`cat ROADMAP` ``), not via the goal text.** Forced by the verified
  activator behavior (`/goal` and `ralph-loop` re-inject only literal text, ≤4000
  chars, no auto-re-read). Without this the loop drifts on stale state. **Needs
  by maintainer 2026-05-22 (adds one small skill to the build).**
- DEC-007 (added at validate): **Dependent sub-goals chain in plain git:** branch
  `goal/<slug>/NN` off `goal/<slug>/NN-1`; the human merges bottom-up at `/kit:ship`.
  Replaces the `ghstack` stacking that was dropped with the toolchain. **Confirmed by maintainer 2026-05-22 (interface choice).**
- DEC-008 (added at validate): **"Lightly-ordered" = a single chain only** (no
  fan-in/fan-out). The first branch is the gsd-2 tripwire. Makes the boundary
  enforceable at decompose time.
- DEC-009 (added at validate): **The loop runs under the kit safety subset, never
  merges, and runs a completion audit before claiming success** (every roadmap PR#
  verified open via `gh pr view`). Closes the "marked done, zero PRs" failure
  (plan-for-mega-goal's founding failure mode) and the ID-027 autonomy-gate concern.

## Open questions
- DEC-001 (separate command), DEC-002 (roadmap home), DEC-006 (dynamic-injection
  skill), DEC-007 (plain-git branch chain): **all confirmed by maintainer 2026-05-22.**
- Sub-goal granularity: **resolved 2026-05-22** to the light goal-draft default (the
  loop runs `/kit:spec` / `/kit:next` on the fly per sub-goal; child specs are
  generated lazily, not pre-generated).
- Sequencing vs the in-flight pivot (ID-033..036): mega-goal does NOT depend on
  SPEC-032 but should land after `/goal` is folded into the operating manual (ID-033)
  so the pointer + injection convention is consistent. Maintainer to sequence.
