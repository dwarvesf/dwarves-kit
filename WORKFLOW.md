# WORKFLOW.md: the cycle, the lanes, the gates

> Agent-facing contract. Read after CLAUDE.md. It names the lifecycle, routes
> work by risk, and points at the guardrail that enforces each boundary.
> It suggests and routes; it does not block. The only hard stops are the
> safety-gate hook, the push-to-main blocker, the anti-rationalization Stop
> hook, and the verification pipeline.

## Required reading (in order)
1. CLAUDE.md            - project context: stack, structure, rules
2. docs/specs/SPEC-NNN-<slug>.md - the active spec; the shared contract for the cycle
3. docs/architecture.md - how the pieces fit (reference; not required per task)

## Size the work first (risk-tiered intake)
Pick a lane before you start. Smaller work skips ceremony.

| Lane   | When | Path |
|--------|------|------|
| tiny   | typo, copy, comment, one obvious edit | edit, verify, done. No spec. |
| normal | one bounded feature or fix | /spec, /execute, /review, /ship |
| full   | touches auth, authz, hooks, data model, data loss, audit/security, an external provider, an API contract, a migration, or weakens validation | /think, /spec, /spec-validate, /execute, /review-team, /docs, /ship, /retro |
| bug    | a defect, regression, or failing test (not a new feature) | /debug (root cause before any fix), then /review |

When in doubt between two lanes, take the heavier one. Anything in the full-lane
trigger list uses the full lane unless you explicitly narrow the scope and say why.

## The cycle (phase, exit, enforcer)
| Phase    | Command | Exit when | Enforced by |
|----------|---------|-----------|-------------|
| Think    | /user:think | decision brief written (if BUILD) | advisory |
| Design (opt-in) | /user:design | solution agreed + appended to the brief | advisory |
| Design critique (opt-in) | /user:devs-team, /user:visual-team | critique appended to the brief or spec | advisory (normal/full) |
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
                          (the SPEC-005 contract), pick the lane, surface the draft body
                          for whatever goal-loop activator is present, hand off to the
                          lane's first command. Mutator; does NOT execute, never writes
                          last-goal.md.
  -> the lane runs        tiny | normal | full (see the cycle table above)
       normal/full -> /user:spec -> /user:spec-validate -> /user:execute (verify pipeline)
                      (opt-in: /user:devs-team + /user:visual-team before spec; /user:test-plan before execute)
                      -> /user:review -> /user:docs -> /user:ship -> /user:retro
  -> on ship              /user:ship reviews the completeness log; ID-NNN drops off the
                          queue (CHANGELOG is the canonical shipped record).
```

**Detector/mutator split.** `/user:start` and `/user:next` only read and render; `/user:assign` is the only mutator. **Activator-agnostic.** `/user:assign` writes only the `.claude/goals/<slug>.md` draft (ADR-0011) and surfaces its body; activation (starting the loop) is done by whatever primitive is present (the built-in `/goal`, the `ralph-loop` plugin, or the `goal-craft` skill). The kit NEVER writes `.claude/last-goal.md`; if no activator exists, the draft is a plain reusable file. **"Even the goal loop follows WORKFLOW"** is delivered honestly: the safety subset is hard-enforced by existing hooks (anti-rationalization, the verification pipeline, the push-to-main blocker); decision/doc completeness is warned + logged to `~/.claude/dwarves-kit/logs/completeness.log` and reviewed at `/user:ship` + `/user:retro`, not hard-blocked mid-loop (PHILOSOPHY rejects hard-gating process completeness). State model: SPEC-005. Full design: SPEC-006.

## Completion contract
A task is done only when its acceptance criteria are met and the verifier has
actually run the tests, not when you claim they pass. If you cannot run the
check, report that plainly; the anti-rationalization hook is the backstop for
premature completion. Self-reported "done" is not proof; the task-verifier is.

### Completeness clauses (warn + log, reviewed at ship)
Two self-check clauses run during Build/Reflect. Both WARN and LOG to `~/.claude/dwarves-kit/logs/completeness.log` (the `spec-drift-guard` logging shape); neither hard-blocks. `/user:ship` and `/user:retro` review that log at the gate. Hard blocks stay reserved for the safety subset (PHILOSOPHY rejects hard-gating process completeness).

- **Decision-translation.** Each decision in a spec's optional **Build decisions** sub-list (the decisions that imply implementation, tagged under a `### Build decisions` heading or a `Build:` prefix in the Decision Log) must be referenced by ID or `Implements:` target in a task or acceptance criterion; an orphan is warned + logged. Scope: ONLY the Build-decisions list. Rationale, rejected-alternative, and `(validation)`/`(reconciliation)` decisions are exempt. If a spec has no Build-decisions list, the clause is a no-op.
- **Doc-update.** The diff against the integration branch's merge-base (pinned, not a floating base) is checked against the doc-impact map below; a change that touches X without its companion docs is warned + logged. Normal/full lanes only (tiny-lane ship suppresses it).

#### Doc-impact map
Per change-type, the companion docs that must move with it. This covers the enumerated change-types; an unenumerated type is a logged gap (a warning), not a guarantee.

| If a change touches | Companion docs that must update |
|---|---|
| `hooks/*` | `RUNBOOK.md`, README hook table, `tests/test-meta.sh` count, `tests/test-hooks.sh`, the count surfaces (see below) |
| `commands/*` (new) | `MANUAL.md`, README command table, `.claude-plugin/plugin.json` + `marketplace.json`, `tests/test-meta.sh`, the count surfaces (see below) |
| `agents/*` | README agent list, `tests/test-meta.sh` frontmatter checks, the count surfaces (see below) |
| `settings.json` (hook wiring) | README hook table, `RUNBOOK.md`, `install.sh` merge logic |
| `install.sh` | README install steps, `tests/` |
| `rules/*` | README path-scoped-rules note, `docs/architecture.md` |
| `skills/*` | README, `MANUAL.md` |
| `examples/hello-spec/*` | `examples/hello-spec/README.md`, the downstream-template note |
| a PHILOSOPHY principle | `docs/PHILOSOPHY.md`, `commands/kit-health.md` reject-list |
| a new `docs/decisions/` ADR | README + `docs/architecture.md` cross-refs |
| a new `docs/specs/SPEC-NNN` | `_meta/BACKLOG.md` status, the spec's `Status:` header |
| **a new top-level dir under the kit root** | **this doc-impact map (WORKFLOW.md)**, README "Project structure", `docs/architecture.md` |
| any shipped change (normal/full) | `CHANGELOG.md`, `VERSION`, `.claude-plugin/plugin.json` + `marketplace.json` version, `tool.toml` version, `docs/retro/v<ver>.md` |

The bolded row is self-maintaining: adding a new top-level dir must update this map. Source: SPEC-006.

**Count + version surfaces.** Two values are duplicated across many files; the rows above point here so the sweep is enumerated, not "everywhere it appears". The component-count line (`N hooks + N commands + N agents + N skill`) lives in `CLAUDE.md`, `README.md`, `MANUAL.md` ("The N commands"), `docs/architecture.md` (component table), and `tool.toml` (description). The version string lives in `VERSION`, `.claude-plugin/plugin.json`, `docs/architecture.md` (component-table header), and `tool.toml`. Changing any count or the version means sweeping every file in the matching list; `marketplace.json` inherits the version via `"source": "."` and needs no bump. The SPEC-016 ship updated most count surfaces but missed `docs/architecture.md` and `tool.toml`; enumerating them here closes that gap.

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
render the queue + drafts read-only (SPEC-006). There is no separate `/user:goals`
list/switch command (SPEC-006 DEC-003, parked).
Full contract and rationale: ADR-0011.

## Artifact placement and concurrency (multi-spec)
The kit's concurrency model is **worktree-per-spec** (SPEC-010): many specs coexist
in `docs/specs/`, one is active per branch (SPEC-005 branch-aware detection), and
"multiple active specs at once" means N git worktrees, each one-active. The kit's
boundary stops at per-worktree detection + per-worktree state isolation; spawning,
scheduling, or merging the N worktrees is an external runtime, not the kit's job.

The placement rule that keeps this safe: **an artifact bound to a spec lives IN the
active spec; a pre-spec or per-diff artifact stays a working-tree file (isolated by
the worktree).** Lanes that produce a spec-bound result resolve "the active spec"
through the one shared SPEC-005 path (so a writer and a later reader never split
across two specs), and write into that spec, not a fixed-name root file. New lanes
must follow this: if your output binds to a spec, append it as a `## Section` in the
active spec (replace-not-stack), the way `/user:test-plan` and `/user:ui-design` do.
Two older lanes, `/user:devs-team` and `/user:visual-team`, predate this rule and
still prefer the brief (or inline output); aligning them to spec-first is a tracked
follow-up, noted in the table below.

| Artifact | Home | Scope | Why |
|---|---|---|---|
| `docs/specs/SPEC-NNN-<slug>.md` | committed, per-spec file | per-spec | the contract; unique name, no collision |
| `## Test plan` (SPEC-018) | in the active spec | per-spec | build input `/user:execute` reads from the spec it runs |
| `## Design critique` (`/user:devs-team`, SPEC-016) | the pre-spec brief if present, else the active spec | per-brief pre-spec, else per-spec | runs pre-spec, prefers the brief; predates the spec-first rule (follow-up to align) |
| `## UI design` + `## Visual critique` via `/user:ui-design` (SPEC-020) | active spec, else the pre-spec brief | per-spec when a spec exists | spec-first (DEC-008); spec-bound = multi-spec safe |
| `## Visual critique` via standalone `/user:visual-team` (SPEC-016) | the pre-spec brief if present, else inline-only | per-brief / transient | no spec-write path today; predates the rule (follow-up to align) |
| `docs/specs/DECISION-BRIEF.md` | working-tree file | one per worktree (pre-spec) | exists during `/think`+`/design` before a SPEC-NNN exists; `/spec` folds it into the spec's `## Solution`, after which the spec is the carrier |
| `REVIEW.md`, `TODOS.md` | working-tree files (gitignored) | per-diff, per worktree | transient `/review` output, regenerated each run; not spec-bound |
| kit logs, session-state | `~/.claude/dwarves-kit/...` | namespaced by worktree id | shared-path writes isolated per worktree (SPEC-010 TASK-5) |

The pre-spec brief is the one artifact that cannot be per-spec (no SPEC-NNN exists
yet); in that window concurrency relies on worktree isolation, and `/spec` folds the
brief into the spec so the spec becomes the carrier from then on. Same-directory
branch-switching is NOT a supported concurrency mode; use a worktree per spec.
Sources: SPEC-010 (worktree model + state namespacing), SPEC-016 DEC-011 +
SPEC-018 + SPEC-020 DEC-008 (the in-spec placement rule).
