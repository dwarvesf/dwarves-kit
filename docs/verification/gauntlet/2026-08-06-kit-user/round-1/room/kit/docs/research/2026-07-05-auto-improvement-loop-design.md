---
title: "Read-plane feedback: the post-completion review mechanism (per-mega sign-off) + the auto-improvement loop (cross-mega backlog proposals)"
date: 2026-07-05
purpose: >
  Design for an auto-improvement loop that reads the harness ledger (the collected
  gate/proof/session/run data), interprets the aggregate signal, and emits candidate
  BACKLOG ITEMS , a retro one layer up from /kit:retro (which is per-run). It is the
  concrete realization of the Decision-E feedback loop at the WORK-ITEM level: the
  read-plane not just displaying stats but proposing what to fix next. Design only;
  needs the `stats` read engine (kit-modularity SG-02) to exist first. Drafted ahead
  of a follow-up mega.
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: none
next_review: null
status: active
---

# Auto-improvement loop: ledger -> proposals

## Problem

We now collect a lot of harness telemetry in the ledger (gate outcomes, proof records,
run durations, deviations, defect correlations, session events). Today that data is
READ for display (the `stats`/observatory lenses, the RUN_REPORT). Han's ask: close the
loop , turn the collected numbers into an AUTO-IMPROVEMENT loop that PROPOSES backlog
items. Like a retro, but a layer up: `/kit:retro` looks at ONE run; this looks across
MANY megas/sessions and asks "what pattern is the data telling us to fix?"

## Framing (event-sourcing, Decision E)

This is a READ-PLANE consumer that emits WORK. Ledger = source of truth (append-only);
this loop = a projection (`stats` aggregate) + an INTERPRETATION step + a WRITE to the
backlog. It never mutates the ledger; it recomputes from it. The output (backlog rows)
is itself just a proposal a human triages, not a second source of truth.

```
  ledger (SoT)            stats window-aggregate        LLM interpretation         backlog
  gate/proof/session  ->  gate-yield, deviation-rate, -> "gate X denies 40%    ->  queued rows
  run/duration events     defect-correlation,             over 6 megas -> the       (evidence
  (many megas)            anomalies, durations             spec template's Y          attached,
                                                           section is unclear"        dedup'd)
                                          ^                                              |
                                          └───────────── human triages ─────────────────┘
```

## Architecture (three stages, each cheap)

1. **Aggregate (deterministic).** Run the `stats` lenses over a WINDOW (multi-mega, e.g.
   last N megas / last 30 days), not one run. Pure projection, no LLM. Output: a compact
   signal table (each lens + its figure + the rids it covers). This is the grounding.
2. **Interpret (LLM, grounded).** One pass that turns each signal into a HYPOTHESIS with
   the cited number: "gate `spec-validate` denied 40% of `bearing`-design sub-goals over
   6 megas -> the spec template's Design block is unclear." The prompt gets ONLY the
   aggregate table + the backlog (for dedup); it must cite the lens + figure for every
   proposal (no ungrounded suggestions).
3. **Propose (deterministic write).** Emit each surviving hypothesis as a `queued`
   backlog row , with the evidence line (lens + figure + rids) and a suggested tag ,
   onto the right board. Dedup against existing rows FIRST (a proposal already open, or
   already dropped, is not re-emitted).

## The disciplines (the whole game)

- **Propose-only.** It writes `queued` rows a human triages; it NEVER auto-acts, never
  auto-scaffolds, never edits code. The human is the gate.
- **Cite the number.** Every proposal names the lens + the figure + the rids it rests on.
  An ungrounded "maybe improve X" is noise; the citation is what makes it actionable AND
  auditable (you can re-run the lens to check).
- **Dedup HARD.** Weekly re-runs must not re-propose the same thing. Dedup against BOTH
  open rows AND dropped/rejected rows (a rejected proposal reappearing every week is the
  failure mode that kills trust , same lesson as the loop-until-dry `seen`-set rule).
- **Cadence.** Weekly or on-demand (the `cc-intel` weekly-digest slot evolves into this).
  Not per-run , that is `/kit:retro`'s job; this is the cross-run layer.

## Where it fits / relation to existing pieces

- **Needs `stats`** (kit-modularity SG-02) , it is a `stats`-window consumer. Sequence
  AFTER kit-modularity.
- **`cc-intel`** (the weekly digest, moving to the kit) is the natural HOST , it already
  runs weekly and reads sessions; extend it from "digest" to "propose".
- **`/kit:retro`** stays , per-run retro is a different layer; this is the meta-retro over
  many runs. Do NOT merge them.
- **`skill-curator`** (cc-self-improve) is adjacent but different , it improves SKILLS from
  a memory ledger; this improves the HARNESS/PROCESS from the gate/run ledger. Same shape
  (ledger -> proposal), different target; could share the propose+dedup plumbing.
- **Hermes (Decision H)** , the proposals should surface as cards in the Air Hermes cockpit,
  so Han triages them where he already steers. This loop is a SOURCE for the H mirror.

## Companion: the post-completion review mechanism (per-mega sign-off)

Han's related ask (2026-07-05): a MECHANISM to review results easily AFTER a mega finishes ,
NOT reviewing one specific run. His over-test / measure-twice discipline gives high accuracy,
but sometimes he needs a GLANCEABLE surface to review a whole mega's groups + results before
sign-off. This is the SAME read-plane as the auto-improvement loop, one job over:

| | Review mechanism | Auto-improvement loop |
|---|---|---|
| Scope | ONE mega, at completion | MANY megas, on a cadence |
| Question | "did this pass? sign off." | "what should we fix next?" |
| Output | a sign-off gate + a review surface | queued backlog proposals |
| Both | read-plane projections over the ledger; persist nothing; recompute from the log | |

**Mechanism (fold into the mega lifecycle's convergence gate):** when a mega hits its terminus,
the loop already writes `RUN_REPORT.md`. ADD a step that auto-generates a REVIEW SURFACE , a
browsable dashboard rendered from the ledger + `stats` lenses + the PR/CI/gate states +
proof-of-done tables + the over-test COVERAGE-DELTAs , grouped per sub-goal, state encoded in
colour so what needs attention reads at a glance. It becomes the HUMAN SIGN-OFF GATE before
archive: mega completes -> RUN_REPORT + review-dashboard generated -> Han eyeballs the groups /
results and signs off -> archive. It is a GATE, not just a report.

- **Shape:** the Tier-A static-HTML dashboard (prototyped 2026-07-05 at the review-dashboard
  Artifact) , a file you open, no daemon. A `stats --html` export renders it from live data.
- **Live variant:** Decision H (the Hermes cockpit) surfaces the same for in-agent review.
- **Discipline:** read-only render, recomputable from the ledger (event-sourcing E). The
  dashboard is a projection, never a stored source of truth.
- **Sequence:** needs `stats` (kit-modularity SG-02) for the live render; the sign-off-gate
  wiring is a small addition to the mega convergence gate. Could ship WITH the auto-improvement
  mega (same read-plane plumbing) or as its own small step.

## Not decided here

The exact trigger thresholds (what figure warrants a proposal , a fixed cutoff vs the LLM's
judgment over the whole table); the dedup key (row-hash? semantic?); which board proposals
land on (the owning repo's, or a central "harness-improvement" board); whether stage 2 is one
LLM pass or a small panel; the cadence knob's home. Resolve when the mega drafts , after
kit-modularity ships `stats`. Likely a small own mega (or a `cc-intel` sub-goal), NOT folded
into kit-modularity.
