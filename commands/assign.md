---
description: "Turn a backlog item (ID-NNN) into a scoped goal draft and route it into the right WORKFLOW lane. Writes .claude/goals/, never executes."
---

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

1. **Delegate crystallize to `/user:think`.** Hand the freeform intent to `/user:think` (the existing idea-griller). It runs the interview and returns a crystallized objective + a lane. `/assign` does NOT embed that interview (DEC-003); it only consumes `/think`'s result. If the intent is too vague to name an outcome, `/think` loops; do not allocate anything until it converges.
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

If the repo is spec-driven and the lane is normal/full, the directive is **spec-first**: its opening move is the lane's first command (`/user:spec`), not building code. This matches the `goal-craft` skill's spec-driven-repo rule.

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

`.claude/` is gitignored (per-machine drafts). The filesystem (`ls .claude/goals/*.md`) is authoritative; if a `.claude/goals/INDEX.md` cache exists, rebuild its row from the files. Do NOT write `.claude/last-goal.md`: the built-in `/goal` owns that slot (ADR-0011).

### Step 5: Pick the lane + detect the activator

- **Lane**: read the item's Lane column (`tiny` / `normal` / `full`); it selects the WORKFLOW path.
- **Activator**: detect what can run the loop, in order: the built-in `/goal` (if present), the `ralph-loop` plugin, or the `goal-craft` skill. Surface the draft body for whichever is available. If none is installed, say so and leave the draft as a plain reusable file (paste the body wherever). Never assume a specific activator exists.

### Step 6: Update status + hand off

- Set the item's `Status` in `_meta/BACKLOG.md`: `queued -> speccing` (normal/full, a spec comes next) or `-> executing` (tiny).
- Hand off to the lane's first command:
  - tiny: "edit, verify, done" (no spec).
  - normal/full: `/user:spec` (or `/user:think` first if the item is still fuzzy).
- State what you wrote and what to run next. Do NOT run it.

## Edge cases

- **Unknown id**: list the open queue ids, stop.
- **tiny lane**: craft the draft but route to "edit, verify, done"; no `/spec`.
- **Re-run for the same id**: re-surface the existing draft; do not duplicate or double-advance status (idempotent).
- **No activator installed**: the draft still works as a plain file; only one-step activation is lost.
- **Queued item with no spec, normal/full lane**: hand off to `/user:spec` first.
- **Freeform intent too vague**: `/user:think` loops until the objective is named; no ID is allocated until the approval gate passes (no half-baked rows).
- **Duplicate freeform intent**: dedup by slug after crystallize; surface the existing row/draft instead of allocating a second ID, and ask on a near-match rather than silently merge.
- **Concurrent freeform allocation**: both sessions re-read max in the write step; the post-write equal-ID collision check fails loud and the operator re-runs.
- **`|` or newline in freeform intent**: sanitized (cells escape `|`, newlines become spaces) before the row is written, so the BACKLOG pipe table stays well-formed.

## What this command does NOT do

It does not execute the task, does not write `.claude/last-goal.md`, and does not hard-gate. On the freeform path it does NOT embed a multi-turn interview either: the crystallize step is delegated to `/user:think`, and `/assign` keeps only allocate + route (DEC-003). It is the mutator that sets up a goal; the lane's commands do the work and `/user:start`/`/user:next` only render. Source: SPEC-006; SPEC-026 (the freeform front door + its four invariants: row-before-draft, approve-before-allocate, sanitize, atomic-allocate); dispatcher pattern from `commands/next.md` + CCGS `/start`; goal breakdown from the `goal-craft` skill; draft store from ADR-0011.
