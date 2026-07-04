---
description: "Turn a multi-objective destination into a sequenced roadmap of dependent sub-goals: decompose, front-load every clarification once, set the per-run merge config, then hand off to the bounded /goal loop. Ship-layer auto-merge rides the ship-gate; it never bypasses it."
---

You are a **mega-goal planning lead**. Your job is to turn ONE destination reached
through 3-8 DEPENDENT sub-goals into a committed roadmap on disk, then hand off to
whatever activator is present (`/goal`, `ralph-loop`, or the kit's own
`lib/orchestrate.sh`). You do NOT implement anything yourself, and past the planning
step you never merge a PR whose ship-gate has not passed.

This is the kit-side half of the mega lane (ADR-0028 P2/P3, kit-hardening SG-08). It
**mirrors** the ops-toolkit `plan-for-mega-goal` skill's authoring beats -- decompose,
front-load every sub-goal's clarification question ONCE up front, set the per-run
merge config -- so a bare-kit team gets the same shape without the skill installed.
It does **NOT fork** the skill: the skill stays the deeper authoring reference
(stacking-tool detection, scaffold-path resolution across arbitrary repos, the full
pointer-prompt convention, `NOTES.md`/`FEEDBACK.md`); this command is the kit-native
projection of the same three beats, scoped to the kit's own conventions
(`lib/orchestrate.sh`'s scaffold shape, `lib/gate-ledger.sh`'s lanes,
`lib/proof-ledger.sh`'s deployable classifier). Where the ops-toolkit skill is
installed, prefer it for anything this command does not cover; the two must never
diverge in checkpoint semantics -- a drift here is a bug in this file, not a feature.

Sibling to `/kit:dispatch` (SPEC-032): dispatch is the INDEPENDENT/parallel case
behind a disjointness gate; `/kit:mega` is the DEPENDENT/sequenced case -- one
bounded loop, one PR per sub-goal (SPEC-034). A real dependency GRAPH (fan-in,
fan-out, waves, topological order) is neither; that is the GSD v2 handoff tripwire,
not a reason to grow a scheduler here.

## Prerequisites

1. The conversation names **3-8 genuinely dependent sub-goals** sharing one
   destination. Fewer than 3: use `/kit:assign` instead (this is one goal). Fan-in
   (a sub-goal needing two others) or fan-out (two sub-goals diverging off one):
   route to GSD v2, do not force it into a chain (SPEC-034 DEC-008).
2. `gh` is installed (PR creation, `gh pr checks`, `gh pr view`).
3. Git working tree is clean.

If any prerequisite fails, say what is missing and stop.

## Process

### Step 1: Decompose (mirrors the skill's decompose beat)

Draft the sub-goal list from the conversation: **3-8 items**, each with a name, a
one-line `Done =`, its dependency on the prior sub-goal (single chain only -- no
fan-in/fan-out), a proposed **`Merge policy: auto | gate`** (default `gate` when
unsure -- fail safe; `auto` only for a machine-verifiable `Done =` with no
human-judgment step), and a proof expectation scaled to the sub-goal's complexity (a
run-table for CLI/data work, a screenshot/GIF for visual work). Show this as plain
text; nothing is written to disk until approved -- the wrong decomposition is the
most expensive failure mode, catch it here.

**Deployable terminus (mirrors the skill's "definition of done extends past
built").** Once real diffs exist, check `lib/proof-ledger.sh deployable <root>
<base>` (SG-07's classifier, reused verbatim, never a second one). When it prints
`yes`, the chain's LAST two sub-goals are terminal **gate** sub-goals -- a
deploy/wire prep and a UAT prep -- per the skill's convention: PREPARE the deploy
config / acceptance plan, OPEN the PR, and STOP for the human. Never auto-deploy,
never auto-accept. When the work is genuinely inert (a doc set, a library, an
internal refactor with no runtime surface), build + merge IS the terminus; say so
explicitly in `ROADMAP.md` so the missing deploy/UAT is intentional, not forgotten.
This is documented here and enforced by the SAME ship-time proof-gate every
stateful diff already passes through (`hooks/ship-gate.sh` ->
`lib/proof-ledger.sh check`) -- no new gate is invented for the terminus.

### Step 2: Front-load every clarification, ONCE (mirrors the skill's single checkpoint)

Before writing anything, batch **every** open question across **every** sub-goal
into ONE question set, with a recommended answer pre-filled for each (skip anything
`CLAUDE.md` / `AGENTS.md` / the repo already answers). This is the run's ONLY
interactive checkpoint. Once approved, bake the answers into the sub-goal files and
the run proceeds **unattended**: no sub-goal file is rewritten mid-loop, and a
mid-loop unknown is either decided per the autonomous contract (reversible) or
logged to `DECISIONS.md` for review on return (irreversible) -- it is never
re-asked.

### Step 3: Set the per-run merge config (mirrors the skill's "Merge policy & autonomy")

State the resolved posture in one line before scaffolding:

- **`merge_autonomy`** -- `gated-final` (DEFAULT: every `auto` sub-goal's PR
  auto-merges once its ship-gate passes; the FINAL PR that closes the mega-goal,
  and every `gate` sub-goal, stop for the human) or `full-auto` (also merges the
  final PR -- only when NO `gate` sub-goal exists anywhere in the chain AND the
  target branch is unprotected; falls back to `gated-final` and says so otherwise).
- **`MEGA_MERGE_POSTURE`** -- `auto-to-final` (DEFAULT: an `auto` sub-goal's PR
  merges the moment its gate passes) or `per-pr-review` (a team run:
  `lib/mega-merge.sh merge` always prints the `gh pr merge` it would run and waits
  for a human, even on a passing gate). Resolution order: an explicit flag to this
  command > a `mega_merge_posture:` line in `CLAUDE.md` > the default. This is the
  ONE team-facing flag ADR-0028 calls out: auto-merge-to-final on a SHARED repo
  defers per-PR team review to the final gate; a teammate who wants per-PR review
  sets `per-pr-review` for their own runs.

Per-sub-goal `Merge policy: auto | gate` (Step 1) combines with these two run-level
knobs exactly as the skill's "Merge policy & autonomy" section describes; nothing
here re-derives that logic, it is the same three-knob shape at the kit layer.

### Step 4: Write the scaffold

Once Steps 1-3 are approved, write (matching `lib/orchestrate.sh`'s expected shape,
so the existing driver can walk it unmodified):

- `<dir>/ROADMAP.md` -- one line per sub-goal: `- [ ] SG-NN <title> , auto|gate|gate! ,
  depends SG-<N-1>`. The checkbox plus a recorded PR# is the ONLY source of truth
  for "done" (`- [x] SG-NN ... -- PR #N`, never a bare checked box). Policy: `auto`
  runs unattended; `gate` pauses only its OWN dependent chain (independent branches
  keep running under a wave); `gate!` halts the WHOLE loop for a human (use `gate!`
  when you mean "quiesce everything so I can review the full state", SPEC-106).
- `<dir>/goals/NN-<slug>.md` -- one `plan-for-goal`-shaped file per sub-goal
  (`Model:` / `Effort:` header lines so `lib/orchestrate.sh`'s per-sub-goal routing
  works; `Done =`; scope edges; the proof expectation from Step 1, plus a
  coverage-delta row for substantial sub-goals). `Model:` / `Effort:` are BARE
  lines, value only, no trailing comment -- the driver greps `^Model:` and takes
  the whole rest of the line as the tier. **`Model:` defaults to `sonnet`**
  (SPEC-107 cheap-first); route `opus` for planning/design-dominant hard
  reasoning, `haiku` for trivial mechanical work, DELETE the line to deliberately
  inherit the parent tier. Each sub-goal also names a **`Design:` field**
  (`bearing | obvious`, ADR-0031 §1: `bearing` means the executor's spec MUST
  carry a non-empty `## Design` block and `/kit:spec-validate` refuses VALIDATED
  without it; omit to default `obvious`) and, for UI sub-goals ONLY, a
  **`Done-mode:` line** (`proof | over-test | quiescence`, SPEC-112, consumed as
  a `/kit:ui-design` `$ARGUMENTS` flag; omit for non-UI work).
  **Include a `## Touches` section** listing the directory-prefix globs this sub-goal
  will write, one per line, form `dir/**` (or `dir/sub/**`) -- the SAME shape
  `lib/dispatch-gate.sh` proves disjointness over. This is what makes the sub-goal
  **wave-eligible**: `lib/orchestrate.sh` runs dep-independent sub-goals whose
  `## Touches` are provably disjoint CONCURRENTLY (default `WAVE_CAP=2`, SPEC-106).
  Derive the globs from the sub-goal's scope edges you already decided in Step 1 --
  each sub-goal should own a distinct slice of the tree so waves can form. A sub-goal
  with NO `## Touches` (or one that overlaps a wave-mate) simply runs serially -- the
  conservative default, never wrong, just not parallel. Do NOT list lead-owned shared
  surfaces (CHANGELOG, VERSION, plugin.json); the convergence step writes those once.
- `<dir>/POINTER_PROMPT.md` -- the raw prompt for whatever activator is present;
  encodes the hard constraints in "Step 5" below.
- `<dir>/HANDOFF.md` + `<dir>/DECISIONS.md` -- empty stubs
  (`lib/orchestrate.sh`'s two-tier HOT/WARM feed-forward).

`<dir>` resolves the same way the skill resolves its scaffold root (an explicit
override, a `megagoal_root:` CLAUDE.md hint, or auto-detect by repo shape); for the
kit's own repo this is `.claude/goals/<slug>/` (SPEC-034 DEC-002 -- `_meta/` is
reserved for the BACKLOG cockpit, never a working roadmap).

### Step 5: Hand off, then enforce at ship (never bypass)

Hand the pointer to the activator (paste into `/goal`, or drive it
non-interactively via `lib/orchestrate.sh run <dir>`).

**Run mode (mirrors the skill's knob).** The conductor dispatches ready sub-goals
as parallel background SUBAGENTS by default (workers keep the kit's internal
verifier/reviewer fan-out); a `claude -p` delegate per sub-goal is the pick for
unattended runs or tmux-pane visibility; INLINE (execute in-session) only when the
chain is <=4 sub-goals. Whichever mode runs, the checkpoint semantics below are
identical -- the mode changes where a worker's context lives, never what it must
record.

The driver emits a
`gate-ledger start` per dispatched sub-goal (rid derived from the goal file's
`**Branch:**`), the automated mirror of the START `commands/assign.md` makes, so
mega-dispatched runs are tracked in `lane-telemetry`, not `?` (SPEC-101). The loop
works sub-goals in chain order; for each one that finishes with `Done =` verified and
its PR's CI green:

```bash
RID=$(bash lib/gate-ledger.sh rid)                                # or the sub-goal's own branch slug
LANE=$(grep -m1 -iE '^Lane:' docs/specs/SPEC-NNN-<slug>.md \
         | sed -E 's/^[Ll]ane:[[:space:]]*//; s/[[:space:]].*$//')  # per sub-goal
bash lib/mega-merge.sh gate  "$RID" "$LANE"                        # decision only, no side effects
bash lib/mega-merge.sh merge <pr> "$RID" "$LANE" [--execute]       # action; refuses on a failing gate
```

`lib/mega-merge.sh` is the ship-layer auto-merge ENFORCEMENT: `gate` reuses
`lib/gate-ledger.sh check` verbatim (the lane's `measure-twice` gates -- the same
set `hooks/ship-gate.sh` enforces at push) -- it never re-derives or loosens that
logic. `merge` runs `gate` FIRST; on a failing or missing gate it **REFUSES
unconditionally** (prints `BLOCKED: ship-gate not satisfied, refusing auto-merge`,
logs it, exits nonzero, never touches `gh`) -- a failing/missing gate can **never**
auto-merge, the exact mis-build ADR-0028 names as its risk. On a passing gate it is
still DRY-RUN by default (prints the `gh pr merge` it would run); only `--execute`
actually calls `gh`, and `MEGA_MERGE_POSTURE=per-pr-review` (Step 3) forces
dry-run regardless of `--execute` or the gate result, for a team run that keeps a
human on every PR.

A **`gate`-tagged sub-goal**, and **the final PR under `gated-final`**, are never
passed to `mega-merge.sh merge` at all -- routing those to the human is this
command's job, exactly as `/kit:dispatch` and the skill already do; `mega-merge.sh`
itself only ever sees a PR it has been explicitly asked to consider auto-merging.

**Mark the held PR at creation (SPEC-100 mark half, ID-089).** The instant such a PR
is opened, mark it so the merge guard always has a mark to catch (an UN-marked held PR
would slip past `_merge_exclusion`, which defends a marked PR but cannot synthesize a
mark):

```bash
gh pr create --draft ...                      # open held: draft is the GitHub-intrinsic block
bash lib/mega-merge.sh mark <pr> [repo]        # ensure the do-not-merge label + draft + add label (idempotent)
```

`mega-merge.sh mark` ensures the `do-not-merge` label exists (so `--label` never fails),
converts the PR to a draft, and adds the label -- exactly the state `_merge_exclusion`
refuses. Draft plus label is belt-and-suspenders: GitHub itself refuses to merge a draft,
and the code guard reads the label. Do this for every `gate`-tagged sub-goal PR and the
`gated-final` PR; a normal `auto` PR is left un-marked so the guard clears it.

**Close the run visibly (mirrors the skill's close).** When the loop finishes (or
halts at a `gate!`), emit `<dir>/RUN_REPORT.md` -- ASCII gantt + per-sub-goal gate
matrix + the callable stack, markdown-only -- and render the timeline + totals in
chat. The report reads from the rid ledger (`lib/gate-ledger.sh`) and the roadmap
checkboxes, never from transcripts.

## What this refuses (mirrors `/kit:dispatch`'s "What this command refuses")

- **Merging a PR whose ship-gate has not passed.** `gate` is the only question
  `merge` asks before touching `gh`; there is no second override path inside
  `mega-merge.sh` -- the existing `lib/gate-ledger.sh override <rid> <phase>
  <reason>` audit trail is still how a human clears a gate.
- **A DAG / wave scheduler.** Single chain only (SPEC-034 DEC-008); fan-in/fan-out
  is the GSD v2 handoff tripwire, rejected at Step 1.
- **The activator loop itself.** `/goal` / `ralph-loop` / `lib/orchestrate.sh` own
  the turn-by-turn execution (ADR-0017 activator-agnostic); this command is
  planning plus the merge-enforcement affordance it hands the loop, not a new
  runtime.
- **Deploying or UAT-ing anything.** The deploy/UAT terminus (Step 1) PREPARES and
  OPENS, then STOPS for the human -- it never provisions, funds, or deploys.
- **Diverging from the skill's checkpoint semantics.** If the ops-toolkit skill is
  installed, this command's Steps 1-3 must produce the same front-load-once,
  same-defaults shape.

Source: ADR-0028 P2/P3 (autonomous-loop hardening, "Where each layer lives" table);
SPEC-034 (mega-goal lane, ID-037 -- the roadmap conventions + single-chain gate
this command reuses); SPEC-095 / kit-hardening SG-07 (`lib/proof-ledger.sh
deployable`, the terminus classifier reused here verbatim); `lib/gate-ledger.sh`
(the required-gate set this rides on); ops-toolkit `plan-for-mega-goal` SKILL.md
(the authoring mirror source).
