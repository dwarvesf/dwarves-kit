---
description: "Turn a backlog item (ID-NNN) into a scoped goal draft and route it into the right WORKFLOW lane. Writes .claude/goals/, never executes."
---

Self-intro (AGENTS.md "Self-intro" convention): open your first reply with exactly one banner line, `[kit:assign] Turn a backlog item into a scoped goal draft and route it into the right lane.`, then proceed.

You are a goal dispatcher. Turn a committed backlog item into a runnable goal draft and hand it to the right lane. You do NOT implement anything; you set up the goal and route.

## Process

### Step 1: Resolve the argument (two shapes)

`$ARGUMENTS` is one of two shapes. Trim it, then branch:

- **ID shape**: the trimmed argument matches `^ID-[0-9]+$`. Take the **ID-first path** below (Step 1b onward), unchanged. This is the path that has always existed.
- **Freeform shape**: anything else (intent text like "apply SDD to X" or a vague brief). Take the **freeform path** in Step 1a, which crystallizes the intent into an ID + BACKLOG row first, then rejoins the ID-first tail at Step 4.

A future third intake shape (e.g. an imported issue) is another branch of this same resolver, not a new command. The resolver is the only place that decides ID vs freeform; everything downstream is shared.

### Step 1a: Freeform path (delegate, gate, sanitize, allocate, write)

When the argument is freeform intent (does NOT match `^ID-[0-9]+$`), run these ordered steps. `/assign` stays a light mutator-dispatcher (SPEC-006): it does NOT run a multi-turn interview itself. Two invariants govern this path, and both come before any file is written:

- **approve-before-allocate**: pause for human approval of the crystallized objective BEFORE allocating an ID. A vague brief never auto-creates a row (DEC-002).
- **row-before-draft**: write the BACKLOG Active-queue row before the goal draft, so ID traceability exists first (the row before draft order is the invariant; never write a `.claude/goals/` draft for an un-rowed intent).

1. **Delegate crystallize to `/kit:think`.** Hand the freeform intent to `/kit:think` (the 6-forcing-questions idea challenger). It runs the interview and returns a crystallized objective + a lane. `/assign` does NOT embed that interview (DEC-003); it only consumes `/think`'s result. If the intent is too vague to name an outcome, `/think` loops; do not allocate anything until it converges.
2. **Approval gate (approve-before-allocate).** Present the crystallized objective and pause for explicit human approval. Until the human approves, allocate nothing and write nothing. This is the gate that keeps half-baked rows out of the queue.
3. **Dedup by slug.** Derive the slug from the approved objective (per the sanitize rule in Step 1a.4). If a `.claude/goals/<slug>.md` draft or a BACKLOG row with that slug already exists, surface it instead of allocating a second ID (filesystem-is-truth idempotency, SPEC-005). On a near-match slug, ask rather than silently merge or duplicate.
4. **Sanitize (DEC-004).** Before the freeform text touches any file, sanitize it:
   - **Table cells**: escape `|` (write it as `\|`) and replace newlines with spaces in every BACKLOG row cell, so a freeform string cannot break the `_meta/BACKLOG.md` pipe table.
   - **Slug**: reduce the derived slug to `[a-z0-9-]+` only. Lowercase, replace spaces with `-`, then strip `/`, `..`, and anything outside `[a-z0-9-]`, so the slug cannot traverse out of `.claude/goals/`. The kebab convention is unchanged; it is just hardened to `[a-z0-9-]+`.
5. **Atomic allocate + write the row (DEC-005, row-before-draft).** Allocate the next `ID-NNN` by **re-reading the current max ID** in `_meta/BACKLOG.md` Active queue **in the same step that writes the row** (do not cache a max read earlier). The new ID is `max + 1`, zero-padded. Append a sanitized Active-queue row with `Status: queued` and `Source: freeform intake (<YYYY-MM-DD>)`, filling Title / Target artifact / Lane from the crystallized objective + `/think`'s lane. After writing, **re-read the queue and check no two rows share the new ID**; if a collision exists (a concurrent allocation picked the same `max + 1`), **fail loud** and tell the operator to re-run, rather than leaving two rows with one ID. This mirrors the existing SPEC/ADR dup-number guard.
6. **Rejoin the ID-first tail.** With the row written and the ID allocated, proceed exactly as for an `ID-NNN`: Step 4 (draft write), Step 5 (lane + activator), Step 6 (status + hand-off). The freeform path adds no new tail; it reuses the ID path's.

### Step 1b: Resolve the item (ID-first path)

Read `$ARGUMENTS` for the `ID-NNN`. Find that row in the `_meta/BACKLOG.md` Active queue (the Schema section there defines the columns). If the id is absent, say so, list the open queue ids, and stop. (An argument that looks like an ID but is not in the queue is a typo'd ID, not a freeform intent: report "unknown id", do NOT silently create a freeform row from it.)

### Step 2: Idempotency check

If a `.claude/goals/<slug>.md` already exists for this id (one draft per id), re-surface the existing draft instead of creating a duplicate, and skip to Step 5. Mirrors SPEC-005 edge 6: the filesystem is the source of truth.

### Step 3: Project the six-section operating directive

From the item's Title + Target artifact, craft the goal as a **six-section operating directive**, not a one-line contract. Each section *projects* from an `AGENTS.md` zone or a section of the active spec; this is the projection contract, and it must match `AGENTS.md`'s "How a goal is composed" table (keep the two in sync, or the `AGENTS.md`↔`assign.md` drift failure-mode fires). The mapping is a composition, not 1:1: two of the six sections come from the active spec, not from `AGENTS.md`.

1. **Context-to-read** <- `AGENTS.md` zone 1 ("Read in this order"). Carry the ordered read list (AGENTS.md, CLAUDE.md, the active `docs/specs/SPEC-NNN-<slug>.md`, then reference docs) so the loop orients before touching anything.
2. **Constraints** <- the `AGENTS.md` / `CLAUDE.md` rules plus the item's scope fence: the files/dirs in play and an explicit `Not:` list of adjacent things to leave alone. This is where the old scope fence lives now.
3. **Operating rules** <- `AGENTS.md` zone 2 ("Task loop"): size the lane, read the spec + its AC, implement the smallest verifiable increment, verify, commit (one logical change, no spec/ticket IDs in the subject).
4. **Validation loop** <- the active spec's `## Verification`. If the Target artifact is a SPEC, point the goal at that doc's `## Verification` (a pointer-`/goal`); otherwise name the real check command. Do not write "tests pass"; name the command.
5. **Done-when** <- `AGENTS.md` zone 3 ("Done means") + the active spec's `## After state` (the observable bullets). The goal is done only when its AC are met, the check actually ran, review is recorded + a report written, and the final response says what changed and what was not attempted. Quote the spec's `## After state` observable bullets here verbatim as the done-picture. If the spec lacks an `## After state` section, fall back to `AGENTS.md` "Done means" alone.
6. **Pause-if** <- `AGENTS.md` zone 4 ("Pause if"): stop and ask a human (with a named blocker note, no churn) on architecture direction, source-of-truth hierarchy, validation removal, risk-classification change, or privacy/security. This is where the old termination-on-blocker lives now.

If the repo is spec-driven and the lane is normal/full, the directive is **spec-first**: its opening move is the lane's first command (`/kit:spec`), not building code. This matches the `goal-craft` skill's spec-driven-repo rule.

### Step 4: Write the draft (the SPEC-005 contract / ADR-0011)

Create `.claude/goals/<slug>.md` with pinned frontmatter and the goal body:

```
---
slug: <kebab-derived-from-title>
id: ID-NNN
target_spec: <SPEC-NNN, or "(none)">
status: drafted
created: <YYYY-MM-DD>
---
<the six-section operating directive from Step 3 (Context-to-read / Constraints / Operating rules / Validation loop / Done-when / Pause-if), ready to paste into an activator>
```

`.claude/` is gitignored (per-machine drafts). The filesystem (`ls .claude/goals/*.md`) is the sole source of truth; there is no derived cache (ADR-0023). A draft is retired (moved to `.claude/goals/done/`, never deleted) once its `target_spec` ships, via `lib/goal/goal-drafts.sh archive` at `/kit:ship`. Do NOT write `.claude/last-goal.md`: the built-in `/goal` owns that slot (ADR-0011).

### Step 5: Pick the lane + detect the activator

- **Pull mode (`--next`)**: invoked as `/kit:assign --next` (no ID), pull the board's top item instead of being handed one: `bash lib/board/backlog.sh next` prints the first `queued` row (file order is the priority order); claim it in the cross-session registry (Step 5b) and flip the board state `bash lib/board/backlog.sh set <ID> claimed`, then continue exactly as if that ID had been named. No daemon, no auto-trigger: a pull is one explicit invocation (PHILOSOPHY §6 N2); operator-named `/kit:assign ID-NNN` is unchanged.

- **Type first**: classify the work KIND before sizing it:

  ```bash
  bash lib/classify/task-type-classify.sh classify "<the item title / crystallized objective>"
  ```

  `spec-feature` continues below (pick a lane). Any other type (research / eval / review / doc /
  migration / data-tool) runs its TYPE LOOP instead of the code cycle: the goal draft names the
  loop's phases (WORKFLOW.md `## Type loops`), the executor (the registry's `agent` column in
  `docs/verification/task-types.md`), and the proof artifact it owes (same registry;
  `bash lib/gate/proof-gate.sh contract "<title>"` prints the composed contract). Lanes still apply
  to the RISK of any code the loop touches; the loop supplies the cycle.

  **Grill before you define done.** Run `/kit:grill` (or drive its bank inline): type-shaped
  questions, one at a time with recommended answers, until the task is understood; the Q&A
  digest lands in the draft's Context and resolved terms/decisions land in the glossary/ADRs
  as they resolve. Tiny lane exempt.

  **Every goal draft carries a `Done =` line (PHILOSOPHY §6 N3), whatever the type.** Derive it
  from the proof contract (`bash lib/gate/proof-gate.sh contract "<title>"`) plus the type's
  test-design dialect (test-design-standard §5b): one boolean the completion audit can compare
  evidence against. A draft without a `Done =` line is not assignable; defining done is phase 0
  of every loop, before any work runs (the V-model right arm, type-agnostic).

- **Lane**: read the item's Lane column (`tiny` / `normal` / `full` / `bug` / `backfill`); it selects the WORKFLOW path. If the column is blank, or you want a check, auto-classify from the title:

  ```bash
  bash lib/classify/lane-classify.sh classify "<the item title / crystallized objective>"
  ```

  It applies the WORKFLOW.md "Size the work first" triggers deterministically (precedence: backfill, tiny, full, bug, normal; "when in doubt, heavier"). Use its output as the suggested lane and write it into the BACKLOG row. This SUGGESTS, it does not dictate: if you disagree, override and say why (a heavier lane is always safe). The same classifier seeds the lane for each spec `/kit:dispatch` fans out.

- **Precedent lookup (SPEC-068).** Before sizing, ask the repo what it already knows:
  `bash lib/precedent.sh find "<the item title>"`. Surface the top matches in the goal
  draft's Context (prior specs/retros/runs shape the Done= and prevent re-derivation);
  no matches is itself information (genuinely new ground).

- **Floor check (advisory).** Once the lane is committed (from the column, or your override, or the classifier), run the floor check so an under-sized choice cannot pass silently:

  ```bash
  bash lib/classify/lane-classify.sh check "<the chosen lane>" "<the item title / crystallized objective>"
  ```

  If it prints `LANE-DOWNGRADE`, the task text matches a heavier lane than you chose: size up, or state the explicit narrowing reason (per WORKFLOW "anything on the full-trigger list uses full unless you narrow the scope and say why"). It is advisory (exit 0, logged to `completeness.log`, reviewed at `/kit:ship`), never a block ("Detect, don't dictate"). Silence means the choice is at or above the floor. This is the guard for the classify-then-route gap (SPEC-053): the classifier suggested, but nothing caught an under-sized choice until now.

- **Record the routing facts (SPEC-061).** One line, right after the lane is committed, so lane telemetry has the chosen-vs-classified pair to aggregate:

  ```bash
  git switch -c <type>/<slug>              # the work branch MUST exist first (SPEC-070)
  RID=$(bash lib/gate/gate-ledger.sh rid)       # canonical run id = branch slug
  bash lib/gate/gate-ledger.sh start "$RID" "<chosen lane>" "<classifier's suggested lane>" "<chosen work type>" "<classifier's suggested type>"
  ```

  Mis-recorded the lane or type? Correct it with `bash lib/gate/gate-ledger.sh start --amend "$RID" "<correct lane>" ...` , a sanctioned START-AMEND every reader takes as canonical (last amend wins; SPEC-077); an honest fix never reads as a MULTI-START misfire.

  The repo is auto-detected. `lib/telemetry/lane-telemetry.sh report|misfires` reads these at `/kit:retro`; a run without a START line surfaces as untracked (itself a signal).

- **Show the road (SPEC-063).** Print the checklist the run will walk so the operator sees
  the steps up front: `bash lib/gate/gate-ledger.sh plan "<chosen lane>"`. From here on, each
  phase entry prints `bash lib/gate/gate-ledger.sh progress "<rid>" "<chosen lane>"` (the
  `step k/n` line; AGENTS.md Task loop carries the standing rule).
- **Activator**: detect what can run the loop, in order: the built-in `/goal` (if present), the `ralph-loop` plugin, or the `goal-craft` skill. Surface the draft body for whichever is available. If none is installed, say so and leave the draft as a plain reusable file (paste the body wherever). Never assume a specific activator exists.

### Step 5b: Claim the goal in the cross-session registry (multi-session safety)

If the operator may run other Claude sessions on this repo at the same time, claim the
goal so two sessions never pick colliding file-sets (ADR-0022, SPEC-036). Use the slug,
the lane from Step 5, and the goal's declared write-set (the target spec's `## Touches`
globs if it has them, else the scope-fence dirs from the Constraints section, as `dir/**`
prefix globs):

```bash
bash lib/goal/goal-registry.sh claim <slug> <lane> <glob>...
```

- **CLAIMED** -> registered as one single-writer file under `.git/kit-goals/`; proceed to
  hand-off. The goal now shows in `/kit:start`'s running-goals monitor.
- **REFUSED: overlaps running goal '<other>'** -> another active session already owns an
  overlapping file-set. Do NOT route this goal now; tell the operator to serialize (finish
  and `release` the other goal first) or repick a disjoint goal. This is the cross-session
  twin of the `/kit:dispatch` disjointness gate, reusing the same rule (`lib/gate/dispatch-gate.sh`).

This is advisory, not a hard gate (Detect, don't dictate): a single-session operator can
ignore a stale entry and clear it with `bash lib/goal/goal-registry.sh release <slug>`. On goal
completion, the loop releases its claim (`release <slug>`).

**Attempt-log convention.** Add one line to the directive's Operating rules so the loop
leaves a human-legible trail of what it tried: after each attempt/iteration, run
`bash lib/goal/goal-registry.sh log <slug> "<one line of what was tried>"`. A human monitoring
the registry then sees not just who is running but what each goal has attempted.

### Step 6: Update status + hand off

- Set the item's `Status` in `_meta/BACKLOG.md`: `queued -> speccing` (normal/full, a spec comes next) or `-> executing` (tiny).
- Hand off to the lane's first command:
  - tiny: "edit, verify, done" (no spec).
  - normal/full: `/kit:spec` (or `/kit:think` first if the item is still fuzzy).
- State what you wrote and what to run next. Do NOT run it.

## Edge cases

- **Unknown id**: list the open queue ids, stop.
- **tiny lane**: craft the draft but route to "edit, verify, done"; no `/spec`.
- **Re-run for the same id**: re-surface the existing draft; do not duplicate or double-advance status (idempotent).
- **No activator installed**: the draft still works as a plain file; only one-step activation is lost.
- **Queued item with no spec, normal/full lane**: hand off to `/kit:spec` first.
- **Freeform intent too vague**: `/kit:think` loops until the objective is named; no ID is allocated until the approval gate passes (no half-baked rows).
- **Duplicate freeform intent**: dedup by slug after crystallize; surface the existing row/draft instead of allocating a second ID, and ask on a near-match rather than silently merge.
- **Concurrent freeform allocation**: both sessions re-read max in the write step; the post-write equal-ID collision check fails loud and the operator re-runs.
- **`|` or newline in freeform intent**: sanitized (cells escape `|`, newlines become spaces) before the row is written, so the BACKLOG pipe table stays well-formed.

## What this command does NOT do

It does not execute the task, does not write `.claude/last-goal.md`, and does not hard-gate. On the freeform path it does NOT embed a multi-turn interview either: the crystallize step is delegated to `/kit:think`, and `/assign` keeps only allocate + route (DEC-003). It is the mutator that sets up a goal; the lane's commands do the work and `/kit:start`/`/kit:next` only render. Source: SPEC-006; SPEC-026 (the freeform front door + its four invariants: row-before-draft, approve-before-allocate, sanitize, atomic-allocate); dispatcher pattern from `commands/next.md` + CCGS `/start`; goal breakdown from the `goal-craft` skill; draft store from ADR-0011.
