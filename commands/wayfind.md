---
description: "Plan a chunk of work too big for one agent session as a shared decision map: map.md + typed decision tickets in the mega-goal folder, resolved one per session through the kit's own grill/prototype/research machinery, until nothing is left to decide. Then hand off to /kit:spec or a ROADMAP, never straight to execute."
disable-model-invocation: true
---

You are a wayfinder. A loose idea has arrived, too big for one session and wrapped in fog: the way from here to the **destination** is not visible yet. Your job is to find the way, not to charge at the destination: chart a shared **map** of **decision tickets** (questions whose resolution is a decision, not build slices), then resolve them one at a time until the way is clear.

Ported from mattpocock/skills `wayfinder` (MIT), re-based onto files + the kit board (SPEC-207; design: docs/research/2026-07-31-mattpocock-trio-adoption.md §1+§4). Tracker-native storage is deliberately NOT this command (parked; SPEC-207 Out of scope).

**Router check first (upstream's admitted failure mode is over-reach).** Wayfind is slower and denser than a single grill. A well-scoped feature belongs on `/kit:grill` + `/kit:spec`; a decomposable build with a clear route belongs on `/kit:mega`. Reach for wayfind only when the OPEN QUESTIONS outnumber the stateable ones.

## Plan, don't do

Every ticket resolves a decision; the map is done when nothing is left to decide before someone goes and does the thing. The pull to just do the work is usually the signal you have reached the edge of the map: time to hand off. The map's `## Notes` can override this per effort; absent that, produce decisions, not deliverables.

## Where things live

```
_meta/megagoals/<slug>/
  map.md                    # the map: the low-res index, loaded once per session
  tickets/NN-<slug>.md      # one decision ticket per file
  ROADMAP.md                # (later) the do-half; written at graduation, not by wayfind
```

Co-location is deliberate: wayfind is the decide-half of the folder whose do-half is the mega-goal ROADMAP (ADR-0032). Graduation happens in place. The board (SPEC-055) carries **ONE umbrella row per map**; tickets are NEVER duplicated as board rows.

### map.md

The map is an **index, not a store**: a decision lives in exactly one place, its ticket file; the map only gists it and points. Open tickets are not listed in the body; they are found by scanning `tickets/` (the frontier query below).

```markdown
# Map: <name>

## Destination
<what reaching the end looks like: the spec, decision, or change this effort is finding its way to. One or two lines; every session orients to it before choosing a ticket.>

## Notes
<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far
- [NN-<slug>] <closed ticket title>: <one-line gist of the answer>

## Not yet specified
<!-- fog of war: in-scope questions not yet phrasable precisely; graduates as the frontier advances -->

## Out of scope
<!-- work ruled beyond the destination; closed, never graduates -->
```

### Tickets

`tickets/NN-<slug>.md`, body sized to one agent session:

```markdown
Type: research | prototype | grilling | task
Status: open | claimed | closed
Claimed-by: <who, when claimed>
Blocked-by: [NN, NN]   # empty = unblocked

## Question
<the decision or investigation this ticket resolves>

## Answer
<written at resolution; assets linked, never pasted in>
```

A session **claims** a ticket by setting `Status: claimed` + `Claimed-by:` FIRST, before any work; concurrent sessions skip claimed tickets. A ticket is **unblocked** when every `Blocked-by` ticket is closed. The **frontier** = open, unblocked, unclaimed tickets: the edge of the known. **Refer to tickets by their title in everything the human reads**, never by a wall of bare numbers; the `NN` rides inside the name.

## Ticket types (each routes to machinery the kit already owns)

Every ticket is **HITL** (worked with a human who speaks for themselves) or **AFK** (agent alone). A HITL ticket only resolves through that live exchange; **the agent never stands in for the human's side of it. A grilling agent that answers its own questions has broken this contract.**

- **research** (AFK): surface a fact a decision waits on, from docs, third-party APIs, or knowledge outside the working directory. Resolved by a research subagent (the research type loop: frame -> sweep -> adversarially verify -> cited report), findings on a throwaway `research/<name>` branch with a context pointer from the ticket. The ONE exception to one-ticket-per-session: research tickets fan out in parallel.
- **prototype** (HITL): raise the fidelity of the discussion with a cheap concrete artifact to react to, via `/kit:prototype`. The ticket's answer records the verdict + the `prototype/<name>` branch pointer.
- **grilling** (HITL, the default): conversation via `/kit:grill`'s one-question-at-a-time discipline, aimed at THIS ticket's question.
- **task** (HITL or AFK): manual work that must happen before a decision CAN be made (sign up for the service so its API can be judged, provision access, move data so its shape is visible). The one type that does rather than decides; it earns its place by unblocking a decision, never by delivering the destination. The answer records what was done + resulting facts later tickets depend on (credential location, URLs, row counts). Sized beyond a ticket, it is not a ticket: it is the destination's build showing up early; hand it to the normal lane ladder.

## Fog of war

Chart only what you can see. **Fog or ticket? The test is whether you can state the question precisely NOW, not whether you can answer it now.** Sharp question (even if blocked) -> ticket. Not phrasable that sharply -> one loose entry in `## Not yet specified`; never pre-slice fog into ticket-sized pieces (one patch may graduate into several tickets, or none). Resolving tickets clears fog; graduate what became stateable into fresh tickets and delete the graduated fog line.

`## Out of scope` is different: work beyond the destination, ruled out consciously. It never graduates (the frontier stops at the destination). A live ticket exposed as beyond the destination gets **closed** with one gist line in Out of scope, and stays out of Decisions so far (that section records the route actually walked).

## Mode 1: chart the map

Invoked with a loose idea. Charting is one session's work and hand-resolves nothing.

1. **Name the destination** via `/kit:grill` (+ domain modeling where it helps). The destination fixes the scope, so it is settled first.
2. **Map the frontier**: grill again, breadth-first, fanning across the whole space for the open decisions and first takeable steps. **No fog surfaced = no map needed**: the journey fits one session; stop and route to `/kit:grill` + `/kit:spec` instead.
3. **Write map.md** (Destination + Notes filled, Decisions empty, fog sketched into Not yet specified) and **add the ONE umbrella board row** for the effort.
4. **Create the tickets you can state now**, then wire `Blocked-by` in a second pass (tickets need numbers before they can reference each other). Everything else stays fog.
5. **Fire the research subagents** for every research ticket, in parallel, each capturing to its `research/<name>` branch.
6. Stop. Report the map path, the frontier, and the running research.

## Mode 2: work the map

Invoked with a map (path or slug); a named ticket is optional.

1. Load **map.md only** (low-res). Do not read every ticket body.
2. Pick the ticket: the named one, else the first frontier ticket. **Claim it before any work.**
3. Resolve it via its type's machinery above, zooming into related/closed ticket bodies on demand; consult the skills `## Notes` names.
4. Record: write `## Answer`, set `Status: closed`, append the one-line gist to `## Decisions so far`.
5. Tend the map: create newly-surfaced tickets (create-then-wire), graduate fog the answer sharpened, close mis-scoped tickets into Out of scope, update or drop tickets the decision invalidated.
6. Stop. **Never resolve more than one ticket per session** (research fan-out excepted). Expect concurrent sessions on other tickets; claimed means skip.

## Exit: the map is clear

Nothing left to decide: hand off, never straight to execute.

- Single bounded feature -> `/kit:spec`; the map's Decisions so far becomes the spec's Context.
- A build needing ordered sub-goals -> write `ROADMAP.md` beside map.md and run it as a mega-goal (`/kit:mega`, ADR-0032); the map stays as the decision record.
- Flip the umbrella board row to reflect the handoff; the map goes read-only.

Record the beat when a wayfind session ends: `bash lib/gate/gate-ledger.sh record <rid> Wayfind ran "mode=<chart|work> ticket=<NN|-> frontier=<N-remaining>"` (rid = the umbrella effort's branch when one exists, else the session's own).
