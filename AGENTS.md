# AGENTS.md: the operating layer

> Tool-agnostic front door. Any agent runtime (Claude Code, Codex, Gemini, a
> human) reads this first to learn how work is done in this repo. It carries the
> portable operate-contract: what to read, how to run a unit of work, when work
> is done, and when to stop and ask.

## Enforcement boundary (read this first)

**This file is a contract, not a guardrail.** Enforcement is Claude-Code-only: the
hooks (safety-gate, push-to-main blocker, anti-rationalization Stop hook, the
verification pipeline) are what actually block bad outcomes, and they run only
under Claude Code. Under any other runtime (Codex, Gemini, a bare LLM)
`AGENTS.md` is **advisory only**: it tells an agent what to do, but nothing
enforces it. Do not assume the guardrails are portable. They are not, until the
v3.x multi-runtime agent-hook work lands. See `docs/PHILOSOPHY.md` (honesty rule:
never over-claim portable enforcement) and `CLAUDE.md` for the CC-specific layer
(hooks, slash commands, plugin).

The rest of this file is four portable zones. The goal-crafter
(`commands/assign.md`) projects them into a six-section `/goal` (see "How a goal
is composed" at the end).

---

## 1. Read in this order

Orient before you touch anything. Read top to bottom; stop when you have enough.

1. **AGENTS.md** (this file) - how work is done here; the operate-contract.
2. **CLAUDE.md** - the Claude-Code layer: stack, structure, rules, hooks, commands, plugin.
3. **docs/specs/SPEC-NNN-<slug>.md** - the active spec; the shared contract for the cycle. Read its `## Verification` and `## After state` before implementing.
4. **docs/architecture.md** / **WORKFLOW.md** - reference, not required per task. Read `docs/architecture.md` for how the pieces fit; read `WORKFLOW.md` for the lanes and the gate at each phase boundary.

## 2. Task loop

How to do one unit of work. The smallest verifiable increment, verified, committed.

0. **Take work.** Handed a task: use it. **Handed a WAVE (2+ items approved in one
   conversation): enqueue every item as a board row FIRST (queued; the in-flight one
   executing), then pull them one at a time.** Work that never touches the board is
   invisible to the board's state machine even when its runs are ledgered, the gap an
   operator caught live on 2026-06-10 (SPEC-064). Not handed one: pull the board's top queued item,
   `bash lib/backlog.sh next`, claim it (goal-registry) and flip it to `claimed` (the
   `/kit:assign --next` flow). The BACKLOG is the board; its Status column is the state
   machine (`queued -> claimed -> speccing -> validated -> executing -> shipped`, + parked/
   dropped). Operator-named work is unchanged; pull is an additional trigger, never a daemon.
1. **Classify the type, then size the lane.** `bash lib/task-type-classify.sh classify "<task>"`
   first: `spec-feature` picks a lane below; any other type (incident / reconcile / operate /
   planning / learning / eval / research / doc / migration / data-tool) runs its TYPE LOOP per
   `WORKFLOW.md ## Type loops`, with its executor from the registry's `agent` column. For code:
   pick `tiny` / `normal` / `full` / `bug` / `backfill` per `WORKFLOW.md`; when in doubt between
   two lanes, take the heavier one. **Between classification and done comes the grill** (`/kit:grill`, or its
   one-question-at-a-time discipline driven inline): interview until the task is actually
   understood, type-shaped questions, recommended answers, contradictions checked against the
   repo, answers WRITTEN as they resolve (glossary / sparse ADR / the goal draft's Context).
   Tiny lane exempt. **Record the grill's disposition either way** (SPEC-063):
   `bash lib/gate-ledger.sh record <slug> grill ran "<N> branches resolved"`, or, when the
   conversation already resolved the banks, `... record <slug> grill skipped "<why>"`; a
   skip without a reason is invisible to telemetry, which defeats the point.
   **Then phase 0: define the done scenario**
   (`bash lib/proof-gate.sh contract "<task>"` + the type's test-design dialect,
   test-design-standard §5b) BEFORE any work runs; the grill's answers are the done's raw
   material, and the goal draft carries the `Done =` line.
2. **Read the spec and its acceptance criteria.** For a spec-driven task: the active spec's task row, its AC, its `## Verification`, and its `## After state`. No spec (tiny lane): the one obvious edit.
3. **Implement the smallest verifiable increment.** One logical change. No speculative features, no premature abstraction; clarity over cleverness.
4. **Verify.** Run the spec's `## Verification` command (or the lane's check). Do not claim a result you did not run.
5. **Commit.** Conventional commit, one logical change. No spec/ticket IDs in the subject line.

If you cannot make progress, see zone 4 (Pause if) and stop with a named blocker note. Do not churn.

**Show the road, then your position on it (SPEC-063).** Right after a lane is committed,
print the checklist the run will walk: `bash lib/gate-ledger.sh plan <lane>`. At each phase
entry, print where the run stands: `bash lib/gate-ledger.sh progress <spec-slug> <lane>`
(one status line: `<rid> · <lane> · step k/n (<phase>)` + the ✓/▶/· checklist). For the
full story of a past or in-flight run: `bash lib/lane-telemetry.sh trace <rid>`.

**Escalate the review for enforcement surfaces (SPEC-069).** A run touching `lib/` or
`hooks/` uses `/kit:review-team` (multi-lens), not a single reviewer.

**Record your gates (ADR-0024).** When you run a phase gate (`/kit:spec`, `/kit:spec-validate`, `/kit:execute`, `/kit:review`, `/kit:docs`, `/kit:ship`, ...), record it so the run is auditable: `bash lib/gate-ledger.sh record <spec-slug> <Phase> ran`; record a deliberate skip as `skipped "<why>"`. The `ship-gate` hook refuses a push whose lane has a required gate with no `ran`/`override` entry. Full convention + the logged-override path: WORKFLOW.md "## Gate ledger and ship enforcement".

## 3. Done means

A task or goal is done only when **its acceptance criteria are met AND the
verifier actually ran the check**, not when you claim they pass. Self-reported
"done" is not proof. The check compares against the `Done =` scenario defined at
phase 0, whatever the work's type (PHILOSOPHY §6 N3): if no done scenario was
defined before the work ran, the work was not assignable, and "done" has nothing
to be measured against.

Concretely, done means: **acceptance criteria met, the check actually ran (not
just asserted), review recorded + report written, and the final response says
what changed and what was not attempted.** If you could not run the check, report
that plainly; the anti-rationalization hook is the backstop for premature
completion under Claude Code, but the honesty obligation is yours under any
runtime.

## 4. Pause if (ask a human)

Stop and ask a human before acting on any of these. These are decisions with
direction or irreversible cost that a goal loop must not make on its own.

- **Architecture direction** - a change to how the pieces fit, a new component, an interface or data-model shape.
- **Source-of-truth hierarchy** - which file or section is canonical when two disagree (for example, moving the operate-contract between `AGENTS.md`, `CLAUDE.md`, and `WORKFLOW.md`).
- **Validation removal** - weakening, deleting, or bypassing a test, an assertion, a hook, or any guardrail.
- **Risk-classification change** - moving work to a lighter lane, or narrowing a `full`-lane trigger (auth, authz, hooks, data model, data loss, audit/security, external provider, API contract, migration).
- **Privacy / security** - secrets, credentials, access scope, anything that touches what data leaves the repo or who can reach it.

When you pause: write the named blocker, state the decision you are not making and why, and stop.

---

## How a goal is composed (for `commands/assign.md`)

The goal-crafter projects these four zones into a six-section `/goal`. The mapping
is a **composition, not 1:1**: two of the six sections come from the active spec,
not from this file. Keep the four zone names stable; renaming one without updating
`commands/assign.md` breaks the projection.

| `/goal` section | Source |
|---|---|
| Context-to-read | AGENTS.md zone 1 (Read in this order) |
| Constraints | CLAUDE.md / AGENTS.md rules |
| Operating rules | AGENTS.md zone 2 (Task loop) |
| Validation loop | the active spec's `## Verification` |
| Done-when | AGENTS.md zone 3 (Done means) + the active spec's `## After state` |
| Pause-if | AGENTS.md zone 4 (Pause if) |
