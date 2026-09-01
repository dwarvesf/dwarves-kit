---
title: "Omnigent (Databricks meta-harness) absorption: team guardrails, onboarding, cost policy vs the dwarves-kit team-collab design"
date: 2026-07-05
purpose: >
  Deep-read of omnigent-ai/omnigent (the Databricks-backed meta-harness that wraps
  Claude Code / Codex / Cursor with policy, sandbox, shared history, live collaboration,
  cost guardrails) cross-referenced against the dwarves-kit team-collaboration planning
  (research/2026-07-04-team-collab-workflow-proposal.md v2 + kit-modularity Decision C).
  Verdict tables per mechanism, absorption designs, and the deltas the team-collab
  proposal should pick up in v3. Everything build-shaped stays behind the
  named-second-user tripwire; this doc changes the DESIGN, not the build gate.
source_repos: [ops-toolkit, dwarves-kit]
refresh_cadence: none
next_review: null
status: active
---

# Omnigent absorption analysis

Sources: https://github.com/omnigent-ai/omnigent (fetched 2026-07-05) +
https://www.databricks.com/blog/introducing-omnigent-meta-harness-combine-control-and-share-your-agents.
Recon raw notes cached in session scratchpad (omnigent-{README,POLICIES,AGENT_YAML_SPEC,databricks,deploy-README,harness-bench}.md).

## Verdict summary (one line per source)

- **Omnigent**: SKIP wholesale (server-centric, it IS the L5 tier ADR-0022 fences out);
  ABSORB 4 mechanisms as design deltas into the team-collab proposal (policy-as-code
  stacking, cost-policy axis framing, TEAM.md onboarding checklist, fail-closed-hook
  evidence); PARK 2 (stateful sequence policies, per-user API budgets) with tripwires.
  Zero code ships now; the named-second-user tripwire still gates any build.

## Health signals

| Signal | Reading |
|---|---|
| Traction | 6,250 stars / 816 forks at ~3.5 weeks old (repo created 2026-06-11). Promoted launch, not organic aging. Alpha badge. |
| Bus factor | Top 5 contributors are ~735 of ~950+ contributions; core = Databricks MLflow maintainers (dbczumar, serena-ruan, TomeHirata). A Databricks team project under a neutral org. |
| License / seam | Apache-2.0 OSS core, genuinely standalone. Paid seam = managed "Omnigent on Databricks" (Mosaic AI Gateway governance, MLflow traces, Lakebase state) + per-token Foundation Model billing. |
| Install | Primary quickstart is curl\|sh (fails our security screen for direct adoption); uv/pip/brew alternatives exist. Python 3.12+, Node 22+, tmux, bubblewrap. Windows degraded. |
| Measurement story | No productivity or performance numbers anywhere. Blog is architecture-philosophy. Honest smoke-test provenance in databricks.md, and an honest self-audit that their capability matrix has "three disagreeing sources of truth". |
| Cadence / stability | 20+ commits/day peaks, weekly releases. P1 issues open: runner orphans tool callbacks and never self-recovers (#1026); a documented 24h zombie spin-loop pathology in the Claude hook (pre-#1782). |

## Architecture in one diagram (why wholesale is a skip)

```
   OMNIGENT                                          DWARVES-KIT TEAM DESIGN
   ────────                                          ───────────────────────
   FastAPI/WS SERVER + Postgres        vs            GIT (the only hub)
     │  sessions, transcripts, policy                  │  specs, attestations
     │  evaluate API, web UI, auth                     │  docs/runs/<rid>.md, CI re-check
     ▼                                                 ▼
   RUNNER on each dev machine                        kit installed per machine
     │  tmux-wrapped real CLI                          │  hooks = UX guardrail
     │  CC hooks POST every PreToolUse                 │  local ledger never syncs
     │  to server, FAIL-CLOSED                         │  branch protection = the block
```

Omnigent's every team feature (policy evaluate, shared history, co-drive, cost meter,
auth) hangs off an always-on server that stores transcripts and sits in the hot path of
every tool call. That is exactly the "no lock servers, no synced state,
no dashboards-as-service, no real-time presence" wall the 2026-07-04 proposal locks, and
the L5 tier PHILOSOPHY already routes to Nimbalyst/Conductor. Their own issue tracker
shows the ops tax of that hot path (fail-closed spin-loop, orphaned callbacks,
tunnel auth gaps). Skip the architecture; mine the mechanisms.

## Mechanism verdicts

| # | Mechanism (how it actually works) | Verdict | Why |
|---|---|---|---|
| 1 | **Server+runner meta-harness** (server coordinates, runner executes locally, transcripts in server Postgres) | **SKIP** | Violates git-only wall; is the fenced-out L5 tier. Their own P1 issues price the ops tax. |
| 2 | **Policy engine, 3 stacked levels** (server-wide admin > agent spec > session; ALLOW/DENY/ASK; session strictest-first; YAML-declared Python callables) | **ABSORB (design)** | The STACKING idea and the ASK verdict transfer; the evaluation server does not. Maps to a git-tracked repo policy file read by kit hooks (UX) + CI re-check (enforcement). Design delta D1 below. |
| 3 | **Stateful/contextual policies** (risk-score accrual per tool call; "after npm install, ASK before git push"; mutable session_state in the event dict) | **PARK** | Real idea, but needs per-session state our stateless hooks don't keep, and no incident has demanded it. Tripwire: a real incident where a SEQUENCE risk (install-then-push, fetch-then-exfil) slips past static guards; then design a session-state file for hooks. |
| 4 | **Cost guardrails** (`cost_budget` with ASK thresholds; `user_daily_cost_budget` per user per UTC day; hard cap = downgrade gate not hard stop, DENY only while on an expensive model, allow after `/model` down) | **ABSORB (framing) + PARK (build)** | Our axis (c) is a total blank; this fills the DESIGN. But their own docs admit the limit: subscription-OAuth sessions are invisible ("LLM calls invisible", no per-token cost), so budgets only meter API-key usage. Design delta D2; build parked, tripwire: a team member billing via API key. |
| 5 | **Team onboarding** (invite-only signup links, OIDC allowed_domains, `omnigent login <url>` + `omnigent host <url>` one-command join) | **SKIP mechanism, ABSORB checklist** | Server auth is moot for a git-hub design (identity = git). But the onboarding QUESTIONS it answers become the TEAM.md content spec, which our P1 row names and never specifies. Design delta D3. |
| 6 | **Shared history** (all session state in server DB, rendered anywhere) | **SKIP** | Banned by the wall. Our gate-level slice (attestations in docs/runs/ + stats reading git) already gives the team-visible part. Transcript-level sharing stays personal-machine. |
| 7 | **Live collaboration** (Share link to watch+chat, `attach` co-drive on YOUR machine, `run --fork` clones a session at a point) | **SKIP** | Real-time presence is banned at all phases. Fork-at-point is the one enviable verb; our equivalent already exists (branch + handoff doc + CI-checks-the-branch-not-the-machine means shipping someone else's branch works). |
| 8 | **Fail-closed hook enforcement** (every PreToolUse POSTs to server; unreachable server = DENY; documented 24h re-POST spin-loop pathology) | **ABSORB (evidence)** | Validates our opposite choice: hooks = advisory UX, CI + branch protection = the block. One line into proposal §6. Design delta D4. |
| 9 | **Cross-vendor review routing** (Polly: each diff reviewed by a model from a different vendor than the writer) | **NOTE only** | verify-claim (kit-foldin SG-06 claim-verifier) is already a multi-model skeptic panel. Add one NOTES line: default the panel to cross-model-with-the-writer when known. |
| 10 | **Subscription-OAuth governance** (docs tell teams to park a `claude setup-token` Max OAuth token in Modal secrets fanned to cloud sandboxes; same docs warn "verify the terms of service allow that pattern") | **ABSORB (governance line)** | The anti-pattern to ban explicitly: never fan a personal Max token to shared or cloud machines; each contributor's subscription auth stays on their machine. Design delta D3 (TEAM.md billing section). |
| 11 | **Sandbox + L7 egress** (bwrap/seatbelt per agent YAML, `enforce_sandbox` policy, egress credential injection) | **SKIP for kit** | Host-side concern, already covered personally by agentkernel; the kit stays bash-first with no OS-isolation machinery. Consumer repos that need it document it, the kit does not ship it. |

## Cross-reference: their offer vs our plan, per axis

| Axis | Omnigent's answer | Our v2 proposal | Gap verdict |
|---|---|---|---|
| (a) Guardrails/policy | Server-evaluated 3-level policy engine, fail-closed hooks | Attestation + CI re-check + branch protection; hooks demoted to UX | Ours is sound and cheaper; MISSING only a declarative policy artifact (what is allowed, readable in git). D1 fills it. |
| (b) Onboarding | Invite links, OIDC, one-command host join | "TEAM.md via /kit:adopt" named once, no content spec | Real gap. D3 specs TEAM.md. |
| (c) Cost policy | cost_budget / per-user daily / downgrade gate; only works API-key tier | NOTHING (axis blank everywhere) | Real gap in DESIGN; mostly moot in BUILD while everyone is on Max subscriptions. D2 writes the axis; build parked. |
| (d) Shared history | Server DB, everything shared by construction | Attestations + rejected-findings + boards + stats over git | Ours covers the team-decision slice deliberately; transcript sharing stays out. No change. |
| (e) Live collab | Share / co-drive / fork | Banned; async handoff via spec-as-unit + branch evidence | No change. Their co-drive ("their messages execute on YOUR machine") is a security surface we do not want. |

## Absorption designs (smallest concrete deliverable each)

All four land as ONE edit batch: a v3 revision of
`research/2026-07-04-team-collab-workflow-proposal.md` (new sections + table rows), so
the emitter (design text) ships with its reader (Han's pending review of that same doc).
No code, no new gates, tripwire untouched.

- **D1 policy-as-code stacking.** New §: a git-tracked `POLICY.md` (or `kit.toml
  [policy]` table, decide at build time) in the consumer repo: path fences ("contractors
  do not touch infra/"), guarded verbs (force-push, prod deploy), ASK-class actions.
  Three levels, strictest-first, mirroring Omnigent's stack but with git as the admin
  plane: repo policy (maintainer, in git) > mega/goal scope fence (orchestrator, in the
  scaffold) > session (the operator's own hooks). Kit hooks read it as UX; CI re-checks
  the mechanically checkable subset (e.g. diff touches a fenced path = fail). Explicit
  non-goal: no evaluation server, no fail-closed hot path.
- **D2 cost-policy axis.** New §: (1) state the subscription reality up front, Max-plan
  contractors have flat cost and invisible per-token spend, so the ONLY enforceable
  lever there is MODEL-TIER policy (SPEC-116 routing becomes team policy: which lanes
  may burn opus/xhigh); (2) for API-key actors, adopt Omnigent's per-user daily budget +
  ASK thresholds + downgrade-gate-not-hard-stop shape, enforced client-side by the kit
  statusline/hooks reading a budget line from TEAM.md; (3) governance: never fan a
  personal Max OAuth token to shared/cloud machines (their documented Modal-secret
  pattern is our named anti-pattern). Build parked, tripwire: first API-key-billed team
  member. **Han's stance 2026-07-05 (supersedes any issued-key-default reading):
  billing mode stays OPTIONAL per member, own subscription / own API key / company
  key all first-class, declared in TEAM.md; company key is an offer whose Console
  workspace limits come free, never a mandate. Cost visibility follows the mode;
  process visibility (attestations, actor=, boards) is mandatory and billing-agnostic.**
- **D3 TEAM.md content spec.** Turn the P1 one-liner into a spec: identity (git email =
  actor), roles table (who is maintainer/who may conduct megas), policy pointer (D1),
  billing declaration per member (Max subscription vs API key, feeds D2), machine
  bootstrap checklist (/kit:adopt + install verify + hooks smoke), review-window
  expectations, attest-for rules. One file, written by the maintainer, read on day one.
- **D4 failure-mode evidence.** Add one row to proposal §6: "Policy hot-path outage
  (Omnigent fail-closed spin-loop, 24h zombie re-POST)" -> "cannot happen here: hooks
  are advisory and local, the only blocking surfaces are git branch protection + CI,
  both already always-on infra someone else operates."

## Routing actions

1. This doc = the canonical record (you are reading it).
2. dwarves-kit `_meta/BACKLOG.md` parking lot: team-mode row gains a pointer to this
   doc; one NEW parked row for the cost-policy axis (tripwire: first API-key-billed
   member). Stateful-sequence-policy park rides the team-mode row's note rather than
   its own row (it is a sub-design of the same unpark).
3. kit-foldin NOTES ride-later: one line on SG-06 claim-verifier defaulting the skeptic
   panel cross-model to the writer.
4. The v3 proposal revision (D1-D4 as sections 8/9/10 + one §6 row) was APPLIED
   2026-07-05 on Han's go, with his billing correction baked in (optional per member);
   `research/2026-07-04-team-collab-workflow-proposal.md` is now v3.

## What we deliberately did not take

The meta-harness idea itself (one wrapper over CC/Codex/Cursor), the desktop app, the
web UI, managed sandboxes, OTel tracing plumbing, and the agent-as-YAML contract. All
of them assume the server. The kit's bet stays: git + bash + CI is enough below 3
operators, and when Dwarves genuinely outgrows that, the answer is evaluating a hosted
tier (Omnigent now joins Nimbalyst/Conductor on that shortlist) rather than rebuilding
one in bash.
