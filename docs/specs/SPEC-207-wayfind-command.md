# SPEC-207: /kit:wayfind, the file-based decision map

Status: Draft · 2026-07-31 · Owner: Han
Lane: full
Relates-to: docs/research/2026-07-31-mattpocock-trio-adoption.md §1+§4 (adoption +
wiring design; board row ID-450), SPEC-206 (/kit:prototype, the prototype-ticket
executor), ADR-0032 (mega-goal delegate execution, the do-half this decide-half
co-locates with), SPEC-055 (the board, which keeps one umbrella row per map)

## Problem

Work bigger than one agent session arrives wrapped in fog: the kit can grill
ONE task, think ONE brief, and execute a ROADMAP of sub-goals, but has no
shape for the stretch before the ROADMAP is writable, when the open questions
outnumber the stateable ones and every new session re-derives context. The
2026-07-25 pass parked the tracker-native version of upstream wayfinder; the
2026-07-31 adopt ask takes the file-based shape (upstream's own fallback,
zero new infra).

## Solution shape

One new user-invoked command, `commands/wayfind.md` (ported from
mattpocock/skills wayfinder, MIT, re-based onto files + the kit board), plus
the WORKFLOW.md wiring for it and for SPEC-206's prototype beat. The command
carries `disable-model-invocation: true`: wayfind is the heaviest intake
shape and upstream's documented failure mode is over-reach, so the model must
never self-chart a map; only the human opens one.

1. **The map** lives at `_meta/megagoals/<slug>/map.md`: sections Destination
   / Notes / Decisions so far (one gist line + pointer per closed ticket) /
   Not yet specified (fog) / Out of scope. The map is an index, not a store;
   a decision lives in its ticket file only. Co-location is deliberate:
   wayfind is the decide-half of the folder whose do-half is ROADMAP.md
   (ADR-0032); graduation happens in place.
2. **Decision tickets** are files, `_meta/megagoals/<slug>/tickets/NN-<slug>.md`,
   each holding header lines (`Type: research|prototype|grilling|task`,
   `Status: open|claimed|closed`, `Claimed-by:`, `Blocked-by: [NN, ...]`) and
   a `## Question` sized to one agent session. The frontier = open, unblocked,
   unclaimed tickets. Claim before any work by writing `Status: claimed` +
   `Claimed-by:`; concurrent sessions skip claimed tickets.
3. **Types route to owned machinery**: grilling -> `/kit:grill` (HITL, the
   default; the agent NEVER answers its own grill questions), prototype ->
   `/kit:prototype` (HITL), research -> parallel research subagents on
   throwaway `research/<name>` branches (AFK; the one exception to
   one-ticket-per-session), task -> the normal lane ladder (the one type that
   does rather than decides; earns its place by unblocking a decision).
4. **Two modes.** Chart: name the destination (grill), breadth-first grill
   for the frontier (no fog surfaced = no map needed, stop and say so),
   write map + stateable tickets, wire Blocked-by in a second pass, fire the
   research subagents, stop (charting hand-resolves nothing). Work: load the
   map low-res, claim the first frontier ticket (or the named one), resolve
   via the type's machinery, record (answer in the ticket, Status: closed,
   gist line appended to Decisions so far), graduate fog, rule mis-scoped
   tickets out of scope. One ticket per session, research excepted.
5. **Exit**: the map is done when nothing is left to decide. Hand off to
   `/kit:spec` (single feature) or a ROADMAP.md beside the map (`/kit:mega`);
   Decisions so far becomes the brief/spec Context. Never straight to
   execute. Router line carried from upstream's admitted failure mode: a
   well-scoped feature belongs on `/kit:grill` + `/kit:spec`, not wayfind.
6. **Board wiring**: ONE umbrella board row per map (SPEC-055 stays the one
   source of truth for work items); tickets are never duplicated as board
   rows. WORKFLOW.md "Where work comes from" gains the wayfind paragraph;
   the phase table gains SPEC-206's opt-in Prototype row (deferred from that
   spec to keep its lane normal).

## Out of scope

Tracker-native storage (GitHub Issues, native blocking edges) stays PARKED
with its 2026-07-25 tripwire (Multica outgrows flat cards; unpark vehicle
ID-425). No lib/ or hooks/ changes; no board-machinery changes (ticket
claim/status is a deliberate lightweight file-header vocabulary,
`open|claimed|closed`, SEPARATE from the board's state machine; this
supersedes the research doc's earlier "reuse the kanban claimed state"
sketch, which pre-dated the ticket-file design); no changes to /kit:mega.
The cross-worktree claim race is mitigated by the commit-is-the-claim rule
in the command body, not by a lock: a push rejection is the collision
signal. Ceiling accepted for v1; the goal-registry stays the lock for the
umbrella effort, not per ticket.

## Test plan

Doc-dialect (prompt-file artifact, no runnable behavior): the verification
below is grep-shaped presence + the repo's own docs-wiring sweep; the
behavioral proof of the command is its first real charting run (follow-up,
not a gate here, matching SPEC-206's precedent).

## Verification

- `commands/wayfind.md` exists; greps find: `map.md`, `tickets/NN-`,
  `Blocked-by`, `frontier`, one-ticket-per-session, the four types, the
  no-self-grill contract line, the /kit:spec handoff.
- `docs/WORKFLOW.md` greps: wayfind paragraph in "Where work comes from";
  `Prototype (opt-in)` row in the phase table.
- `bash tests/test-docs-wiring.sh` and `bash tests/test-meta.sh` show no NEW
  failures vs master (8 README-count failures pre-exist).

## After state

A foggy multi-session effort gets a durable shared map in the same folder its
eventual ROADMAP will live in; sessions resume without re-deriving context;
decision tickets route to the kit's own grill/prototype/research machinery;
and the board carries one umbrella row instead of a ticket flood.
