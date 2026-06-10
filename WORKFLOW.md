# WORKFLOW.md: the cycle, the lanes, the gates

> Agent-facing contract. Read after CLAUDE.md. It names the lifecycle, routes
> work by risk, and points at the guardrail that enforces each boundary.
> It suggests and routes; it does not block. The only hard stops are the
> safety-gate hook, the push-to-main blocker, the anti-rationalization Stop
> hook, and the verification pipeline.
> The visual flow/loop view (every flow + alt-flow, its trigger, and its
> stop condition, with ASCII diagrams) is the `## Flow and loop reference`
> section at the end of this file.

## Required reading
`AGENTS.md` is the front door and owns the read-order; it is the single source.
Read `AGENTS.md` zone 1 ("Read in this order") for the full ordered list, then
return here. This file does not restate the list, so the two cannot drift.

## Where work comes from (the board)

`_meta/BACKLOG.md` is the kanban board (SPEC-055): one row per work item, the Status column is
the state machine (`queued -> claimed -> speccing -> validated -> executing -> shipped`, plus
`parked` / `dropped`). Render it with `bash lib/backlog.sh board`; flip states mechanically with
`backlog.sh set <ID> <state>` (the leading keyword changes, the row's annotation prose
survives). Work arrives two ways, and they coexist: an operator names an item
(`/kit:assign ID-NNN`), or a session pulls the top queued item (`/kit:assign --next` =
`backlog.sh next` -> goal-registry claim -> flip to `claimed`). No daemon, no parallel task
database: the markdown file is the one source of truth.

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

`/kit:assign` backs this tree with an **advisory floor check** (`lib/lane-classify.sh
check`): once a lane is chosen, it re-classifies the task text and warns + logs (to
`completeness.log`, reviewed at `/kit:ship`) when the choice is lighter than the
deterministic floor, so an under-sized `full`/`bug` task does not slip through silently.
It warns; it never blocks (Detect, don't dictate). Over-sizing is always silent (safe).

## Type loops (the non-code cycles)

Lanes size CODE work. The classifier's other five types each get their own right-sized cycle
(PHILOSOPHY §6 N1). Same intake either way: `lib/task-type-classify.sh` names the type; code work
picks a lane above, everything else runs its type's loop below. Chat stays chat, a loop engages
when a task is being executed, not on every message. The executor per type (preassigned or
dynamic) lives in the registry (`docs/verification/task-types.md`, `agent` column); the proof
artifact and rigor live there too.

**Phase 0 is universal (PHILOSOPHY §6 N3): every loop starts with the grill, then the done
scenario.** First `/kit:grill`, the type-shaped intake interview (one question at a time,
recommended answers, write-as-you-go; tiny exempt). Then define the done scenario,
the proof contract (`bash lib/proof-gate.sh contract "<task>"`) plus the test design in the
type's dialect (test-design-standard §5b), BEFORE any phase below runs. What follows is what
gets compared against that definition when the work claims done (the V-model right arm,
type-agnostic).

| Type | Loop (entry -> phases -> exit) |
|------|-------------------------------|
| research | frame the question -> multi-modal sweep (parallel angles) -> adversarially verify every load-bearing claim -> cited report |
| eval | frame + define metrics -> hand-verify seed data -> climb the test ladder (smoke -> live) -> TEST-REPORT with falsifiability controls -> verdict |
| doc | diff sweep (what changed) -> update every affected doc -> doc-verifier confirms docs match code |
| migration | inventory the estate -> dry-run on a copy -> staged apply -> verify + record the run -> rollback path proven |
| data-tool | spec/port the surface -> build -> recorded live run + negative control -> Done gate (proof-of-done indexes the run ledgers) |
| incident | alert/symptom -> triage (witr/logs) -> root-cause BEFORE any fix (/kit:debug discipline) -> fix/mitigate -> INC-NNN record -> monitoring follow-up |
| reconcile | inventory the estate -> classify conform/drift -> migrate/fix -> reference-fix -> gate check |
| operate | trigger (schedule/operator) -> pre-checks -> run the procedure -> record the run -> alert on deviation |
| planning | gather state (board + PRs + calendar) -> prioritize -> enqueue/re-rank board rows -> digest |
| learning | ingest material -> explain/companion -> practice -> self-check >= the track's bar |
| spec-feature | (code) pick a lane in "Size the work first" above |

A loop is right-sized or it is wrong: a research loop that feels like ceremony for a research
task is a defect, not rigor. Tool comparisons are evals; test-design passes ride the owning
work item's test-plan phase; cleanup/drift sweeps are the reconcile loop; deployments ride
migration (same dry-run + rollback shape); agent-org config rides spec-feature lanes.

## The cycle (phase, exit, enforcer)
| Phase    | Command | Exit when | Enforced by |
|----------|---------|-----------|-------------|
| Think    | /kit:think | decision brief written (if BUILD) | advisory |
| Design (opt-in) | /kit:design | solution agreed + appended to the brief | advisory |
| Design critique (opt-in) | /kit:devs-team, /kit:visual-team | critique appended to the active spec (else the brief) | advisory (normal/full) |
| UI design (opt-in, downstream) | /kit:ui-design | brief -> generate (frontend-design) -> critique -> revise | advisory (downstream only) |
| Spec     | /kit:spec | spec exists, Status: DRAFT | spec-drift-guard hook |
| Validate | /kit:spec-validate | Status: VALIDATED | advisory (full lane) |
| Test plan (default for normal/full) | /kit:test-plan | `## Test plan` written into the spec, in the type's dialect (test-design-standard §5b) | advisory default (normal/full); tiny exempt |
| Build    | /kit:execute or /kit:next | tasks checked, verifier PASS | verification pipeline (worker, verifier, fix; max 2) |
| Review   | /kit:review or /kit:review-team | review verdict recorded | advisory |
| Docs     | /kit:docs | README/CHANGELOG match code | advisory |
| Ship     | /kit:ship | tagged + PR | ship gate (blocks on DO NOT SHIP), push-to-main blocker |
| Reflect  | /kit:retro | docs/retro/v<version>.md written | advisory |
| Debug (off-cycle) | /kit:debug | root cause recorded, fix verified, human-confirmed | iron law + guess-fix guard (anti-rationalization) |

Throughout: safety-gate blocks destructive Bash; anti-rationalization blocks
premature "done"; auto-format runs on edit; session-state-save and
post-compact-reinject protect long sessions. The Debug row is an off-cycle
entry point (a bug-lane loop), not a linear phase between Reflect and the next cycle.

## The V-model lens

The cycle table above is the canonical phase list. This section reads it as a **V**.
The **left arm BUILDS**: each phase produces an artifact and statically reviews it
(verification, "did we build this right?"). The **right arm TESTS**: it executes the
test that validates each artifact and reports (validation, "does it actually work?").
**Build** is the vertex. The V-model's core move is that every artifact gets *two*
checks: a static review when it is produced (left/vertex) and a dynamic test later
(right). The kit does not shift test design up the left arm (it has one late
`/kit:test-plan` step), so the test-design + execution wing sits on the right.

```
   LEFT · BUILD (produce + review each artifact)        RIGHT · TEST (execute the mirror)
   ============================================        =================================

   Brief / Requirement ............................... Acceptance test   /kit:ship gate
   build /kit:think · /kit:assign  · review (none)
    Solution-design .................................. System test       project test suite
    build /kit:design  · review /kit:devs-team
     Spec ........................................... Integration test   integration-checker
     build /kit:spec (+research-*) · review /kit:spec-validate
      Code ......................................... Unit / task test    task-verifier
      build /kit:execute · /kit:next                                    (fix-agent repairs)
      review /kit:review · /kit:review-team (deep security: security-auditor)
       ╲                                            ╱
        ╰──── test design: /kit:test-plan writes the tests ────╯
                         (vertex: build = code + test code)

   UI track (downstream):  build /kit:ui-design · review /kit:visual-team
   Docs:                   /kit:docs verifies docs vs code (-> doc-verifier)
   Cross-phase (outside the V):  /kit:start · /kit:retro · /kit:debug · /kit:dispatch ·
                                 /kit:kit-health · /kit:absorb · responding-to-review
```

**The duality, read across.** Each row is one artifact, checked twice: a static
review when produced (left/vertex), a dynamic test when executed (right).

| Artifact | Built by | Static review (when produced) | Dynamic test (executed later) |
|---|---|---|---|
| Brief / requirement | `/kit:think`, `/kit:assign` | (none; ship gate traces back) | Acceptance test (`/kit:ship`) |
| Solution design | `/kit:design` | `/kit:devs-team` | System test (project suite) |
| Spec | `/kit:spec` (+ research-* agents) | `/kit:spec-validate` | Integration test (`integration-checker`) |
| Code | `/kit:execute`, `/kit:next` (+ `fix-agent`) | `/kit:review`, `/kit:review-team` (+ `reviewer`; deep: `security-auditor`) | Unit / task test (`task-verifier`) |
| UI design (downstream) | `/kit:ui-design` | `/kit:visual-team` | (visual; no dynamic test) |
| Docs | (written during build) | `/kit:docs` (+ `doc-verifier`) | (doc-verifier confirms vs code) |

So `/kit:spec-validate`, `/kit:devs-team`, `/kit:review`, `/kit:visual-team`, and
`/kit:docs` are not a separate lane: each is the **static verification of one
artifact, at the phase that produces it**, mirrored by the right-arm test that later
validates the same artifact.

**Commands vs agents.** A `/kit:...` entry is a *command* you invoke. A plain name
(`task-verifier`, `integration-checker`, `reviewer`, `doc-verifier`) is an *agent*
dispatched by a command, never invoked directly. The right-arm tests are executed by
agents (dispatched inside `/kit:execute`) plus the `/kit:ship` gate. The unit +
integration levels can also be re-run on demand, read-only, with `/kit:verify` (no rebuild).

**Cycle-table mapping.** The V-phase names above map onto the cycle-table rows:
Think, Design (opt-in), Design critique (opt-in), UI design (opt-in), Spec,
Validate, Test plan (default for normal/full), Build, Review, Docs, Ship, Reflect, and
Debug (off-cycle).

**The mirror gaps.**

- **Brief / Requirement** has no static-review command; the `/kit:spec-validate`
  acceptance-criteria check + the `/kit:ship` gate trace back to the brief instead.
- **Test design is one late step, not shifted left.** `/kit:test-plan` (opt-in)
  writes the tests; workers write the test code at the vertex. The classic V designs
  a test at every left phase; the kit concentrates it, which is why the testing wing
  is on the right.
- **No system-test command:** the project suite runs at build and at ship.

### Coverage gaps

The V is nearly complete. One open hole, judged against PHILOSOPHY criterion #2
(a feature must serve >= 2 lifecycle phases) and "no phantom features":

1. **CANDIDATE AGENT `acceptance-verifier`** (optional; v2 candidate). The acceptance
   test is checked *inline* by `/kit:ship`; everywhere else the kit verifies with a
   separate read-only agent (per "verify with a fresh context, not self-report").
   Extracting acceptance into a read-only `acceptance-verifier` that both `/kit:ship`
   and `/kit:verify` dispatch would complete the right-arm verifier set. Verdict:
   **consider, not urgent** (the inline gate works today).

Two gaps closed 2026-05-23: the `security-auditor` orphan (wired into `/kit:review-team`)
and `/kit:verify` (shipped, SPEC-035, the on-demand right-arm executor). The V is now
fully covered by commands + agents; the only open item is the optional `acceptance-verifier`
(v2 candidate). Everything else would be a phantom.

## Lane×phase depth matrix

How much ceremony each lane applies at each phase of the V-model. Rows are the
five risk-tier lanes (definitions and task-type mapping in the lane table above
under "Size the work first"). Columns are the phases from the cycle table and
the V-model lens above. Every cell is one of:

- **measure-twice** -- full ceremony for this phase; do not skip.
- **run-lite** -- lighter pass; advisory, opt-in, or quick-verify is enough.
- **skip** -- this phase does not apply to this lane.

| Phase | tiny | normal | full | bug | backfill |
|---|---|---|---|---|---|
| Think | skip | run-lite | measure-twice | skip | run-lite |
| Design (opt-in) | skip | skip | measure-twice | skip | skip |
| Design critique (opt-in) | skip | skip | measure-twice | skip | skip |
| UI design (opt-in) | skip | skip | run-lite | skip | skip |
| Spec | skip | measure-twice | measure-twice | skip | run-lite |
| Validate | skip | skip | measure-twice | skip | skip |
| Test plan (default) | skip | run-lite | measure-twice | run-lite | skip |
| Build | run-lite | measure-twice | measure-twice | measure-twice | skip |
| Review | skip | run-lite | measure-twice | measure-twice | run-lite |
| Docs | skip | run-lite | measure-twice | skip | measure-twice |
| Ship | skip | measure-twice | measure-twice | run-lite | skip |
| Reflect | skip | skip | measure-twice | skip | skip |
| Debug (off-cycle) | skip | skip | skip | measure-twice | skip |

**Non-obvious depth calls** (logged for traceability):

- **Think / normal = run-lite**, not measure-twice: the normal lane starts at
  `/kit:spec`, not `/kit:think`. A brief is implied by the spec, but a full Think
  session is not required. run-lite captures the light-touch intent check that
  naturally precedes writing a spec.
- **Test-plan / bug = run-lite**: a bug fix benefits from a reproduction plan
  (what breaks, what proves it is fixed), but a full test-plan session is not
  required. The verification pipeline and `/kit:debug`'s root-cause record cover
  the intent; run-lite reflects "light reproduce + verify" rather than full
  test-design.
- **Review / bug = measure-twice**: a bug fix is a high-stakes narrow change.
  The full lane uses review-team; the bug lane uses `/kit:review`, but the
  scrutiny level for a regression fix should be full, not advisory.
- **backfill / Spec = run-lite**: `/kit:spec` is optional for backfill (the lane
  table says "Doc-output only; no app-behavior change"). run-lite reflects
  "optional but encouraged for non-trivial backfills."
- **backfill / Docs = measure-twice**: docs ARE the output of a backfill run
  (AGENTS.md, CLAUDE.md, specs). This is the one phase that must be done fully.
- **backfill / Build = skip**: the lane table explicitly prohibits app-code
  edits; Build (the verification pipeline executing tasks) does not apply.

When a new phase is added to the cycle table (and the V-model lens gains a row),
add a column here and assign a depth per lane before shipping the change.

## Gate ledger and ship enforcement

Every phase gate a run executes is recorded to a per-run ledger, so the run is
auditable after the fact (ADR-0024). The lane×phase matrix above is the single
source for which gates a lane *requires* (its `measure-twice` cells);
`lib/gate-ledger.sh` parses it, with no second copy of the mapping.

- **Record each gate as you run it:** `bash lib/gate-ledger.sh record <spec-slug> <Phase> ran "<note>"`, where `<Phase>` is a matrix row name (Spec, Validate, Build, Review, Docs, Ship, ...). Record a deliberate skip as `... <Phase> skipped "<why>"` so the skip is visible, not silent. Log actions with `action <spec-slug> "<what>"`.
- **One append-only, redacted file per run** under `$DWARVES_KIT_LOG_DIR/runs/<slug>.log` (the existing hook-log convention; no command bodies or secret paths). It is an audit trail, never a source of state.
- **Enforcement is at ship only.** `hooks/ship-gate.sh` refuses a feature-branch push or `gh pr create` when the active spec's lane has a `measure-twice` gate with no `ran`/`override` entry. Mid-flight phases are never blocked (Detect, don't dictate).
- **Override, logged:** to ship past a missing gate, record a reason: `bash lib/gate-ledger.sh override <spec-slug> <Phase> "<reason>"`. The override is part of the audit trail; in a fully autonomous run it is agent-writable, so the guarantee is block-by-default plus every skip and override recorded, not a hard stop (ADR-0024).

## The spine
How a committed backlog item becomes shipped work, end to end:

```
session start
  -> /kit:start          RENDER the BACKLOG Active queue (the "what's left?" list)
                          and list active .claude/goals/ drafts. Read-only; a detector.
  -> /kit:assign ID-NNN  goal-crafter: break the item down, set objective + scope
                          fence + termination-on-blocker, write .claude/goals/<slug>.md
                          (the goal-draft contract), pick the lane, surface the draft body
                          for whatever goal-loop activator is present, hand off to the
                          lane's first command. Mutator; does NOT execute, never writes
                          last-goal.md.
  -> the lane runs        tiny | normal | full | bug | backfill (see the lane table above)
       normal/full -> /kit:spec -> /kit:spec-validate -> /kit:execute (verify pipeline)
                      (opt-in: /kit:devs-team + /kit:visual-team before spec; /kit:test-plan before execute;
                       /kit:ui-design for downstream UI work, after /kit:design)
                      -> /kit:review -> /kit:docs -> /kit:ship -> /kit:retro
       backfill    -> review the codebase, write AGENTS.md / CLAUDE.md / specs, then
                      /kit:review (optional). No /kit:execute; no app-code edits.
  -> on ship              /kit:ship reviews the completeness log; ID-NNN drops off the
                          queue (CHANGELOG is the canonical shipped record).
```

**Freeform front door.** `/kit:assign` accepts freeform intent, not only an `ID-NNN`. Given freeform, it delegates the interview to `/kit:think`, pauses for approval, then allocates the ID + BACKLOG row before routing as usual; the ID-first path is unchanged. **Detector/mutator split.** `/kit:start` and `/kit:next` only read and render; `/kit:assign` is the only mutator. **Activator-agnostic.** `/kit:assign` writes only the `.claude/goals/<slug>.md` draft and surfaces its body; activation (starting the loop) is done by whatever primitive is present (the built-in `/goal`, the `ralph-loop` plugin, or the `goal-craft` skill). The kit NEVER writes `.claude/last-goal.md`; if no activator exists, the draft is a plain reusable file. **"Even the goal loop follows WORKFLOW"** is delivered honestly: the safety subset is hard-enforced by existing hooks (anti-rationalization, the verification pipeline, the push-to-main blocker); decision/doc completeness is warned + logged to `~/.claude/dwarves-kit/logs/completeness.log` and reviewed at `/kit:ship` + `/kit:retro`, not hard-blocked mid-loop (PHILOSOPHY rejects hard-gating process completeness).

## Mid-flight amend
Canonical rule. You are mid-`/kit:execute` on a `VALIDATED` spec and the work
reveals scope that must be added now ("also do Y"). Amend the spec in place;
do not restart the lane and do not silently mutate it. The operator card
(`MANUAL.md` "## Operator scenarios") and `commands/execute.md` point here; they
do not restate this rule. The state-machine row (`BUILDING -> SPECIFYING ->
BUILDING`) lives in `docs/architecture.md` "## SDLC state machine"; this section
carries the operational rule, and the `## Flow and loop reference` below draws the
amend micro-loop.

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
  autonomous `/kit:execute` pauses for the operator to approve the added scope
  before the amend lands (this is AGENTS.md zone 4 "Pause if", a scope / risk /
  architecture change). Then record it as an entry in the spec's `## Amendments`
  section (optional, on-demand; see `commands/spec.md`), one line per amend:
  `AMEND-NNN: date | what | why | at which checkpoint | new tasks | re-validated`.
- **Resume leads with `/kit:next`, not a fresh `/kit:execute`.** `/next` picks
  the next undone `- [ ]` task and skips `- [x]` done rows, so resume runs only
  the amended tasks. `/execute` re-parses and re-presents the whole plan, so it
  is the wrong door after an amend.

## Completion contract
The done-definition is canonical in `AGENTS.md` zone 3 ("Done means"); do not
restate it here. In the kit, the task-verifier is what proves "done" (self-reported
"done" is not proof), and the anti-rationalization hook is the backstop for
premature completion. The clauses below add kit-specific completeness checks on top
of that done-definition.

### How lanes are judged (lane telemetry, SPEC-061)

Lanes are not assumed effective; they are measured. Every `/kit:assign` records a START line
(chosen lane, classified lane, work type, repo) into the run's gate ledger, reviews record
their verdicts, and `/kit:ship` records the PR outcome. `lib/lane-telemetry.sh report|misfires`
aggregates read-side; `/kit:retro` Step 1d reviews it with a disposition contract (every
misfire becomes a keyword fix + pin, a BACKLOG row, or a recorded accepted-noise line).

The questions the report answers, and what each signal means:

| Signal | Healthy | Unhealthy means |
|---|---|---|
| Misclassification rate (chosen != classified, both directions) | rare, explained | intake miscalibrated: tune keywords from the real phrasing (SPEC-060 pattern) |
| Gate skip/override rate per lane | occasional, reasoned | a chronically skipped gate is the wrong gate for that lane: move it in the matrix |
| Review findings curve per lane | a healthy nonzero | always-0 = dull lens; always-high = intake too loose (grill harder) |
| Duration vs lane weight (first..last ledger TS) | tiny short, full long | a tiny run spanning days = misrouted or blocked |
| Untracked runs (no START line) | ~0 | work is entering lanes outside /kit:assign: wire the entry point |

Telemetry proposes; the human at retro disposes ("Detect, don't dictate"). No daemon, no new
store: the pipe-delimited ledgers under `~/.claude/dwarves-kit/logs/` are the only substrate.

### Completeness clauses (warn + log, reviewed at ship)
Two self-check clauses run during Build/Reflect. Both WARN and LOG to `~/.claude/dwarves-kit/logs/completeness.log` (the `spec-drift-guard` logging shape); neither hard-blocks. `/kit:ship` and `/kit:retro` review that log at the gate. Hard blocks stay reserved for the safety subset (PHILOSOPHY rejects hard-gating process completeness).

- **Decision-translation.** Each decision in a spec's optional **Build decisions** sub-list (the decisions that imply implementation, tagged under a `### Build decisions` heading or a `Build:` prefix in the Decision Log) must be referenced by ID or `Implements:` target in a task or acceptance criterion; an orphan is warned + logged. Scope: ONLY the Build-decisions list. Rationale, rejected-alternative, and `(validation)`/`(reconciliation)` decisions are exempt. If a spec has no Build-decisions list, the clause is a no-op.
- **Doc-update.** The diff against the integration branch's merge-base (pinned, not a floating base) is checked against the doc-impact map below; a change that touches X without its companion docs is warned + logged. Normal/full lanes only (tiny-lane ship suppresses it).

#### Doc-impact map
Per change-type, the companion docs that must move with it. This covers the enumerated change-types; an unenumerated type is a logged gap (a warning), not a guarantee.

| If a change touches | Companion docs that must update |
|---|---|
| `hooks/*` | `MANUAL.md` (hook table + Troubleshooting), README hook table, `tests/test-hooks.sh`, `tests/test-meta.sh` |
| `commands/*` (new) | `MANUAL.md`, README command table, `.claude-plugin/plugin.json` + `marketplace.json`, `tests/test-meta.sh` |
| `agents/*` | README agent list, `tests/test-meta.sh` frontmatter checks |
| `settings.json` (hook wiring) | README hook table, `MANUAL.md` (Troubleshooting), `install.sh` merge logic |
| `install.sh` | README install steps, `tests/` |
| `rules/*` | README path-scoped-rules note, `docs/architecture.md` |
| `lib/*` | README "Project structure", `docs/architecture.md`, `tests/test-meta.sh` + `tests/test-hooks.sh` (helper unit tests) |
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

## Lead-owned convergence

When work fans out across branches or goal-loop iterations, certain surfaces are
touched by every change. To prevent write conflicts and to keep the integration
boundary clean, these surfaces are **hands-off for workers**; the lead integrates
them once via `/kit:ship` after all workers finish.

### Hands-off shared-surface list

Workers MUST NOT write these paths. The lead writes them exactly once at
`/kit:ship`:

- `CHANGELOG.md`
- `VERSION`
- `.claude-plugin/plugin.json`
- `tool.toml`
- `tests/test-meta.sh`
- `_meta/BACKLOG.md`
- `docs/retro/v*.md`
- `marketplace.json` (inherits version via `"source": "."`, also hands-off)

Every entry above appears in the doc-impact map's shared-surface rows (the
"any shipped change (normal/full)" row covers CHANGELOG, VERSION,
plugin.json, tool.toml, and retro; the "commands/*", "hooks/*", "agents/*",
and "AGENTS.md" rows cover test-meta.sh; the "docs/specs/SPEC-NNN" row
covers BACKLOG.md; the version-surfaces note covers marketplace.json).
This list is a subset of the doc-impact map; the subset invariant is enforced
by `tests/test-meta.sh`.

### Worker signal: READY or BLOCKED

Each worker, when its branch task set is complete, emits exactly one signal:

- `READY` -- all tasks verified, branch clean, no cross-task blocker seen.
- `BLOCKED` -- a blocker was hit that the worker cannot resolve alone (name it).

The worker records this signal as a one-line status in its branch's final
commit message or a `READY.md` / `BLOCKED.md` working-tree note (gitignored).
The lead collates these signals before running `/kit:ship`.

### Non-duplication clause

Convergence has three strictly bounded jobs: (1) enumerate and enforce the
hands-off shared-surface list above, (2) collate the READY/BLOCKED signals from
all worker branches, and (3) hand the integrated result to `/kit:ship`.

It does NOT do cross-task wiring checks -- that is `integration-checker`'s job,
run at `/kit:execute` Step 4. It does NOT write the shared surfaces -- that is
`/kit:ship`'s job (Steps 1b/4a/7 already own those writes). Convergence
writing to `CHANGELOG.md`, `VERSION`, or any other hands-off surface directly
is a violation of this contract.

### Enforcement: Detect, don't dictate

Convergence follows the kit's "Detect, don't dictate" principle. A worker
writing to a hands-off surface is warned and logged to
`~/.claude/dwarves-kit/logs/completeness.log`; it is never a hard block.
The lead reviews the log at `/kit:ship` before integrating. Hard blocks are
reserved for the safety subset (safety-gate hook, push-to-main blocker).

## What this contract does NOT do
It does not lock phases. An experienced operator may skip /spec-validate on a
normal-lane change or go straight to /next. The kit detects state
(context-readiness hook) and suggests the next step; it never blocks
progression. Hard stops are reserved for irreversible cost: destructive
commands, push-to-main, premature completion, failed verification.

## Goal drafts (.claude/goals/)
The kit keeps candidate goal drafts in `.claude/goals/<slug>.md` (gitignored,
per-machine) beside the built-in `/goal`'s single active slot
`.claude/last-goal.md`. The kit writes the drafts; the filesystem
(`ls .claude/goals/*.md`) is the sole source of truth, there is no derived cache
(ADR-0023). The kit NEVER writes
`last-goal.md`. Activating a draft means handing its body to
whatever goal-loop activator is present (the built-in `/goal`, the `ralph-loop`
plugin, or the `goal-craft` skill); if none is installed, the drafts still work
as plain reusable files. Brainstorm many drafts, one is active at a time; each
carries a `target_spec`/`id`. Picking a draft and routing it into a lane is `/kit:assign`; `/kit:start`/`/kit:next`
render the queue + drafts read-only. There is no separate `/kit:goals`
list/switch command (parked).

**Lifecycle (drafted -> archived-on-ship).** A draft lives at the top level of
`.claude/goals/` while its work is live; once its `target_spec` ships,
`lib/goal-drafts.sh archive` (run by `/kit:ship`) moves it to
`.claude/goals/done/` (moved, never deleted; `status:` flipped to `shipped`).
The render commands enumerate top-level `*.md` only, so an archived draft drops
out of "what's active" with no filter code. This is the goal **draft** store
("what's active"); do not confuse it with the cross-session running-goal
**registry** under `.git/kit-goals/` ("what's executing now", ADR-0022). The
shared slug ties a draft to its registry claim; the two stores sit side by side
in `docs/architecture.md` "## State model".

## Artifact placement and concurrency (multi-spec)
The kit's concurrency model is **worktree-per-spec**: many specs coexist
in `docs/specs/`, one is active per branch (branch-aware detection), and
"multiple active specs at once" means N git worktrees, each one-active.
**`/kit:dispatch` spawns the N worktree workers and converges them lead-owned**
(ADR-0019; one lead session, the in-session `Agent(run_in_background,
isolation:worktree)` primitive locked by ADR-0020), behind the disjointness gate
(`lib/dispatch-gate.sh`): two specs run concurrently only when their `## Touches`
globs are provably disjoint, and a post-task drift guard checks each worker stayed in
its globs. What stays an **external runtime, NOT the kit's job**: a DAG / wave
scheduler / topological ordering / crash-recovery durability (GSD v2), and auto-merge
(the human merges at `/kit:ship`). The kit does flat fan-out + a pairwise gate + a
wait-queue, and stops there.

The placement rule that keeps this safe: **an artifact bound to a spec lives IN the
active spec; a pre-spec or per-diff artifact stays a working-tree file (isolated by
the worktree).** Lanes that produce a spec-bound result resolve "the active spec"
through the one shared active-spec path (so a writer and a later reader never split
across two specs), and write into that spec, not a fixed-name root file. New lanes
must follow this: if your output binds to a spec, append it as a `## Section` in the
active spec (replace-not-stack), the way the critique, plan, and review lanes do
(`/kit:test-plan`, `/kit:devs-team`, `/kit:visual-team`, `/kit:ui-design`,
`/kit:review`, `/kit:review-team`).
The shared invariant is the spec-first head; `/kit:visual-team` adds an inline
fallback because it alone can run with neither a spec nor a brief.

| Artifact | Home | Scope | Why |
|---|---|---|---|
| `docs/specs/SPEC-NNN-<slug>.md` | committed, per-spec file | per-spec | the contract; unique name, no collision |
| `## Test plan` | in the active spec | per-spec | build input `/kit:execute` reads from the spec it runs |
| `## Design critique` (`/kit:devs-team`) | active spec, else the pre-spec brief | spec-first | binds to the design it critiques |
| `## UI design` + `## Visual critique` (`/kit:ui-design`; `/kit:visual-team`) | active spec, else the pre-spec brief (visual-team: else inline-only) | spec-first | both write `## Visual critique` to the same heading + location; replace-not-stack dedups |
| `docs/specs/DECISION-BRIEF.md` | working-tree file | one per worktree (pre-spec) | exists during `/think`+`/design` before a SPEC-NNN exists; `/spec` folds it into the spec's `## Solution`, after which the spec is the carrier |
| `## Review` (`/kit:review`, `/kit:review-team`) | in the active spec | per-spec | review verdict + findings + TODOs; replace-not-stack; inline in chat if no spec exists |
| kit logs, session-state | `~/.claude/dwarves-kit/...` | namespaced by worktree id | shared-path writes isolated per worktree |

The pre-spec brief is the one artifact that cannot be per-spec (no SPEC-NNN exists
yet); in that window concurrency relies on worktree isolation, and `/spec` folds the
brief into the spec so the spec becomes the carrier from then on. Same-directory
branch-switching is NOT a supported concurrency mode; use a worktree per spec.

### Multi-session (cross-session) coordination
`/kit:dispatch` above is the **single-session** case: one lead session fans out workers
and holds disjointness in its own context. The kit also supports the **multi-session**
case (ADR-0022, SPEC-036): one operator opens several Claude sessions on one machine, one
goal per session, and walks away. There is no shared lead, so the coordination moves onto
disk, a **passive running-goal registry** under `$(git rev-parse --git-common-dir)/kit-goals/`
(shared by every worktree of the repo, inherently untracked, never committed):

- **Claim before building.** `/kit:assign` runs `bash lib/goal-registry.sh claim <slug>
  <lane> <glob>...`; the goal is admitted only if its declared globs are disjoint from
  every active registered goal (the same `lib/dispatch-gate.sh` rule, reused). An overlap
  is REFUSED with the colliding goal named; the operator serializes or repicks.
- **One single-writer file per goal.** A session writes only its own `<slug>.goal`, the
  same one-writer-per-surface model as the hands-off list; no shared write.
- **Monitor from any session.** `bash lib/goal-registry.sh list` (surfaced in
  `/kit:start`) shows every running goal + lane + status across sessions, the kit-level
  companion to the native agent view (which sees only one session's subagents).
- **Each goal leaves an attempt log.** `bash lib/goal-registry.sh log <slug> "..."`
  appends a human-legible line of what the goal tried (`<slug>.attempts`).
- **Release on completion.** `bash lib/goal-registry.sh release <slug>` drops the entry.
  A stale `running` entry from a crashed session is visible in `list` and cleared the same
  way; there is no GC daemon (that would be a runtime).

What stays an **external runtime, NOT the kit's job** (unchanged): coordination across
machines, by 3+ live human operators, or with goal-ordering chains (B waits for A to
merge), all L5 (Nimbalyst / GSD v2). The registry records and compares; it never
schedules, sequences, or merges.

Design provenance for every rule in this contract lives in `docs/specs/` and
`docs/decisions/`: the spec files and ADRs carry the rationale and history. This
contract states the rules; it does not cite the spec IDs that decided them.

## Flow and loop reference

The visual companion to the contract above: the same machine drawn as flows and
loops. The tables above are the rules; this section is the picture. For per-command
operator detail read `MANUAL.md`; for component fit and the SDLC state machine read
`docs/architecture.md`.

At a glance: **1** backbone (the spine, above), **5** primary intake lanes (the lane
table, above), **3** bounded loops (the engines, below), **8** opt-in side-flows,
**7** alternate/branch flows, and **4** hard stops (the only blockers). Everything
except the four hard stops **suggests and routes; it does not block**.

### The state stores the flows move between

Three stores; nothing is re-entered between phases. (The durable/ephemeral table is
in `docs/architecture.md` "## State model"; this is the flow view.)

```text
  _meta/BACKLOG.md            docs/specs/SPEC-NNN-<slug>.md      .claude/goals/<slug>.md
  ┌─────────────────┐         ┌──────────────────────────┐      ┌──────────────────────┐
  │ the Active queue│         │ the contract             │      │ ephemeral goal drafts│
  │ ID-NNN rows     │ ──────▶ │ Status: DRAFT            │ ◀──▶ │ (gitignored,         │
  │ status:         │  assign │        -> VALIDATED      │      │  per-machine)        │
  │ queued/speccing/│         │        -> SHIPPED        │      │ one draft per ID     │
  │ validated/      │         │ tasks, AC, Verification, │      └──────────────────────┘
  │ executing/      │         │ After state, Open Qs     │        the built-in /goal owns
  │ shipped (parked)│         └──────────────────────────┘        .claude/last-goal.md;
  └─────────────────┘                                             the kit NEVER writes it
```

**Detector vs mutator** (load-bearing): `/kit:start` and `/kit:next` only read and
render the queue + drafts. `/kit:assign` is the only mutator: it writes a goal draft,
flips a backlog status, and hands off. Given freeform intent instead of an `ID-NNN`,
`/kit:assign` delegates the crystallize interview to `/kit:think`, then allocates the
ID + BACKLOG row (approve-before-allocate, sanitized) before routing as usual.

### Pick a lane (the decision tree)

```text
                       is it a defect / regression / failing test ?
                                   │ yes            │ no
                                   ▼                ▼
                                 bug          new work on an existing repo
                                              with no operate-layer docs ?
                                                   │ yes        │ no
                                                   ▼            ▼
                                                backfill    how big / how risky ?
                                                            ├─ trivial edit ....... tiny
                                                            ├─ one bounded change . normal
                                                            └─ risk-list match .... full
```

The `full` trigger list (see the lane table) is a hard tripwire: anything on it uses
`full` unless you explicitly narrow the scope and say why.

### The three bounded loops (engines)

The kit ships **bounded in-session loops** and declines **unbounded outer loops**. A
bounded loop continues *within* the current session under a model-evaluated stop
condition plus the safety subset; an unbounded loop spawns *new* sessions without one
(autonomous-runtime territory, out of scope). All three engines are bounded.

**Goal loop.** A continuation that keeps the session working one objective until a
verifiable stop holds. Wired from the backlog by `/kit:assign`, activated by whatever
loop primitive is present (the built-in `/goal`, the `ralph-loop` plugin, or the
`goal-craft` skill). Enforcer: the anti-rationalization Stop hook (blocks premature
"done"), plus the rest of the safety subset. Stop: the objective's `## Verification`
command(s) pass AND the done-definition holds; on an unresolvable blocker it appends a
note to the spec's `## Open questions` and stops.

```text
   activator starts the objective
            │
            ▼
   ┌───▶ do the next increment ──▶ run ## Verification
   │            ▲                        │
   │            │                  pass? │
   │            │              ┌─────────┴─────────┐
   │            │           no │                   │ yes
   │            │              ▼                   ▼
   │            │     anti-rationalization     ALL done? ──no──┐
   │            │     blocks "done";           │ yes           │
   │            └─────  keep working ◀─────────┘               │
   │                                                            │
   │   hit a blocker you can't resolve?                         ▼
   └── write a note to spec ## Open questions ─────────────▶  STOP
```

**Debug loop** (`/kit:debug`, the `bug` lane). A systematic loop (Phase 0 + four phases)
under one iron law: **NO FIX WITHOUT A RECORDED ROOT CAUSE.** Phase 0 builds the feedback
loop first: a fast, deterministic, agent-runnable pass/fail signal that every later phase
consumes (SPEC-059). Evidence accrues in an append-only
ledger `.claude/debug/<slug>.md` whose `## Root cause` heading is the contract.
Enforcer: the guess-fix guard (a gated mode of the anti-rationalization hook) blocks a
fix/done claim while the open ledger's `## Root cause` is empty. Stop: root cause
recorded + fix verified + human-confirmed.

```text
   /kit:debug
       │
       ▼
   Phase 0: Feedback loop ─▶ Phase 1: Root cause ─▶ Phase 2: Pattern ─▶ Phase 3: Hypothesis ─▶ Phase 4: Implementation
       │  (ledger            (reproduce,          (predict, then         (apply the fix)
       │  ## Root cause)     narrow; bisect        test the guess)            │
       │                     if regression)             │                     ▼
       │                                                │                verified? ──no──┐
   guess-fix guard: a fix/done claim is BLOCKED         │                     │ yes      │
   while ## Root cause is empty ◀───────────────────────┘                     ▼          │
                                                                       human-confirm     │
   3 failed fixes in a row ──▶ STOP: architecture wall (rethink design)        │         │
                                                                               ▼         │
                                                                             DONE ◀──────┘
```

**Execute verification pipeline** (the build engine). `/kit:execute` dispatches one
worker per task, verifies each in a fresh context, retries fixable failures, and checks
cross-task wiring at the end. Self-reported "done" is never proof; the verifier is.
Enforcer: the verification pipeline is itself a hard stop. Stop: every task PASS **and**
the integration-checker PASS (multi-task specs). Branches: `PASS` (advance),
`FAIL:fixable` (retry via fix-agent, **max 2**), `FAIL:escalate` or retries exhausted
(stop -> human).

```text
   /kit:execute  (record pre-build base ref)
        │
        ▼
   ┌── for each task in phase ──────────────────────────────────────────┐
   │     worker subagent (fresh context) ──▶ task-verifier (read-only)   │
   │                          ┌───────────────────┼───────────────────┐  │
   │                       PASS              FAIL:fixable        FAIL:escalate
   │                          │                   │                    │  │
   │                          │                   ▼                    │  │
   │                          │            fix-agent (scoped)          │  │
   │                          │            re-verify; retry < 2 ─┐     │  │
   │                          │            retries == 2 ─────────┼────▶│  │
   │                          ▼                                  │     ▼  │
   │                   mark task done ◀────────────────────────────  ESCALATE
   └──────────┬─────────────────────────────────────────────────────────┘
              │ all tasks PASS
              ▼
   phase checkpoint (human: continue / review / stop)
              ▼
   integration-checker (read-only, diffs whole build from base ref)
        ┌─────┼───────────────┐
      PASS  FAIL:fixable   FAIL:escalate
        │     │ (fix-agent)     ▼
        ▼     ▼            ESCALATE
      build complete ◀── re-check
```

**Mid-flight amend micro-loop** (a side excursion off the execute pipeline, not a
fourth engine). The canonical rule + four invariants are in "## Mid-flight amend"
above; this only draws the loop.

```text
   BUILDING (mid /kit:execute, spec is VALIDATED)
        │  trigger: "also do Y"
        ▼
   reach a task checkpoint  ──────────────────────────────┐
   (in-flight task verified + committed; - [x] frozen)     │ not at a checkpoint yet?
        │                                                  │ finish the in-flight task first
        ▼                                                  └──────────────────────────────┘
   SPECIFYING (amend, not restart)
        - append new - [ ] TASK rows; delta After-state / AC / Verification
        - record an ## Amendments entry
        - re-validate the DELTA only (full: /spec-validate; normal: advisory)
        │  Status STAYS VALIDATED (no drop to DRAFT)
        ▼
   /kit:next  ──▶  BUILDING (resume; runs only the amended tasks)
```

### Opt-in side-flows (8)

Advisory, never blocking. They enrich a lane but are not required by any. All write
**into the active spec** when the output binds to a spec (replace-not-stack), so a
later reader and an earlier writer never split across two specs.

| # | Flow | Trigger | Writes to | Stop |
|---|---|---|---|---|
| 1 | `/kit:design` | between `/think` and `/spec`, when the solution needs working out | `docs/specs/DECISION-BRIEF.md` (folded into the spec by `/spec`) | solution agreed per section |
| 2 | `/kit:devs-team` | before the spec hardens; 5 engineering lenses | `## Design critique` in the active spec (else the brief) | verdict recorded |
| 3 | `/kit:visual-team` | a visual/UI design exists (downstream) | `## Visual critique` in the active spec (else brief, else inline) | verdict recorded |
| 4 | `/kit:ui-design` | downstream UI work, after `/design` | `## UI design` in the spec; generates via `frontend-design`; critiques via `/visual-team` | SOLID/RECONSIDER verdict or max-2 revise |
| 5 | `/kit:test-plan` | before `/execute`; derive a coverage matrix | `## Test plan` in the spec (consumed by `/execute`) | matrix written |
| 6 | `/kit:review-team` | PR-grade review; 3 lenses (security/architecture/test-coverage) in parallel | `## Review` in the active spec (else inline) | SHIP / FIX THEN SHIP / DO NOT SHIP |
| 7 | `/kit:absorb` | maintainer-only external-absorption audit | dated report under `docs/absorption/` | proposal-only report (human merge gate) |
| 8 | `/kit:kit-health` | maintainer self-assessment vs PHILOSOPHY, before tagging | report (stdout) | assessment rendered |

### Alternate / branch flows (7)

The edges that fire when the happy path does not hold.

1. **Retry (fixable failure).** A `task-verifier` / `integration-checker` `FAIL:fixable`
   dispatches a scoped fix-agent, then re-verifies. Cap: 2 retries. 1-2 cycles catch
   import/assertion/off-by-one bugs; 3+ means a design problem.
2. **Escalate (unfixable or exhausted).** `FAIL:escalate`, or retries hitting the cap,
   stops the loop and hands to the human with full context. Never auto-retried.
3. **Ambiguous spec.** When more than one non-`SHIPPED`/`PARKED` spec is active and the
   branch slug does not disambiguate, the detectors emit `spec:ambiguous(...)` and ask
   rather than silently pick.
4. **No activator installed.** `/kit:assign` detects the goal-loop activator (`/goal` ->
   `ralph-loop` -> `goal-craft`). If none is installed it degrades gracefully: the draft
   is left as a plain reusable file. Only one-step activation is lost.
5. **Idempotent re-run.** Re-running `/kit:assign` for an ID that already has a
   `.claude/goals/<slug>.md` re-surfaces the existing draft instead of duplicating it or
   double-advancing status. The filesystem is the source of truth.
6. **DO-NOT-SHIP gate.** `/kit:ship` reads the spec's `## Review` verdict first.
   `DO NOT SHIP` -> stop, fix first. `FIX THEN SHIP` -> apply fixes, then ship. No
   `## Review` section -> warn and ask; never silently skipped.
7. **Completeness warn + log (not a block).** Two self-checks (decision-translation and
   doc-update) warn + log to `~/.claude/dwarves-kit/logs/completeness.log` without
   blocking; `/kit:ship` and `/kit:retro` review that log at the gate. (Full rule: the
   "## Completion contract" above.)

### The four hard stops (the only blockers)

Everything else suggests or warns. These four refuse to proceed, because the cost of the
mistake is irreversible:

| Hard stop | Fires on | Mechanism |
|---|---|---|
| safety-gate | destructive Bash (`rm -rf`, `DROP TABLE`, `git reset --hard`, `kubectl delete`; build-artifact allowlist exempt) | PreToolUse hook, exit 2 |
| push-to-main blocker | a push to `main`/`master`/protected | PreToolUse hook, exit 2 |
| anti-rationalization | premature "done" claim; phantom-impl stub in the diff; guess-fix while `## Root cause` empty | Stop hook |
| verification pipeline | a task whose acceptance criteria are unmet or whose tests did not actually run | `/execute` gate (worker -> verifier -> fix -> escalate) |

### Quick reference: trigger -> flow -> stop -> enforcer

| Trigger | Starts | Stop condition | Enforcer |
|---|---|---|---|
| `/kit:start` | render queue + drafts | output rendered | none (detector) |
| `/kit:assign <ID-NNN or freeform>` | goal draft + lane routing (freeform: delegate to `/kit:think`, then allocate ID + row) | draft written, status flipped, handed off | none (mutator; idempotent; approve-before-allocate) |
| `/kit:dispatch <specs>` | disjointness gate -> N background worktree workers -> lead-owned convergence | all workers READY + drift-clean, converged via `/kit:ship` | disjointness gate + drift guard (`lib/dispatch-gate.sh`); no auto-merge; no DAG (ADR-0019) |
| `/kit:think` | decision brief | brief written (if BUILD) | advisory |
| `/kit:spec` | spec scaffold | spec exists, `Status: DRAFT` | spec-drift-guard hook |
| `/kit:spec-validate` | 5-lens adversarial review | `Status: VALIDATED` | advisory (full lane) |
| `/kit:execute` | verification pipeline | all tasks + integration PASS | verification pipeline (hard) |
| `/kit:debug` | feedback-loop-first debug loop (Phase 0 + 4 phases) | root cause + fix verified + human-confirmed | iron law + guess-fix guard |
| `/kit:review[-team]` | review | verdict recorded in the spec's `## Review` | advisory |
| `/kit:docs` | doc sync + doc-verifier | docs match code | advisory |
| `/kit:ship` | ship pipeline | tagged/PR; spec `SHIPPED`; ID off queue | ship gate + push-to-main blocker (hard) |
| `/kit:retro` | retrospective | `docs/retro/RETRO-<date>-<slug>.md` written | advisory |
| a `/goal` activator | goal loop | `## Verification` passes + done-definition | anti-rationalization (hard) |
