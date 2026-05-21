# WORKFLOW.md: the cycle, the lanes, the gates

> Agent-facing contract. Read after CLAUDE.md. It names the lifecycle, routes
> work by risk, and points at the guardrail that enforces each boundary.
> It suggests and routes; it does not block. The only hard stops are the
> safety-gate hook, the push-to-main blocker, the anti-rationalization Stop
> hook, and the verification pipeline.
> For the visual flow/loop view (every flow + alt-flow, its trigger, and its
> stop condition, with ASCII diagrams), see `docs/ORCHESTRATION.md`.

## Required reading
`AGENTS.md` is the front door and owns the read-order; it is the single source.
Read `AGENTS.md` zone 1 ("Read in this order") for the full ordered list, then
return here. This file does not restate the list, so the two cannot drift.

## Size the work first (risk-tiered intake)
Pick a lane before you start. Smaller work skips ceremony.

| Lane   | When | Path |
|--------|------|------|
| tiny   | typo, copy, comment, one obvious edit | edit, verify, done. No spec. |
| normal | one bounded feature or fix | /spec, /execute, /review, /ship |
| full   | touches auth, authz, hooks, data model, data loss, audit/security, an external provider, an API contract, a migration, or weakens validation | /think, /spec, /spec-validate, /execute, /review-team, /docs, /ship, /retro |
| bug    | a defect, regression, or failing test (not a new feature) | /debug (root cause before any fix), then /review |
| backfill | brownfield: review an existing codebase and write the operating-layer docs (AGENTS.md / CLAUDE.md / specs) | review the code, write the docs. Doc-output only; no app-behavior change, no app-code edits. /spec optional. |

When in doubt between two lanes, take the heavier one. Anything in the full-lane
trigger list uses the full lane unless you explicitly narrow the scope and say why.

## The cycle (phase, exit, enforcer)
| Phase    | Command | Exit when | Enforced by |
|----------|---------|-----------|-------------|
| Think    | /user:think | decision brief written (if BUILD) | advisory |
| Design (opt-in) | /user:design | solution agreed + appended to the brief | advisory |
| Design critique (opt-in) | /user:devs-team, /user:visual-team | critique appended to the active spec (else the brief) | advisory (normal/full) |
| UI design (opt-in, downstream) | /user:ui-design | brief -> generate (frontend-design) -> critique -> revise | advisory (downstream only) |
| Spec     | /user:spec | spec exists, Status: DRAFT | spec-drift-guard hook |
| Validate | /user:spec-validate | Status: VALIDATED | advisory (full lane) |
| Test plan (opt-in) | /user:test-plan | `## Test plan` written into the spec | advisory (normal/full) |
| Build    | /user:execute or /user:next | tasks checked, verifier PASS | verification pipeline (worker, verifier, fix; max 2) |
| Review   | /user:review or /user:review-team | review verdict recorded | advisory |
| Docs     | /user:docs | README/CHANGELOG match code | advisory |
| Ship     | /user:ship | tagged + PR | ship gate (blocks on DO NOT SHIP), push-to-main blocker |
| Reflect  | /user:retro | docs/retro/v<version>.md written | advisory |
| Debug (off-cycle) | /user:debug | root cause recorded, fix verified, human-confirmed | iron law + guess-fix guard (anti-rationalization) |

Throughout: safety-gate blocks destructive Bash; anti-rationalization blocks
premature "done"; auto-format runs on edit; session-state-save and
post-compact-reinject protect long sessions. The Debug row is an off-cycle
entry point (a bug-lane loop), not a linear phase between Reflect and the next cycle.

## The spine
How a committed backlog item becomes shipped work, end to end:

```
session start
  -> /user:start          RENDER the BACKLOG Active queue (the "what's left?" list)
                          and list active .claude/goals/ drafts. Read-only; a detector.
  -> /user:assign ID-NNN  goal-crafter: break the item down, set objective + scope
                          fence + termination-on-blocker, write .claude/goals/<slug>.md
                          (the goal-draft contract), pick the lane, surface the draft body
                          for whatever goal-loop activator is present, hand off to the
                          lane's first command. Mutator; does NOT execute, never writes
                          last-goal.md.
  -> the lane runs        tiny | normal | full | bug | backfill (see the lane table above)
       normal/full -> /user:spec -> /user:spec-validate -> /user:execute (verify pipeline)
                      (opt-in: /user:devs-team + /user:visual-team before spec; /user:test-plan before execute;
                       /user:ui-design for downstream UI work, after /user:design)
                      -> /user:review -> /user:docs -> /user:ship -> /user:retro
       backfill    -> review the codebase, write AGENTS.md / CLAUDE.md / specs, then
                      /user:review (optional). No /user:execute; no app-code edits.
  -> on ship              /user:ship reviews the completeness log; ID-NNN drops off the
                          queue (CHANGELOG is the canonical shipped record).
```

**Freeform front door.** `/user:assign` accepts freeform intent, not only an `ID-NNN`. Given freeform, it delegates the interview to `/user:think`, pauses for approval, then allocates the ID + BACKLOG row before routing as usual; the ID-first path is unchanged. **Detector/mutator split.** `/user:start` and `/user:next` only read and render; `/user:assign` is the only mutator. **Activator-agnostic.** `/user:assign` writes only the `.claude/goals/<slug>.md` draft and surfaces its body; activation (starting the loop) is done by whatever primitive is present (the built-in `/goal`, the `ralph-loop` plugin, or the `goal-craft` skill). The kit NEVER writes `.claude/last-goal.md`; if no activator exists, the draft is a plain reusable file. **"Even the goal loop follows WORKFLOW"** is delivered honestly: the safety subset is hard-enforced by existing hooks (anti-rationalization, the verification pipeline, the push-to-main blocker); decision/doc completeness is warned + logged to `~/.claude/dwarves-kit/logs/completeness.log` and reviewed at `/user:ship` + `/user:retro`, not hard-blocked mid-loop (PHILOSOPHY rejects hard-gating process completeness).

## Mid-flight amend
Canonical rule. You are mid-`/user:execute` on a `VALIDATED` spec and the work
reveals scope that must be added now ("also do Y"). Amend the spec in place;
do not restart the lane and do not silently mutate it. Other docs
(PLAYBOOK, ORCHESTRATION, `commands/execute.md`) point here; they do not restate
this rule. The state-model row (`BUILDING -> SPECIFYING -> BUILDING`) lives in
`docs/operating-layer-vision.md` §3.3; this section carries the operational rule.

The amend is governed by four invariants:

- **No lane restart.** `Status:` stays `VALIDATED` across an amend; only the
  DELTA is (re-)validated (full lane: `/spec-validate` on the new tasks; normal
  lane: advisory). Dropping back to `DRAFT` would be a lane restart, the exact
  thing this path removes.
- **Completed work is frozen (add-only).** An amend may only ADD scope (new
  `- [ ]` tasks, new acceptance criteria, new after-state bullets). It must not
  rewrite an already-done (`- [x]`) task's contract; the `- [x]` rows are
  byte-for-byte unchanged. Rewriting a done task is the heavier re-open / re-spec
  path, not an amend.
- **Recorded at a checkpoint, operator-approved, not mid-worker.** The amend
  happens between tasks: the in-flight task is verified and committed first (or no
  task is in flight). Adding scope is an operator decision, never the loop's: an
  autonomous `/user:execute` pauses for the operator to approve the added scope
  before the amend lands (this is AGENTS.md zone 4 "Pause if", a scope / risk /
  architecture change). Then record it as an entry in the spec's `## Amendments`
  section (optional, on-demand; see `commands/spec.md`), one line per amend:
  `AMEND-NNN: date | what | why | at which checkpoint | new tasks | re-validated`.
- **Resume leads with `/user:next`, not a fresh `/user:execute`.** `/next` picks
  the next undone `- [ ]` task and skips `- [x]` done rows, so resume runs only
  the amended tasks. `/execute` re-parses and re-presents the whole plan, so it
  is the wrong door after an amend.

## Completion contract
The done-definition is canonical in `AGENTS.md` zone 3 ("Done means"); do not
restate it here. In the kit, the task-verifier is what proves "done" (self-reported
"done" is not proof), and the anti-rationalization hook is the backstop for
premature completion. The clauses below add kit-specific completeness checks on top
of that done-definition.

### Completeness clauses (warn + log, reviewed at ship)
Two self-check clauses run during Build/Reflect. Both WARN and LOG to `~/.claude/dwarves-kit/logs/completeness.log` (the `spec-drift-guard` logging shape); neither hard-blocks. `/user:ship` and `/user:retro` review that log at the gate. Hard blocks stay reserved for the safety subset (PHILOSOPHY rejects hard-gating process completeness).

- **Decision-translation.** Each decision in a spec's optional **Build decisions** sub-list (the decisions that imply implementation, tagged under a `### Build decisions` heading or a `Build:` prefix in the Decision Log) must be referenced by ID or `Implements:` target in a task or acceptance criterion; an orphan is warned + logged. Scope: ONLY the Build-decisions list. Rationale, rejected-alternative, and `(validation)`/`(reconciliation)` decisions are exempt. If a spec has no Build-decisions list, the clause is a no-op.
- **Doc-update.** The diff against the integration branch's merge-base (pinned, not a floating base) is checked against the doc-impact map below; a change that touches X without its companion docs is warned + logged. Normal/full lanes only (tiny-lane ship suppresses it).

#### Doc-impact map
Per change-type, the companion docs that must move with it. This covers the enumerated change-types; an unenumerated type is a logged gap (a warning), not a guarantee.

| If a change touches | Companion docs that must update |
|---|---|
| `hooks/*` | `RUNBOOK.md`, README hook table, `tests/test-hooks.sh`, `tests/test-meta.sh` |
| `commands/*` (new) | `MANUAL.md`, README command table, `.claude-plugin/plugin.json` + `marketplace.json`, `tests/test-meta.sh` |
| `agents/*` | README agent list, `tests/test-meta.sh` frontmatter checks |
| `settings.json` (hook wiring) | README hook table, `RUNBOOK.md`, `install.sh` merge logic |
| `install.sh` | README install steps, `tests/` |
| `rules/*` | README path-scoped-rules note, `docs/architecture.md` |
| `skills/*` | README, `MANUAL.md` |
| `examples/hello-spec/*` | `examples/hello-spec/README.md`, the downstream-template note |
| a PHILOSOPHY principle | `docs/PHILOSOPHY.md`, `commands/kit-health.md` reject-list |
| a new `docs/decisions/` ADR | README + `docs/architecture.md` cross-refs |
| a new `docs/specs/SPEC-NNN` | `_meta/BACKLOG.md` status, the spec's `Status:` header |
| **a new top-level dir under the kit root** | **this doc-impact map (WORKFLOW.md)**, README "Project structure", `docs/architecture.md` |
| **a new top-level file under the kit root** | **this doc-impact map (WORKFLOW.md)**, README "Project structure", `docs/architecture.md` |
| `AGENTS.md` (kit root) | `CLAUDE.md` + `WORKFLOW.md` pointers (must not drift), `examples/hello-spec/AGENTS.md` (downstream template), `commands/assign.md` (the six-section projection reads its zones), `tests/test-meta.sh` |
| any shipped change (normal/full) | `CHANGELOG.md`, `VERSION`, `.claude-plugin/plugin.json` version, `tool.toml` version, `docs/retro/v<ver>.md` |

The bolded rows are self-maintaining: adding a new top-level dir or file must update this map.

The `backfill` lane (see the lane table) produces operating-layer docs rather than touching a source path: a backfill run writes `AGENTS.md`, `CLAUDE.md`, and any specs for the reviewed codebase, so its companion docs are those it writes.

**Version surfaces.** The version string is duplicated and must stay in sync: it lives in `VERSION` (the source of truth), `.claude-plugin/plugin.json`, and `tool.toml`. Bumping the version means updating those; `marketplace.json` inherits it via `"source": "."` and needs no bump. The kit does NOT keep component counts (`N hooks`, `N commands`, etc.) in prose: describe the component set qualitatively, never as a hand-maintained number that silently rots.

## What this contract does NOT do
It does not lock phases. An experienced operator may skip /spec-validate on a
normal-lane change or go straight to /next. The kit detects state
(context-readiness hook) and suggests the next step; it never blocks
progression. Hard stops are reserved for irreversible cost: destructive
commands, push-to-main, premature completion, failed verification.

## Goal drafts (.claude/goals/)
The kit keeps candidate goal drafts in `.claude/goals/<slug>.md` (gitignored,
per-machine) beside the built-in `/goal`'s single active slot
`.claude/last-goal.md`. The kit writes the drafts plus a derived `INDEX.md`; it
NEVER writes `last-goal.md`. Activating a draft means handing its body to
whatever goal-loop activator is present (the built-in `/goal`, the `ralph-loop`
plugin, or the `goal-craft` skill); if none is installed, the drafts still work
as plain reusable files. Brainstorm many drafts, one is active at a time; each
carries a `target_spec`/`id`. Picking a draft and routing it into a lane is `/user:assign`; `/user:start`/`/user:next`
render the queue + drafts read-only. There is no separate `/user:goals`
list/switch command (parked).

## Artifact placement and concurrency (multi-spec)
The kit's concurrency model is **worktree-per-spec**: many specs coexist
in `docs/specs/`, one is active per branch (branch-aware detection), and
"multiple active specs at once" means N git worktrees, each one-active. The kit's
boundary stops at per-worktree detection + per-worktree state isolation; spawning,
scheduling, or merging the N worktrees is an external runtime, not the kit's job.

The placement rule that keeps this safe: **an artifact bound to a spec lives IN the
active spec; a pre-spec or per-diff artifact stays a working-tree file (isolated by
the worktree).** Lanes that produce a spec-bound result resolve "the active spec"
through the one shared active-spec path (so a writer and a later reader never split
across two specs), and write into that spec, not a fixed-name root file. New lanes
must follow this: if your output binds to a spec, append it as a `## Section` in the
active spec (replace-not-stack), the way all four critique/plan lanes do
(`/user:test-plan`, `/user:devs-team`, `/user:visual-team`, `/user:ui-design`).
The shared invariant is the spec-first head; `/user:visual-team` adds an inline
fallback because it alone can run with neither a spec nor a brief.

| Artifact | Home | Scope | Why |
|---|---|---|---|
| `docs/specs/SPEC-NNN-<slug>.md` | committed, per-spec file | per-spec | the contract; unique name, no collision |
| `## Test plan` | in the active spec | per-spec | build input `/user:execute` reads from the spec it runs |
| `## Design critique` (`/user:devs-team`) | active spec, else the pre-spec brief | spec-first | binds to the design it critiques |
| `## UI design` + `## Visual critique` (`/user:ui-design`; `/user:visual-team`) | active spec, else the pre-spec brief (visual-team: else inline-only) | spec-first | both write `## Visual critique` to the same heading + location; replace-not-stack dedups |
| `docs/specs/DECISION-BRIEF.md` | working-tree file | one per worktree (pre-spec) | exists during `/think`+`/design` before a SPEC-NNN exists; `/spec` folds it into the spec's `## Solution`, after which the spec is the carrier |
| `REVIEW.md`, `TODOS.md` | working-tree files (gitignored) | per-diff, per worktree | transient `/review` output, regenerated each run; not spec-bound |
| kit logs, session-state | `~/.claude/dwarves-kit/...` | namespaced by worktree id | shared-path writes isolated per worktree |

The pre-spec brief is the one artifact that cannot be per-spec (no SPEC-NNN exists
yet); in that window concurrency relies on worktree isolation, and `/spec` folds the
brief into the spec so the spec becomes the carrier from then on. Same-directory
branch-switching is NOT a supported concurrency mode; use a worktree per spec.

Design provenance for every rule in this contract lives in `docs/specs/` and
`docs/decisions/`: the spec files and ADRs carry the rationale and history. This
contract states the rules; it does not cite the spec IDs that decided them.
