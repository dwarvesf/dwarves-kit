# Fiddler AI Control Plane: feature scan for our dashboard

Date: 2026-07-25. Source: https://www.fiddler.ai/blog/ai-control-plane-coding-agents
plus https://www.fiddler.ai/control-plane (page copy + screenshot captions; video not
directly viewable, features reconstructed from surrounding copy). Operator direction:
"that's what I want for our dashboard... I want that feature list."

## What Fiddler ships (their 7 groups)

1. **Fleet intelligence**: executive KPIs in 30-day windows: cost with model breakdown,
   adoption (active developers vs seats), cost per PR and per commit, model usage across
   the fleet; spend by team/repo/model; latency/throughput/adoption trends.
2. **Explorer + trace panel**: filterable index of all agent sessions; click into a
   trace showing session details and attributes.
3. **Two-stream telemetry, unsampled**: agent-side OTel (session, planning context,
   files touched, PR info; Claude Code/Gemini CLI) joined end-to-end with gateway-side
   (requests, responses, tokens, latency, spend, verdicts; LiteLLM/AgentGateway);
   OTel export downstream.
4. **Cost attribution**: cost-per-PR, active-developer tracking, spend breakdowns.
5. **Inline guardrails**: Allow/Block/Redact verdicts <100ms on request AND response
   paths at the gateway; PII/PHI + secrets detectors; allowlist exceptions; agent-plan
   scoring ("Centor Models") before egress/commit.
6. **Audit trail with no gaps**: every verdict logged to traces with session + PR
   attribution.
7. **Real-time alerts** on policy violations; 100+ quality metrics (hallucination,
   toxicity, exposure) on the evaluations side.

## Mapping to the bench plane (have / build / defer)

| Fiddler group | Ours today | Call |
|---|---|---|
| Fleet intelligence | report.py per-mega; stats aggregates; no KPI home | BUILD: fleet home (KPI tiles + trends over ALL rids + bench facts, 30-day windows) |
| Explorer + trace | viewer/report need hand-picked rids | BUILD: filterable run index (repo, lane, type, model, date, conformance, misfire) -> click-through to replay/report |
| Two-stream telemetry | gate ledger = process stream; token/cost stream missing | BUILD = ID-420 config stamps + ID-423 trace spine; our second stream is CC transcripts/OTel joined by session id |
| Cost attribution | bench rows only | BUILD on the join; rid<->PR already appears in ship-gate reasons, formalize the dim |
| Inline guardrails | secret-guard PreToolUse hooks + kit gates (block/override + reasons), harness-plane not gateway-plane | DEFER the gateway (defer-don't-own); DO render existing verdicts as a stream view |
| Audit trail | append-only ledgers + expected-vs-actual conformance (stronger on process) | HAVE; add an exportable audit view |
| Real-time alerts | stats anomalies --propose (batch, propose-never-dispose) | PARTIAL: keep propose-first per N6; live alert only for run-stuck / gate-blocked |

**Positioning line**: Fiddler watches TRAFFIC (requests, tokens, verdicts at a gateway);
we watch PROCESS (which workflow, which gates, expected vs actual). Their moat is the
gateway; ours is the expectation model (WORKFLOW matrix + conformance). The dashboard
to build is their fleet-home + explorer UX over our process data, plus their telemetry
join; their guardrail gateway and NLP metric zoo stay theirs (N4/defer-don't-own; a
future integration point, not a rebuild).

## Dashboard feature list (ours, in build order)

1. Fleet home: KPI tiles (runs, worker minutes, cost, tokens, conformance rate, gates
   ran/skip/override, retries, misfire rate) over 30-day windows + trend sparklines.
2. Run explorer: one index over logs/runs/* with filters; each row -> replay (viewer)
   and report drill-down; misfire and low-conformance rows surfaced first.
3. Telemetry join: session-id join of transcripts (tokens, cost, duration) onto rids;
   unlocks cost-per-run, cost-per-PR, model split for REAL work (not just bench).
4. Verdict stream: gate + secret-guard events as a live allow/block/override feed with
   reasons; exportable audit view.
5. Alert hooks: run-stuck + gate-blocked notifications; everything else stays
   propose-first into the board staging buffer.

Consuming row: ID-425.
