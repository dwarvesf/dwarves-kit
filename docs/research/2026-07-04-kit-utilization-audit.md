---
title: "dwarves-kit utilization audit: which commands and agents actually fire, and the wire-first plan"
date: 2026-07-04
purpose: >
  Evidence-based audit of all 30 kit commands and 24 agents against 96 real run ledgers,
  LAB_LOG, and megagoal RUN_REPORTs, answering Han's 2026-07-04 directive: "make sure we
  won't waste the cmd or agent we built in the kit; if they are not a fit, tell me and show
  me the plan to improve them." v2 same day: Han rejected the retire/merge framing; the plan
  is now WIRE-FIRST, a named workflow firing point for every dormant piece, retire reserved
  for a wire that proves dead after a real trial.
status: v2 wire-first; build under umbrella ID-273 (scaffold after ID-267 closes)
---

# Kit utilization audit (2026-07-04, v2 wire-first)

## 1. Headline

- **Commands: 13 of 30 demonstrably run** in the dominant mode; 2 SELF-RECORDED-ONLY, 9
  DORMANT, 6 utilities owing no footprint.
- **Agents: 9 of 24 have real dispatch evidence; 15 (62.5%) never fire in practice.**
- **One root cause:** the dominant mode is subagent-delegate mega, and the worker contract
  says "Run the lane, NOT `/kit:*`" (legitimate: cross-repo cwd-binding). Everything wired
  ONLY to `/kit:*` dispatch paths starves. The contract stays; the fix is giving every
  starved piece a firing point the dominant path actually reaches: the conductor's
  convergence gate, the worker's own loop triggers, the scaffold/framing phase, Han's gate
  windows, and the weekend batch.

## 2. The five firing surfaces (where wiring can land)

```
 plan time                run time (worker)          close time (conductor)
 ─────────                ─────────────────          ──────────────────────
 scaffold/framing         lane loop triggers         CONVERGENCE GATE
 (plan-for-mega-goal,     (verify-fail, deny,        (/kit:verify +
  /kit:mega decompose)     death-spiral, domain)      /kit:review-team + advisor)

              human surfaces                    batch surfaces
              ──────────────                    ──────────────
              Han's gate windows                weekend-debt-paydown
              (explain digest, quiz-gate)       (explain, quiz DEFERs, dispatch)
```

## 3. Command wiring map (the 11 non-active ones)

| Command | Wire to | The firing rule |
|---|---|---|
| verify | convergence gate | conductor runs `/kit:verify` on the assembled stack as the canonical close step (already ad-hoc'd today; make it the named wrapper). Same-repo bearing sub-goals may also call it post-build |
| devs-team | Design: bearing | a sub-goal marked `Design: bearing` gets the 5-lens devs-team pass on its spec's Design block BEFORE build; diff-keyed by the existing field, so it fires exactly where design risk lives |
| test-plan-review-team | Over-test: yes | an over-tested sub-goal gets the 5-lens test-design pass over its `## Test plan` before build; the over-test marking already exists in the template |
| ui-design | UI-surface condition | fires when the diff touches a UI surface AND a driver exists (agent-browser / playwright per plan-for-goal's self-verification-tools); else `skipped reason=no-ui-surface`. Han's repos with real UI: neko, properties, danny-studio, obs overlays |
| visual-team | rides ui-design | screenshot-based 5-lens review at the sub-goal's visual proof step (the template already demands 2-3 captures; this reviews them) |
| explain | gate windows + weekend batch | conductor auto-generates the `/kit:explain` literate digest for EVERY held gate PR, so Han's review window opens with it (a gate-throughput lever, not ceremony); weekend batch for merged-but-unexplained |
| quiz-gate | gate windows + DEFER queue | offered after the explain digest at interactive windows (never forced); autonomous ships record `DEFER`; weekend batch surfaces the deferred queue |
| debug | worker fix-loop escalation | same failure surviving 3+ verify-fix rounds escalates to `/kit:debug`'s systematic loop (the kit twin of the global break-the-death-spiral rule) |
| assign | board bridge | `/kit:mega` decompose calls assign per cockpit row it consumes; the single-goal runway becomes row -> `/kit:assign` -> goal file -> `/goal` |
| dispatch | weekend batch executor | fans out disjoint tiny paydown items as parallel VALIDATED specs (the same-repo no-DAG niche mega's serial stacks do not cover). WEAKEST wire: if the first two weekend batches never reach for it, retire it then, with usage data |
| next | composed into start | `start` invokes next's detection internally; composition, not deletion |

## 4. Agent wiring map (the 15 starved + task-verifier)

| Agent(s) | Wire to | The firing rule |
|---|---|---|
| api / frontend / infra / performance-reviewer | convergence gate | the gate runs `/kit:review-team` on the assembled stack; its EXISTING diff-keyed dispatch finally gets a caller that actually runs |
| acceptance-verifier, system-verifier | convergence gate | arrive via `/kit:verify` (their existing dispatch site, now invoked) |
| recheck-verifier | two triggers | (a) re-audits the convergence integration-verifier PASS (restores the ADR-0031 trust metric); (b) SAMPLED recheck of worker self-attested verify rows, fed by ID-270's `self_attested` flag: the lens finds them, recheck audits a sample |
| task-verifier | named in the worker contract | the global "verify with fresh-context subagents, not self-critique" rule gets its named agent: workers dispatch task-verifier for the fresh-context check instead of self-reading; execute's per-task spine unchanged |
| fix-agent | verify-fail pairing | on a task-verifier FAIL in a bearing sub-goal, dispatch fix-agent scoped to the failure (fresh context fixes; the context that wrote the bug does not also self-mark the fix PASS) |
| responding-to-review | gate-deny triage executor | on a human DENY, the worker dispatches it to verdict EVERY finding (Confirmed / Partly / Not-a-bug / Intended, file:line evidence) per the triage-first contract SG-05 lands, BEFORE any code change. The agent was built for exactly this and never had a trigger |
| research-architecture / features / pitfalls / stack | mega framing phase | on a brownfield repo, the decompose/framing step fans the quartet out ONCE in parallel; results feed ROADMAP Assumptions (front-loaded unknowns). Grill's S1/S2 signals can additionally trigger research-pitfalls solo |
| data-etl-worker, db-migration-worker | make execute's 2b-0 real | the audit observed execute "often degrades to a single continuous implementer"; the wiring fix is enforcing the existing 2b-0 dispatch: a domain-classified task dispatches the typed agent |
| advisor | three standing beats | see section 5, wired now |

## 5. Advisor: wired into the standing workflow (Han's item 4)

The 2026-07-04 live demo (P5 caught a CRITICAL metric-design flaw in a launch-ready
scaffold; P6 produced the actor= adoption) is now a standing beat, not a one-off:

1. **Plan time, pre-launch scaffold pass** (WIRED 2026-07-04, dotfiles: plan-for-mega-goal
   GUIDE + invocation template): before the pointer is handed to the human, dispatch
   advisor P5 (critique) + P6 (over-suggest) on the scaffold; apply CRITICAL/MAJOR fixes,
   route ride-laters to NOTES.
2. **Close time, convergence gate** (WIRED 2026-07-04 in OPERATE.md + the portable copy;
   the kit-command side + first-class `advisor` ledger row = SG-06 of
   gate-review-absorptions, launch-ready): P5 + P6 on the assembled stack, rows recorded
   (`mode=P5|P6 findings=N actor=`).
3. **Review time** (existing): review-team Step 2b dispatches P5 whenever review-team
   runs, which the convergence gate now guarantees at least once per mega.

## 6. Build routing

- **Wired TODAY (contracts I own):** OPERATE.md convergence-gate composition bullet +
  portable-copy mirror; plan-for-mega-goal pre-launch advisor beat + convergence-gate
  step naming advisor (dotfiles).
- **SG-06 (gate-review-absorptions, launch-ready):** advisor emit + mega.md convergence
  dispatch step.
- **ID-273 (kit-wiring mega, scaffold AFTER ID-267 closes; same kit files):** everything
  else above: /kit:verify + review-team composition into mega.md, the per-command firing
  rules (devs-team/bearing, tp-review-team/over-test, ui-design condition, explain/quiz
  gate-window + weekend batch, debug escalation, assign bridge, dispatch-in-weekend-batch),
  the agent triggers (recheck re-point + sampled self-attestation audit, task-verifier
  naming, fix-agent pairing, responding-to-review deny-trigger, research-quartet framing
  fan-out, execute 2b-0 enforcement), and front-loaded-skip legibility
  (`ran (front-loaded)` / reason= for grill/think/design).
- **Riders:** ID-271 verifier tiers (same files); ID-272 subagent panes (Phase A).

## 7. What is NOT proposed anymore

v1 proposed folding/retiring (reviewers 7->3, research 4->1, devs-team and
test-plan-review-team folded, dispatch/assign retired). Han rejected retire-first on
2026-07-04; every piece above now has a wire. The single retire candidate left standing
is `dispatch`, and only AFTER the weekend-batch wire gets two real trials and stays
unused. Everything else earns its keep or its usage data first.

Unchanged from v1: the worker lane-bypass contract stays (cwd-binding is real);
grill/think skip rates are front-load design, fixed by legibility not frequency;
utility commands owe no footprint; the ACTIVE set's emit grammars stay untouched.

Full evidence: two audit transcripts 2026-07-04 (commands: 30-file sweep x 96 ledgers;
agents: 24-file sweep x dispatch-site grep x LAB_LOG/RUN_REPORT mentions).
