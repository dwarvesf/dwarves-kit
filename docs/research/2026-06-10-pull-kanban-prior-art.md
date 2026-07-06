# Prior art: pull-based agent kanban + dynamic persona dispatch

Date: 2026-06-10. Backlog: ID-047 (the kit-north-star dogfood task). Type: research.
Method: claim-verification matrix designed BEFORE the sweep
(`docs/verification/pull-kanban-prior-art/test-design.md`); every load-bearing claim below
traces to a matrix row (C1-C6) with its recorded result in
(`docs/verification/pull-kanban-prior-art/runs/2026-06-10-0730.md`). Two sweep personas ran in
parallel (a local-evidence prober, an external web verifier) per the type registry's
`dynamic: one persona per sweep angle` agent mode.

## Question

The kit now has a pull-able board (`/kit:assign --next`, SPEC-055) and per-type loops with an
`agent` column (SPEC-054). The NEXT phase wants (a) autonomous pulling (no operator invocation)
and (b) dynamic persona selection at dispatch. What prior art exists with directly reusable
mechanics, and what should we deliberately NOT copy?

## Findings

### 1. OpenClaw Workboard, the closest pull-board prior art [C1]

A Control UI kanban whose cards live in a gateway-local SQLite db; agents drive it through
first-class TOOLS: `workboard_claim / complete / block / heartbeat / decompose / dispatch`
(humans post cards via the UI). The load-bearing mechanic for us: **the pull verb is an agent
tool, not an operator command**. The kit's `--next` is operator-invoked today; Workboard shows
the end-state where claiming is something the executing agent does itself, with heartbeat +
block as the health verbs around it. (ops-toolkit `tools/openclaw/`, SPEC-082.)

### 2. OpenClaw persona catalogs, dynamic selection that actually ships [C2]

13 persona markdown files (`persona:` name, `use-when:`, `difficulty:`, `task-types:` headers;
role prose as body). Selection is **dynamic in-prompt at dispatch**: the lead model reads the
catalog (assembled into its AGENTS.md at deploy time), matches `use-when` against the task, and
prepends the chosen persona's body into the spawned session's task string (SPEC-080 DEC-001:
inlined rather than agentId-attached, working around an upstream spawn bug). Personas are
templates, not agents; selection is model judgment over structured headers, not a lookup table.
This maps 1:1 onto the kit registry's `dynamic:` agent mode: the registry row names the rule,
a persona catalog supplies the candidates, the dispatching model picks by `use-when`.

### 3. GSD (gsd-pi), what NOT to copy, with two corrections [C3]

Active home `github.com/open-gsd/gsd-pi` (the `gsd-build/gsd-2` repo redirects). A TypeScript
app embedding the Pi coding agent; crash recovery is first-class ("no in-memory state survives
across sessions": lock-file crash detection, completed-key persistence); git automation is
**branchless worktrees** + auto-commit/merge (its ADR-001), not branch creation. Correction
that matters here: its task mechanics are a **push-style dispatch loop** (derive project state
from a db, compute the next unit over a milestone -> slice -> task dependency graph), NOT a
pull board; "wave" in its docs is migration phasing, not a runtime mechanic. So GSD remains
what PHILOSOPHY says it is, the external engine for execution DEPTH, and is NOT prior art for
the pull-board shape. Copying its scheduler would trip both the §1 "Shallow and wide" boundary
and §6 N2's reject list.

### 4. AutoGen SelectorGroupChat, persona selection as a first-class dispatch input [C6]

Microsoft AutoGen (AgentChat) selects the next speaker **per turn, model-driven**, from the
shared context plus each agent's `name` + `description`; a `selector_func` overrides with
deterministic routing; `allow_repeated_speaker` tunes the default. The persona IS the dispatch
input, re-evaluated every turn. (CrewAI's `Agent(role=, goal=, backstory=)` is the static
counterpart.) Together with finding 2 this gives the kit a two-layer pattern: structured
persona headers as candidates (OpenClaw-style) + model-driven per-dispatch selection with a
deterministic override hook (AutoGen-style).

### 5. Native surfaces already under the kit [C4, C5]

Claude Code's harness exposes TaskCreate/TaskList/TaskUpdate/TaskStop + Monitor and
CronCreate/CronList/RemoteTrigger natively (verified in-session); the kit's
`lib/goal/goal-registry.sh` already implements the cross-session claim guard (exercised live in this
run's pull). An autonomous-pull design therefore needs NO new daemon primitive: a scheduled
invocation (cron/RemoteTrigger) of the existing `--next` flow + the existing claim guard covers
the trigger and collision halves, leaving only the policy question (when MAY a pull happen).

## Implications for the next phase (design hints, not commitments)

- Pull: promote `--next` from operator command toward an agent verb (Workboard's
  claim/heartbeat/block vocabulary is the proven shape); the trigger can be a scheduled
  invocation of existing machinery, no new runtime (C4/C5).
- Personas: a catalog of structured-header markdown templates + model selection by `use-when`
  at dispatch + a deterministic override hook (C2 + C6). The registry's `agent` column is
  already the anchor point.
- Do not import a scheduler/DAG (C3, corrected): dependency-ordered push dispatch is GSD's
  territory; the kit stays a pull board over a markdown file.

## Limitations

- Single npm fetch failed (npmjs.com 403); substituted the registry JSON API ([UNAVAILABLE
  noted] in the run record).
- CrewAI cited from general knowledge as the static counterpart, not probed; AutoGen carries
  the load-bearing citation.
- OpenClaw findings reflect the ops-toolkit deployment as of 2026-06-10.
