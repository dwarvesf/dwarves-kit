# DECISION BRIEF: factory legibility wave (five directions from the Mike's Software Factory read)

**Status:** DRAFT, rows ID-453..457 point here.
**Source:** operator direction 2026-07-31, second pass over the "Mike's Software Factory" pipeline image. First pass (mechanism comparison, 6/8 steps already covered) lives at ops-toolkit `research/2026-07-31-mikes-software-factory-absorption.md`.

The first pass judged the factory's mechanisms. This pass absorbs its LEGIBILITY: the factory reads aloud as a story a human absorbs in one pass. The kit is stronger machinery with a weaker story. Five directions follow, each with its smallest deliverable and its existing-row anchors.

## 1. The metaphor family (ID-453)

The factory's names work because they form ONE coherent workplace story with PEOPLE in it: a foreman, an interviewer, a night crew, an inspector, an owner's manual. The kit's plain-words program (ID-291/292/307, glossary shipped) fixed individual words but the stages stay abstract nouns (Shape/Build/Watch/Check/Learn). A human can picture an inspector; a human cannot picture a Watch stage.

**Design:** do not rename internals again. Add a narrative layer on the human-facing surfaces only: the README quickstart, `/kit:onboard`, and the MANUAL opening tell the workflow as one extended workshop metaphor, each stage introduced as a role (who) plus its artifact (what they hand you). Command names and registry vocabulary stay stable; the glossary maps story-name to real-name. Note ID-307 already renames grill to interview, which is exactly the factory's word: the plain-words program and the metaphor family converge, so the narrative pass should ride ID-307's remaining renames rather than fight them.

**Smallest deliverable:** one "workshop tour" section (about a page) in the onboarding surface, plus a two-column story-name table in the glossary.

## 2. Every ticket carries a picture (ID-454)

Operator reading of the factory's "draw the plan as a picture before it costs a night": the pre-build artifact, not the post-build proof. A spec or ticket that carries a diagram (components + arrows) or a prototype builds better than prose alone. Post-build visual proof is already ID-395 (MUST); this is its pre-build twin.

**Design:** the spec template gains a `## Picture` section: an ASCII diagram of the change (pieces + arrows), mandatory for full-lane, encouraged for normal. `/kit:spec-validate` adds a Tier-1 mechanical check (section present, non-empty) plus one lens question (does the picture agree with the task list). UI-shaped specs point the Picture section at a `/kit:prototype` run (ID-448, shipped) instead of ASCII. ASCII or box-drawing only, never mermaid, per the operator's standing visuals rule.

**Smallest deliverable:** spec template section + the Tier-1 check. The lens question and prototype routing follow.

## 3. Proof goes visual, and one dashboard over all runs (ID-455). Operator's top priority.

Current proof surfaces are markdown-heavy: proof-of-done tables, RUN_REPORT prose. The factory's tour video is the right instinct: a human previews a GIF in five seconds and a table in five minutes. Pieces already exist and do not compose: ID-395 (visual proof module, queued MUST), the per-mega HTML sign-off dashboard (harness-loop, shipped), the bench scoreboard (ID-421, executing), the Crew panel (ID-432, queued).

**Design, two legs:**

- **Proof contract goes visual-first.** Any behavioral change with a visible surface (CLI output, TUI, web UI) owes a capture (GIF, MP4, or freeze-PNG) next to its run table, produced by the ID-395 module; RUN_REPORT embeds its captures inline instead of linking. Headless or API changes keep the transcript form, honestly labelled.
- **One runs dashboard.** A static generator walks the estate (megagoal archives, proof-of-done docs, RUN_REPORTs, capture files) and renders a single HTML page of run cards: title, date, status, capture thumbnails, links to the report and receipts. Extends the shipped per-mega sign-off dashboard estate-wide; composes ID-421/432 later as panels. Static HTML, no daemon, regenerated on demand (minimum-infra rule).

**Smallest deliverable:** the generator over existing artifacts (it renders whatever proofs exist today, however sparse), so the visual-first contract has a place to land before it is enforced.

## 4. The owner's manual for the end user (ID-456)

The factory ends by handing the OWNER a manual written like they are ten. The kit's docs lane documents the code for the next builder; nothing is owed to the end user of the built thing. `/kit:explain` (on-demand ELI-style) and ID-434 (plain-language ledger renderer) are adjacent but neither is a ship artifact.

**Design:** user-facing products add a GUIDE.md owed at ship time: what this does, how to use it, what to do when it breaks, written in the ELI10 register (plain words, no internals, one page). The docs lane template carries the section; the ship checklist asks for it only when the change has an end user who is not the builder. Internal libraries and infra are exempt by that same test.

**Smallest deliverable:** GUIDE.md template + one ship-checklist line with the "has an end user" test.

## 5. The manager loop: backlog in, shipped PRs out (ID-457, umbrella)

Operator direction: when a row lands on the backlog, an orchestrator picks it up, runs the whole workflow, answers the interview itself with the best available model, builds, ships, and repeats until the queue drains. Retro suggestions feed the backlog, closing the loop.

Almost every organ exists:

```
            (Learn leg, shipped)                 (this umbrella)
  retro ──> learn drain ──> board promote ──┐
                                            ▼
                                   _meta/BACKLOG.md queued rows
                                            │  watcher: new auto-eligible row
                                            ▼
                                 orchestrate.sh queue (ADR-0030, shipped)
                                            │  per row, headless lane:
                                            ▼
                    self-grill ──> spec ──> spec-validate ──> execute ──> greenlight PR loop
                   (NEW, gap A)   (shipped)   (shipped)      (shipped)     (ID-401, queued)
                                            │
                                            ▼
                              merged PR + retro ──> back to the top
```

**The two real gaps:**

- **Gap A, self-grill.** ID-450 (shipped today) pins "the agent never answers its own questions", and that principle holds for interactive lanes. The manager reconciles, not violates: self-grill runs ONLY on rows tagged `auto-eligible`, uses the strongest available model, and writes every self-answered question as a decision row in the debt ledger, so nothing is answered silently: answers are auditable at weekend paydown, and a wrong call is a ledgered decision, not a hidden one.
- **Gap B, the watcher.** A small trigger (cron or board hook) that enqueues newly-queued `auto-eligible` rows into the orchestrate queue. No daemon beyond the existing cron surface.

**Guardrails (design decisions, flagged for the operator):** the loop drains the queue, it never invents its own work: retro suggestions still land in staging and only `board promote` (a human) makes them queued, which is the existing Learn-leg gate and the answer to "until there is nothing else to improve" being unbounded. Per-run budget cap and gated-final merge remain the defaults; full-auto merge is per-row opt-in. The kit's philosophy boundary is respected: the bounded lanes run in-session; the outer re-spawn lives in the queue runner, which ID-394 (Han direction, own the graph) already sanctions.

**Smallest deliverable:** the watcher (gap B) + self-grill as a grill mode flag (gap A), exercised on ONE real auto-eligible row end to end before widening. ID-394 (ordering graph) and ID-401 (greenlight loop) stay their own rows; this umbrella sequences them.

## Build order

1. ID-455 dashboard generator (top priority, renders existing artifacts day one)
2. ID-457 gap B watcher + gap A self-grill, one-row pilot
3. ID-454 spec Picture section
4. ID-453 workshop-tour narrative + ID-456 GUIDE.md template (doc passes, ride together)
