---
description: "Turn a multi-objective destination into a sequenced roadmap of dependent sub-goals: decompose, front-load every clarification once, set the per-run merge config, then hand off to the bounded /goal loop. Ship-layer auto-merge rides the ship-gate; it never bypasses it."
---

You are a **mega-goal planning lead**. Your job is to turn ONE destination reached
through 3-8 DEPENDENT sub-goals into a committed roadmap on disk, then hand off to
whatever activator is present (`/goal`, `ralph-loop`, or the kit's own
`lib/queue/orchestrate.sh`). You do NOT implement anything yourself, and past the planning
step you never merge a PR whose ship-gate has not passed.

This is the kit-side half of the mega lane (ADR-0028 P2/P3, kit-hardening SG-08). It
**mirrors** the ops-toolkit `plan-for-mega-goal` skill's authoring beats -- decompose
(including the tiny-item batching rule), front-load every sub-goal's clarification
question ONCE up front, set the per-run merge config, and (as its own mode) Consolidate
overlapping same-project megas -- so a bare-kit team gets the same shape without the
skill installed.
It does **NOT fork** the skill: the skill stays the deeper authoring reference
(stacking-tool detection, scaffold-path resolution across arbitrary repos, the full
pointer-prompt convention, `NOTES.md`/`FEEDBACK.md`); this command is the kit-native
projection of the same three beats, scoped to the kit's own conventions
(`lib/queue/orchestrate.sh`'s scaffold shape, `lib/gate/gate-ledger.sh`'s lanes,
`lib/gate/proof-ledger.sh`'s deployable classifier). Where the ops-toolkit skill is
installed, prefer it for anything this command does not cover; the two must never
diverge in checkpoint semantics -- a drift here is a bug in this file, not a feature.

Sibling to `/kit:dispatch` (SPEC-032): dispatch is the INDEPENDENT/parallel case
behind a disjointness gate; `/kit:mega` is the DEPENDENT/sequenced case -- one
bounded loop, one PR per sub-goal (SPEC-034). A real dependency GRAPH (fan-in,
fan-out, waves, topological order) is neither; that is the GSD v2 handoff tripwire,
not a reason to grow a scheduler here.

The intake ladder below (mirrors the skill's ladder verbatim, SPEC-142) is the FIRST
check, before Prerequisites: it decides whether this command is even the right one to
invoke for the task at hand.

<!-- BEGIN triage-ladder -->
## Intake triage ladder (check first, before drafting anything)

Before drafting a goal, a scaffold, or a plan, classify the task against three rungs. This is a MUST-check routing step, not advice: a task that fits a lower rung never gets a higher rung's ceremony.

1. **DIRECT kit lane, in-session.** One file, one behavior, one obvious proof. `lane-classify` calls it tiny or small: one worker drafts the change, verifies it, opens one PR. No scaffold, no conductor; the gate-ledger still records. Worked example: fixing a broken link in one README section, one file changed, verified by rendering the link.
2. **Single `/goal`.** One objective, multiple steps, one stopping condition. Worked example: "users can sort the trade log by realized PnL", a multi-step feature with one verification command, handed to `/goal` via `plan-for-goal`.
3. **Mega-goal.** Multiple objectives, multiple repos, or multiple gates converging on one destination. Worked example: the runner-fastpath mega-goal itself, eight sub-goals across three repos (dotfiles, dwarves-kit, ops-toolkit) each running its own `/goal` with its own PR, converging on one overnight runner.

Escape hatch: the user explicitly asking for a mega-goal overrides the ladder; never downgrade a request the user has already sized.
<!-- END triage-ladder -->

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

**Tiny items never earn their own sub-goal (mirrors the skill's tiny-item rule).** A
one-liner-scale item (a config flip, a doc line, a one-line guard) does not earn a
dedicated slot in a chain otherwise sized 3-8 substantial items. Batch every tiny item
into ONE sweep sub-goal, each item keeping its own check line inside that sub-goal's
`Done =` so it stays individually auditable, or route it as a `/kit:assign` `tiny`-lane
task outside the mega-goal entirely (`lib/classify/lane-classify.sh classify` will size it
`tiny` on its own merits). Reserve dedicated sub-goals for work substantial enough to
need its own PR, proof, and merge gate.

**Deployable terminus (mirrors the skill's "definition of done extends past
built").** Once real diffs exist, check `lib/gate/proof-ledger.sh deployable <root>
<base>` (SG-07's classifier, reused verbatim, never a second one). When it prints
`yes`, the chain's LAST two sub-goals are terminal **gate** sub-goals -- a
deploy/wire prep and a UAT prep -- per the skill's convention: PREPARE the deploy
config / acceptance plan, OPEN the PR, and STOP for the human. Never auto-deploy,
never auto-accept. When the work is genuinely inert (a doc set, a library, an
internal refactor with no runtime surface), build + merge IS the terminus; say so
explicitly in `ROADMAP.md` so the missing deploy/UAT is intentional, not forgotten.
This is documented here and enforced by the SAME ship-time proof-gate every
stateful diff already passes through (`hooks/ship-gate.sh` ->
`lib/gate/proof-ledger.sh check`) -- no new gate is invented for the terminus.

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
  Resolution order (SPEC-187 / SG-03): an explicit choice made in THIS step >
  `bash lib/config/kit-config.sh` (source it, then `kit_config_get mega.merge_autonomy`;
  project `.kit.toml` > kit-root `kit.toml`) > the `gated-final` default above. This
  knob has no runtime env-var mirror (unlike the pair below): it is a per-run
  decision made HERE, at scaffold time, so the config layer is the one place an
  adopter can set a standing default without re-answering this step every mega-goal.
- **`MEGA_MERGE_POSTURE`** -- `auto-to-final` (DEFAULT: an `auto` sub-goal's PR
  merges the moment its gate passes) or `per-pr-review` (a team run:
  `lib/goal/mega-merge.sh merge` always prints the `gh pr merge` it would run and waits
  for a human, even on a passing gate). Resolution order (SPEC-187 / SG-03): an
  explicit `--posture=<value>` flag to `mega-merge.sh merge` > the `MEGA_MERGE_POSTURE`
  env var > the config layer's `[mega].mega_merge_posture` (project `.kit.toml` >
  kit-root `kit.toml`) > the `auto-to-final` default. A `mega_merge_posture:` line in
  `CLAUDE.md` is the older, still-honored per-conversation override; the config
  layer is the durable, cross-session equivalent. This is the ONE team-facing flag
  ADR-0028 calls out: auto-merge-to-final on a SHARED repo defers per-PR team review
  to the final gate; a teammate who wants per-PR review sets `per-pr-review` for
  their own runs (env, or their own `.kit.toml`).

Per-sub-goal `Merge policy: auto | gate` (Step 1) combines with these two run-level
knobs exactly as the skill's "Merge policy & autonomy" section describes; nothing
here re-derives that logic, it is the same three-knob shape at the kit layer.

### Step 4: Write the scaffold

Once Steps 1-3 are approved, write (matching `lib/queue/orchestrate.sh`'s expected shape,
so the existing driver can walk it unmodified):

- `<dir>/ROADMAP.md` -- one line per sub-goal: `- [ ] SG-NN <title> , auto|gate|gate! ,
  depends SG-<N-1>`. The checkbox plus a recorded PR# is the ONLY source of truth
  for "done" (`- [x] SG-NN ... -- PR #N`, never a bare checked box). Policy: `auto`
  runs unattended; `gate` pauses only its OWN dependent chain (independent branches
  keep running under a wave); `gate!` halts the WHOLE loop for a human (use `gate!`
  when you mean "quiesce everything so I can review the full state", SPEC-106).
- `<dir>/goals/NN-<slug>.md` -- one `plan-for-goal`-shaped file per sub-goal
  (`Model:` / `Effort:` header lines so `lib/queue/orchestrate.sh`'s per-sub-goal routing
  works; `Done =`; scope edges; the proof expectation from Step 1, plus a
  coverage-delta row for substantial sub-goals). `Model:` / `Effort:` are BARE
  lines, value only, no trailing comment -- the driver greps `^Model:` and takes
  the whole rest of the line as the tier. **`Model:` defaults to `sonnet`**
  (SPEC-107 cheap-first); route `opus` for planning/design-dominant hard
  reasoning AND for a docs/design sub-goal that REWRITES for cohesion or
  persuasion (not a light append) -- write those with the `/kit:pitch`
  discipline (outcome-first, evidence-grounded; delete the stale narrative,
  do not just append) so the presentation convinces; a small docs update
  stays `sonnet`. `haiku` for trivial mechanical work, DELETE the line to deliberately
  inherit the parent tier. Each sub-goal also names a **`Design:` field**
  (`bearing | obvious`, ADR-0031 §1: `bearing` means the executor's spec MUST
  carry a non-empty `## Design` block and `/kit:spec-validate` refuses VALIDATED
  without it; omit to default `obvious`) and, for UI sub-goals ONLY, a
  **`Done-mode:` line** (`proof | over-test | quiescence`, SPEC-112, consumed as
  a `/kit:ui-design` `$ARGUMENTS` flag; omit for non-UI work).
  **Include a `## Touches` section** listing the directory-prefix globs this sub-goal
  will write, one per line, form `dir/**` (or `dir/sub/**`) -- the SAME shape
  `lib/gate/dispatch-gate.sh` proves disjointness over. This is what makes the sub-goal
  **wave-eligible**: `lib/queue/orchestrate.sh` runs dep-independent sub-goals whose
  `## Touches` are provably disjoint CONCURRENTLY (default `WAVE_CAP=2`, SPEC-106).
  Derive the globs from the sub-goal's scope edges you already decided in Step 1 --
  each sub-goal should own a distinct slice of the tree so waves can form. A sub-goal
  with NO `## Touches` (or one that overlaps a wave-mate) simply runs serially -- the
  conservative default, never wrong, just not parallel. Do NOT list lead-owned shared
  surfaces (CHANGELOG, VERSION, plugin.json); the convergence step writes those once.
- `<dir>/POINTER_PROMPT.md` -- the raw prompt for whatever activator is present;
  encodes the hard constraints in "Step 5" below.
- `<dir>/HANDOFF.md` + `<dir>/DECISIONS.md` -- empty stubs
  (`lib/queue/orchestrate.sh`'s two-tier HOT/WARM feed-forward).

`<dir>` resolves the same way the skill resolves its scaffold root (an explicit
override, a `megagoal_root:` CLAUDE.md hint, or auto-detect by repo shape); for the
kit's own repo this is `.claude/goals/<slug>/` (SPEC-034 DEC-002 -- `_meta/` is
reserved for the BACKLOG cockpit, never a working roadmap).

### Step 5: Hand off, then enforce at ship (never bypass)

Hand the pointer to the activator (paste into `/goal`, or drive it
non-interactively via `lib/queue/orchestrate.sh run <dir>`).

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
RID=$(bash lib/gate/gate-ledger.sh rid)                                # or the sub-goal's own branch slug
LANE=$(grep -m1 -iE '^Lane:' docs/specs/SPEC-NNN-<slug>.md \
         | sed -E 's/^[Ll]ane:[[:space:]]*//; s/[[:space:]].*$//')  # per sub-goal
bash lib/goal/mega-merge.sh gate  "$RID" "$LANE"                        # decision only, no side effects
bash lib/goal/mega-merge.sh merge <pr> "$RID" "$LANE" [--execute]       # action; refuses on a failing gate
bash lib/classify/lane-classify.sh deescalate "$LANE" --rid "$RID"          # advisory nudge, mirrors ship.md Step 8
```

**Ship-time de-escalation, mirrored here explicitly (SPEC-141).** `mega.md`'s per-sub-goal
ship/close is this Step -- `gate-ledger` + `mega-merge.sh` -- never a call into
`commands/ship.md`'s script, so its Step 8 bullets (the significance record, the ★-tap nudge,
the pitch offer, the SPEC-141 de-escalation nudge) are not guaranteed to fire here just because
they exist there. Worse, under DELEGATE mode (WORKFLOW.md "Mega-goal delegate execution",
ADR-0032) each sub-goal runs in a fresh headless session, and the conductor "never reads a
child's transcript" -- so even a child that happens to invoke `/kit:ship` internally would have
any nudge it printed swallowed inside that invisible session. The fix reuses the SAME `LANE`
and `RID` this Step already computes for the `mega-merge.sh gate` call above -- no new
computation, no new verb, just the existing SPEC-141 `deescalate` call made explicit at the
one place a human watching the mega run actually sees output.

`lib/goal/mega-merge.sh` is the ship-layer auto-merge ENFORCEMENT: `gate` reuses
`lib/gate/gate-ledger.sh check` verbatim (the lane's `measure-twice` gates -- the same
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
bash lib/goal/mega-merge.sh mark <pr> [repo]        # ensure the do-not-merge label + draft + add label (idempotent)
```

`mega-merge.sh mark` ensures the `do-not-merge` label exists (so `--label` never fails),
converts the PR to a draft, and adds the label -- exactly the state `_merge_exclusion`
refuses. Draft plus label is belt-and-suspenders: GitHub itself refuses to merge a draft,
and the code guard reads the label. Do this for every `gate`-tagged sub-goal PR and the
`gated-final` PR; a normal `auto` PR is left un-marked so the guard clears it.

**The convergence gate dispatches advisor P5+P6, explicitly, with an emit (SPEC-145).** Once
every sub-goal in the chain is merged (or the run halts at the final `gate!`/`gated-final`
boundary), dispatch the `advisor` agent TWICE, in-harness, over the assembled stack diff
(`base..HEAD` across the whole mega-goal, not any one sub-goal's diff): once as **P5
(critique)** -- the extra cross-cutting lens over the WHOLE chain, catching a cross-sub-goal
inconsistency no single sub-goal's own review was scoped to see -- and once as **P6
(over-suggest)** -- proposals surfaced to the human just before the final review, routed to
the mega-goal's `NOTES.md` under `## Proposed additions`. This closes ONE gap a 2026-07-04
audit found: `commands/mega.md` previously named no advisor invocation path at all, so a
subagent-delegate run (where each child self-records its OWN `review ran` line per the worker
contract, never a `/kit:review-team` dispatch) left the advisor completely unreached. It
mirrors the ADVISOR SLICE of the ops-toolkit `plan-for-mega-goal` skill's own convergence-gate
beat (`references/GUIDE.md` step 6a, `references/OPERATE.md` "The convergence gate is
COMPOSED, not improvised"), which already prescribes this exact dispatch + grammar --
"catching up" (never-diverge, SPEC-142) means this ONE beat, not full parity: the skill's
convergence gate is COMPOSED of `/kit:verify` + `/kit:review-team` + advisor P5/P6 together,
and this paragraph wires only the advisor third of that composition. `commands/mega.md` still
names no `/kit:verify` or `/kit:review-team` dispatch of its own at the assembled-stack close
(a pre-existing gap, out of this sub-goal's scope, not newly introduced or newly hidden by
this paragraph).

Record each mode's own ledger row the instant it returns, fail-open, under the FINAL
sub-goal's rid -- the de-facto convention the older free-text `| ACTION |` lines already used,
e.g. `kit-telem-05-mergeguard.log`'s "advisor P5=3 doc/board findings fixed... advisor P6=8
additions surfaced". This rid does NOT require re-deriving from git state at convergence-gate
time (the per-sub-goal `$RID`/`$LANE` this Step's loop computes above are scoped to that
loop iteration, in whatever process/subagent ran that sub-goal, and are not guaranteed to
still be in scope once the loop finishes): it is already KNOWN and static, the same value
Step 4's own comment names ("or the sub-goal's own branch slug") -- the final sub-goal's
`**Branch:**` header value from its `goals/NN-<slug>.md` file, `type/` prefix stripped, the
exact transform `bash lib/gate/gate-ledger.sh rid` applies when run on that branch:

```
FINAL_RID="<final sub-goal's Branch: value, type/ prefix stripped -- from its goals/NN-<slug>.md>"
bash lib/gate/gate-ledger.sh record "$FINAL_RID" advisor ran "mode=P5 findings=<N> actor=$(git config user.name)" \
  || echo "WARNING: advisor gate-ledger emit failed (ledger dir unwritable?); convergence gate unaffected" >&2
bash lib/gate/gate-ledger.sh record "$FINAL_RID" advisor ran "mode=P6 findings=<N> actor=$(git config user.name)" \
  || echo "WARNING: advisor gate-ledger emit failed (ledger dir unwritable?); convergence gate unaffected" >&2
```

Observability only: a missing `advisor` row never blocks the merge or the close (no lane's
required-gate set gains an `advisor` entry; `mega-merge.sh gate`/`hooks/ship-gate.sh` are
unchanged). `<N>` is each mode's own finding/proposal count (`ADVISORY: <N findings>` /
`SUGGESTIONS: <N proposals>`), read the same way `commands/review-team.md` Step 2b's emit
already reads it -- see `agents/advisor.md` "Ledger visibility" for the one shared contract
both dispatch sites follow.

**Close the run visibly (mirrors the skill's close).** When the loop finishes (or
halts at a `gate!`), emit `<dir>/RUN_REPORT.md` -- ASCII gantt + per-sub-goal gate
matrix + the callable stack, markdown-only -- and render the timeline + totals in
chat. The report reads from the rid ledger (`lib/gate/gate-ledger.sh`) and the roadmap
checkboxes, never from transcripts.

## Consolidate mode (remega, mirrors the skill's mode)

A different input than the normal Step 1-5 flow: **2+ existing `.claude/goals/<slug>/`
scaffold dirs of the SAME project** whose decompositions overlap because they were
authored at different times with incomplete information. Given
`consolidate=<slugA>,<slugB>[,...]`, re-decompose their UNION into ONE new scaffold and
mark the old ones superseded -- operator-confirmed, never auto. This composes the
command's OWN existing beats (decompose, front-load-once, `## Touches` authoring,
spec-number reservation) over a union input; it invents no new scaffold shape and needs
no new binary or `lib/` file. Full depth + a worked dry-run: the skill's
`references/GUIDE.md` ("Consolidate mode (remega)") and
`references/consolidate-dry-run-sample.md`.

**The seven steps, at kit-native scoping:**

1. **Inventory** every candidate mega's `ROADMAP.md` + `goals/NN` files: status, `## Touches`,
   deps, `Done =`, `Merge policy`. A `- [x] ... -- PR #N` line imports untouched (never
   re-run, it is history); an in-flight sub-goal finishes under its OLD mega first; a queued
   one is the raw material the re-decompose actually re-plans.
2. **Overlap analysis**: pairwise `## Touches` intersection across the megas via
   `lib/gate/dispatch-gate.sh` -- the SAME disjointness checker Step 4's wave-eligibility already
   reuses, never a second checker -- plus a semantic pass for dedupe candidates (same outcome
   authored twice) and merge candidates (same-module sub-goals for related outcomes).
3. **Re-decompose the union**: write ONE new `ROADMAP.md` applying the dedupe + merge
   decisions, with the dependency graph re-derived from ACTUAL code/interface dependencies
   (not the old chains' authoring order), and `## Touches` re-sliced so each new sub-goal owns
   a disjoint module slice. This re-slicing is what CREATES wave parallelism: sub-goals that
   only chained because they were authored later, and that touch independent modules, now run
   as one parallel wave. Pull any file every sub-goal touches (a shared gate, a dispatcher, a
   VERBS map) into ONE owner sub-goal so the rest go parallel.
4. **Front-load clarifications ONCE**, over the whole union -- Step 2's beat, reused
   verbatim, just framed against the union rather than one mega.
5. **Spec-number block reserve + release.** Reserve via `bash lib/spec/spec-next.sh reserve`
   (SPEC-128's mkdir-mutex reservations ledger, the same mechanism the wavefront dispatch
   already uses at Step 4). This kit has no separate `release` verb: an unclaimed reservation
   self-expires on its own stale-reclaim TTL, so "release the old megas' unused numbers" is a
   no-op here, not a command to run -- the ledger prunes them without an operator step.
6. **Provenance per sub-goal.** Every consolidated sub-goal records `from: <mega-A>/SG-03 +
   <mega-B>/SG-01` on its roadmap line and in its goal file. Done imports keep their own
   single origin + PR.
7. **Supersede, never delete.** Old mega `ROADMAP.md` headers gain `superseded_by:
   <new-slug>`. This kit's nearest archive analog is the goal-draft lifecycle already in
   `WORKFLOW.md` ("Goal drafts (.claude/goals/)"): `lib/goal/goal-drafts.sh archive` moves a
   shipped single-goal draft to `.claude/goals/done/`. A superseded MEGA scaffold (a whole
   `<slug>/` dir, not one file) moves the same way in spirit, to `.claude/goals/done/<slug>/`
   -- mirroring that convention's intent rather than reusing the verb unchanged (it currently
   only walks single `.md` drafts). **Never write the markers or move anything without an
   explicit go from the human**: show the supersede plan first.

**When NOT to consolidate:** any old mega **>=80% done** (just finish it, import nothing);
**different merge postures or different tenants/repos** (a `full-auto` mega and a
`gate`-heavy mega, or two different repos, do not share a merge train); **under ~2 megas x 3
overlapping remaining sub-goals** (the re-planning session costs more than the overlap it
removes).

## What this refuses (mirrors `/kit:dispatch`'s "What this command refuses")

- **Merging a PR whose ship-gate has not passed.** `gate` is the only question
  `merge` asks before touching `gh`; there is no second override path inside
  `mega-merge.sh` -- the existing `lib/gate/gate-ledger.sh override <rid> <phase>
  <reason>` audit trail is still how a human clears a gate.
- **A DAG / wave scheduler.** Single chain only (SPEC-034 DEC-008); fan-in/fan-out
  is the GSD v2 handoff tripwire, rejected at Step 1.
- **The activator loop itself.** `/goal` / `ralph-loop` / `lib/queue/orchestrate.sh` own
  the turn-by-turn execution (ADR-0017 activator-agnostic); this command is
  planning plus the merge-enforcement affordance it hands the loop, not a new
  runtime.
- **Deploying or UAT-ing anything.** The deploy/UAT terminus (Step 1) PREPARES and
  OPENS, then STOPS for the human -- it never provisions, funds, or deploys.
- **Diverging from the skill's checkpoint semantics.** If the ops-toolkit skill is
  installed, this command's Steps 1-3 must produce the same front-load-once,
  same-defaults shape.
- **Auto-superseding a mega scaffold.** Consolidate mode always shows the supersede plan
  and waits for an explicit human go before writing a `superseded_by:` marker or moving
  anything.

Source: ADR-0028 P2/P3 (autonomous-loop hardening, "Where each layer lives" table);
SPEC-034 (mega-goal lane, ID-037 -- the roadmap conventions + single-chain gate
this command reuses); SPEC-095 / kit-hardening SG-07 (`lib/gate/proof-ledger.sh
deployable`, the terminus classifier reused here verbatim); SPEC-141 (ship-time lane
de-escalation, the `lib/classify/lane-classify.sh deescalate` verb mirrored explicitly at Step 5);
`lib/gate/gate-ledger.sh` (the required-gate set this rides on); ops-toolkit
`plan-for-mega-goal` SKILL.md (the authoring mirror source, incl. its tiny-item rule and
its Consolidate mode).
