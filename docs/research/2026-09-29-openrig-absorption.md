---
title: "OpenRig absorption: light default, whole-spec dispatch, and the kit's verbosity bill"
date: 2026-09-29
purpose: >
  Absorption pass over OpenRig (mvschwarz/openrig, openrig.dev) and its author's talk
  "I Run an AI Civilization in Herdr" against dwarves-kit. Three parallel reads: the repo
  and docs, the video transcript, and a token-cost plus onboarding audit of the kit.
  Tests the operator's hypothesis that the kit over-specifies work that current models
  implement fine unaided. Records the verdict per mechanism, the designs, and the one
  bug found on the way (post-compact re-inject never fires).
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: none
next_review: null
status: active
---

# OpenRig absorption

Method: three fresh-context readers on 2026-09-29 (OpenRig repo and docs, the author's
video transcript, a read-only kit audit). Load-bearing quotes and kit numbers were
re-checked by the lead against a local clone and the kit ledgers. M = measured,
E = estimated.

## Verdict

| Source | One line | Verdict |
|---|---|---|
| OpenRig runtime (tmux daemon, seats/pods/rigs, queue, TUI) | multi-agent runtime over Claude Code and Codex sessions | SKIP the runtime; Orca plus the board already cover it, and its issues show brittle TUI detection |
| OpenRig SDLC conventions (markdown, `docs/reference/`) | light default, heavy only when a human assigns it, whole spec per builder | ABSORB five mechanisms (D1 to D5) |
| The talk | names the pathology: agents "reinventing bureaucracy", checks that need checks | ABSORB the ceremony-versus-progress signal (D5); the rest is anecdote |
| Operator hypothesis: "the kit is too verbose for future models" | tested against the kit ledgers | CONFIRMED for the middle of the pipeline, REFUTED for its edges (table below) |

## The shape difference

```
dwarves-kit, full lane today (medium feature, ~56 dispatches, E)

 think -> devs-team(5)+advisor -> research(4) -> spec(~27 sections) -> validate(7 in 1)
   -> test-plan -> test-plan-review(6 x up to 3 rounds) -> test-write
   -> per task: [persona meta-agent -> worker -> task-verifier -> opus recheck -> fix x2]
   -> integration-verifier + recheck -> review-team(3+advisor+domain+validators, 2 rounds)
   -> docs-verifier -> ship-gate -> wrap(19k-token prompt)

OpenRig default (Part A, P1)

 intent + mini-requirements + proof contract (SPEC.md)
   -> ONE builder, whole spec, one sustained run, "navigate the implementation yourself"
   -> failing-test-first, frozen candidate, proof drop
   -> review once per wave, two non-writer reviewers
 Heavier rungs (research P2, adversarial P3, blind design P4) only by named reason.
```

## Operator hypothesis, tested

| Kit stage | Evidence | Reading |
|---|---|---|
| Fresh-context spec validator | 19 of 35 validate outcomes caught a problem (M, ledger) | KEEP, load-bearing |
| Ship-gate / proof-of-done | 15 of 46 ship outcomes caught a problem; 128 proof-gate blocks since July (M) | KEEP the gate; 108 overrides in 4.5 days, ~70% docs/config/inert (M), so the diff classifier over-fires |
| Security review lens | caught a HIGH key-persist leak the panel, reviewer and verifier missed (`commands/battery.md:68-73`) | KEEP |
| Per-task recheck-verifier (Opus) | 29 `Re-audit: PASS` records, 0 `Re-audit: FAIL` across kit and ops-toolkit docs (M, lead re-count) | CUT to sampled or opt-in; it has had its real trial |
| Per-task worker + task-verifier split | OpenRig: "Detailed sequencing instructions were scaffolding when models were weak; today they are a cage" (`docs/reference/wave-sdlc.md:33-35`) | CUT to whole-spec dispatch by default |
| Persona meta-agent per task | extra dispatch to write a preamble (`commands/execute.md:151-166`) | CUT |
| Test-plan review team before code exists | 6 lenses up to 3 rounds; test-write refuses without SOLID, so it gates in practice (`commands/test-plan-review-team.md:53,97`) | Move to P3 only |
| Full-lane think/reflect/design phases | overridden 17/11/11/10 times across ~108 ledgers (M) | The escalation rule over-fires (next table) |
| Always-loaded context | ~10.5k tokens per session, ~4.5k of it the 18KB AGENTS.md copy in adopted repos (M) | Shrink the copy to a pointer |

Conclusion: stronger models make the MIDDLE of the pipeline (breakdown, per-task
verification, persona scaffolding) redundant. They do not make the EDGES redundant. A
model that implements well still misreads intent and still ships unsafe diffs. Spend
tokens at the edges (intent in, proof out), not in between.

## Mechanism verdicts

| # | OpenRig mechanism | Kit today | Verdict |
|---|---|---|---|
| M1 | Part A default, Part B only when assigned: "You may not select Part B for yourself" (`sdlc-conventions.md:23`) | "When in doubt between two lanes, take the heavier one" (`docs/WORKFLOW.md:62`); regex keywords auto-escalate ("token count column" hits security) | ABSORB, D1 |
| M2 | Planning dial P0 to P4; P2 only for an unclosable unknown, P3 only for an author-blind failure mode; "importance is not the test" (`planning-dial.md:35-44`) | lanes keyed on topic keywords (auth, provider, migration) | ABSORB the discriminator, D2 |
| M3 | Whole spec per builder; brief = goal, acceptance, routes, territory, self-navigation grant; smaller chunks need a named reason (`wave-sdlc.md:22-43`) | per-task worker, verifier, recheck, persona | ABSORB, D3 |
| M4 | Refocus: re-deliver the intent chain after compaction (talk, 16:46-19:59) | `post-compact-reinject.sh` re-injects the spec PATH only, and never fires (bug below) | ABSORB, D4, built this session |
| M5 | Ceremony-versus-progress monitoring (talk, 21:51-23:45) and CONTEXT-GAP / JUDGMENT-GAP tag on review misses (`wave-sdlc.md`) | ledger records outcomes; no ratio lens; no miss taxonomy | ABSORB, D5 |
| M6 | PARTIAL slice protocol: revise the claim down, name what did not ship with file:line, route the gap; building the gap inside the slice is scope creep | only "worker fails to complete" (`commands/execute.md:499`) | ABSORB as one line inside D3's rewrite, not a separate addition |
| M7 | Wave review: two non-writer reviewers once per wave | review-team per branch, 3+ lenses + advisor + validators + round two | PARK. Unpark when `/kit:dispatch` runs 3+ parallel specs in one week |
| M8 | Mission install (5 layers, pieces cited by path and hash, agent derives its own delta) | handoff skill + context-readiness hook | PARK. Unpark on a recorded cold-pickup failure (a handoff whose receiver acted on a stale premise) |
| M9 | Context gate: only context-holders author research prompts or adversarial passes | the kit's validators are fresh-context by design | SKIP as a rule. Both are right for different jobs: fresh context verifies claims, a context-holder judges goal fit. The kit's intent-in edge (think/grill) is already the context-holder |
| M10 | Recursive proof loop, "doghouse to moonbase" | covered: `.claude/memory/megagoal-proof-ceremony-rot.md` (ops-toolkit) records the same rot | SKIP, covered |
| M11 | Seats, pods, rigs, durable queue, tmux messaging | Orca orchestration ships the primitives but has zero use (see Operator review) | SKIP the OpenRig runtime; ABSORB the mechanism on Orca, D7. OpenRig issues #79, #86, #81, #64, #48 are all provider-TUI detection drift |
| M12 | "Mind viruses" / epidemiology rig | `kit:memory-tidy` | SKIP, unfalsifiable anecdote |

On onboarding, a challenge to the premise: OpenRig does not have little structure. It
writes eight machine surfaces on install (tmux config, `~/.openrig`, two skill dirs,
`.claude/settings.local.json` hooks, `.mcp.json`, codex config), and its conventions doc
alone is 23.7KB. It FEELS light because the default path asks for about five concepts
and one bounded outcome, and everything heavy is a menu the human opts into. The kit
asks for about 18 concepts and 10 commands before a first normal-lane ship. The lesson
is the default, not the size.

## Designs (smallest deliverable each)

**D1. Light default, heavy by assignment.** Replace `docs/WORKFLOW.md:62` with: default
normal; the agent may PROPOSE full in one sentence and continues on normal until the
operator assigns it. `lane-classify.sh` keyword hits become a suggestion printed to the
operator, except the hard-gate diff paths the ship-gate already checks (auth, migrations,
secrets), which stay mandatory at ship. Over-test. Negative control: "add token count
column" classifies normal; a diff touching a migration still blocks at ship without the
full-lane records.

**D2. Discriminator, not topic.** Research agents (4) run only when the spec names an
unresolved external unknown; the test-plan review team runs only when the spec names an
author-blind failure mode. Both become one `Dial:` line in the spec header with a reason.
The fresh validator stays on every spec (19/35 catch rate). Negative control: a spec with
`Dial: P1` dispatches zero research agents; `Dial: P2` without a named unknown fails
spec-validate.

**D3. Whole-spec dispatch.** `/kit:execute` default: one builder gets the whole spec as a
brief (goal, acceptance, routes, territory, "navigate the implementation yourself, ask
when stuck"). Per-task split only with a named reason on the brief. Drop the persona
meta-agent dispatch. Verification runs once at the end (integration + acceptance), not per
task. Recheck-verifier becomes sampled (1 in N, or on self-attested rows per the wire-first
plan). Fold the PARTIAL rule (M6) in. Target: `commands/execute.md` shrinks, not grows.
Estimated effect for a medium feature: ~56 dispatches to ~15 (E, to be measured by D5).
Over-test. Negative control: a seeded spec with one unmeetable acceptance criterion must
still end FAIL with the criterion named.

**D4. Refocus after compaction.** Built this session (branch `fix/compact-reinject-event`):
wire `post-compact-reinject.sh` to an event that actually fires after compaction, and
re-inject the active spec's Problem paragraph next to its path. This also closes SPEC-334
open question 6.

**D5. Ceremony ratio lens.** From data the ledgers and cost records already hold: per run,
count dispatches and ceremony tokens against diff lines shipped and gates that caught
something. A `kit:stats` anomaly fires when ceremony share passes a threshold with zero
catches. Also add a one-word `gap:` field (context or judgment) to escape records, so D2's
dial gets tuned by misses, not taste. Emitter ships with its reader: the lens lands in the
same change as the field. This is the number that proves or refutes D1 to D3.

**D6. Onboarding to first value.** `/kit:adopt` writes a ~1KB CLAUDE.md pointer to the
installed AGENTS.md instead of an 18KB copy (also ends the drift: trading's copy is 322
lines behind). First-run tour teaches two concepts (lane, proof) and lists the rest as an
opt-in menu. Measure with the existing gauntlet onboarding campaign
(`docs/verification/gauntlet/2026-09-01-onboarding-campaign/`): turns and tokens to a
first shipped PR, before and after.

## Prior decisions this touches

- 2026-07-04 kit utilization audit (`docs/research/2026-07-04-kit-utilization-audit.md`):
  the operator rejected retire/merge in favor of wire-first, "retire reserved for a wire
  that proves dead after a real trial". The recheck-verifier has had that trial (29 PASS,
  0 FAIL). D3 samples it rather than deleting it, which stays inside that rule.
- SPEC-334 open question 6 answered by D4 with transcript evidence (4 compactions, 0
  re-injects).

## Security screens

No OpenRig code was installed or run; the repo was cloned read-only. Its install is
`npm install -g @openrig/cli` (not curl|bash) but it writes hooks into
`.claude/settings.local.json` and `~/.codex/config.toml` with no preview and no rollback
guarantee (its own README). Any future trial runs in a throwaway HOME. No secrets involved.

## Unconfirmed

- OpenRig publishes no token-cost or quality numbers; every speed claim in the talk
  ("50 times faster", "runs much longer") is self-reported.
- Kit dispatch counts per stage are estimates from command prompts, not measured runs.
  D5 exists to replace them with measurements.
- OpenRig docs not read: `product-management-pass.md`, most of `product-journey-sdlc.md`,
  `skills/_canonical/`.

## Operator review (same day)

The operator named two things this record undervalued: work managed by agent status,
and configuration flexibility. Both hold up on re-check. M11 was marked SKIP as
"covered by Orca", and that claim was covered on paper only.

| Claim re-checked | Evidence | Revised reading |
|---|---|---|
| Orca covers status-driven orchestration | Orca ships `orchestration task-create/task-list/task-update`, DAGs, `dispatch`, supervised `worker-start`, `gate-create`, a mailbox, `worktree ps`. `orca orchestration run-list` shows no run; no kit or ops-toolkit code calls `orca orchestration` (M) | Primitives present, unused. The kit dispatches in-process subagents that no status surface can see |
| The kit is as configurable as OpenRig | `kit.toml` has 20 sections of knobs (gates, modules, per-command settings); lanes and phases live in `docs/WORKFLOW.md` and command prose, not data (M) | OpenRig composes the team (RigSpec: pods, members, runtime, model, startup files, culture file) and the pipeline (a per-mission component menu). The kit tunes one fixed pipeline |

What OpenRig does that the kit lacks (`docs/reference/agent-state-taxonomy.md`):

```
 queue row (one owner, append-only transitions)      seat (stable address, e.g. impl@dev)
            \                                            /
             +-------- read-time join, never stored ----+
                              |
     PARKED      = seat idle or blocked on input  AND  it owns an open row   (dropped baton)
     HELD        = deliberate hold with a named owner and an armed wake
     DONE-UNSEEN = finished, nobody consumed the result
                              |
            orchestrator reads the view as its "GPS": next ready row, stuck seats
```

State has three separate axes (session present or absent, activity working or idle or
unknown, resumability), and "unknown" is an honest value, never guessed.

**D7. Work by agent status, on Orca.** Map a mega sub-goal or board row to an Orca task,
dispatch each to a supervised Orca worker, and derive PARKED, HELD, and DONE-UNSEEN from
task status joined with worker activity. The orchestrator asks the view for the next
ready task instead of holding the sequence in context. Orca, not OpenRig, because it is
already installed, the operator drives it from the phone, and OpenRig's weak spot is
exactly its status detection. Smallest deliverable: a `--backend orca` path for one mega
run, trialed on a real mega. Measures: stranded work caught, orchestrator context size,
operator interventions. Over-test. Negative control: stop a worker mid-task; the view
must show PARKED within one poll.

**D8. Config as composition.** Two steps. First, lanes become data: `[lane.<name>]
phases = [...]` in `kit.toml`, shipped defaults equal today's lanes, a repo or mission
may override. D1 and D2 then become data changes, not prose rewrites. Second, after D7
proves the worker path, `[role.<name>]` (model, runtime, startup reading list, skills)
gives dispatch a seat concept. Onboarding then starts from a starter template (as
OpenRig's `first-project` does), not a concept tour. Over-test. Negative control: a repo
override that drops `review` from `normal` must show the phase skipped in the ledger, and
the ship-gate hard paths must still block.

Caveat: OpenRig publishes no measurement that status-driven orchestration beats a single
orchestrator. Its full RigSpec example is large, and flexibility grows the YAML surface
the operator maintains. D7 trials on one mega before anything is rebuilt around it.

Revised build order: D4 shipped (kit #810). D5, then D7 trial and D8 step one in
parallel, then D1 + D2 as data on D8, then D3, then D6 on starter templates.

## Build order (original, superseded above)

D4 now (in flight). D5 next, because it produces the baseline number. Then D1 + D2 (one
change to classification and spec header), then D3 (the big token cut, measured by D5),
then D6. D1 to D3 together reverse the kit's "when in doubt, heavier" posture, so they
wait for the operator's go on direction; on go they become one mega with D5 as its first
sub-goal.
