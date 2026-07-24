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

## Second pass (same day): screenshots read + full docs index

Operator flagged "more in the sidebar / the video". Video id is JS-injected (not in
static HTML, two extraction attempts); the three blog screenshots were downloaded and
read directly, and docs.fiddler.ai/llms.txt enumerates the product surfaces the demo's
sidebar navigates. New material beyond the first pass:

**From the screenshots:**
- Live event stream line format: `time · team · agent-tool · tokens · verdict chip
  (OK / REDACT)`, verdict-per-event, not per-session.
- Agent-plan analysis: the plan rendered as a flow (`read public issue -> read
  /private/repo -> open PR to fork`) with a policy tag (`dlp cross-repo · scope:
  out-of-allow`) and an inline BLOCK verdict. This is plan-level, pre-commit scoring.
- **MCP and PR activity view**: which MCP servers and tools agents call, sessions
  traced to the PR they touched. (Their tagline: every prompt, every response, every
  tool call, one console, OTel export.)
- Continuous-monitoring pillar names span-level depth: sessions, traces, spans, tool
  calls, drift detection, root-cause analysis. Governance pillar: RBAC, approvals,
  audit trails, SR 11-7, HIPAA, EU AI Act.
- GTM framing stat-cards (75% of new Google code AI-generated; AI-assisted commits
  leak secrets 2x; 24K secrets exposed in MCP configs in a year): the fear-metric
  pattern our trust page can answer with process evidence instead.

**The sidebar (from the docs index):** Trace Explorer (filter/search every span) ·
Dashboards (create/edit/zoom/share) · Monitoring Charts + Metric Cards · Alerts
(rules, template-based via YAML, drift, integrity, traffic, statistics) · Custom
Metrics (FQL over span attributes) · Enrichments + LLM-based metrics · Embedding
visualizations (3D) · Experiments/Evals SDK (evaluator rules + downsampling) ·
Segments · RCA events table · Guardrails (safety/PII/faithfulness/secrets) · Gateway
config (LiteLLM, AgentGateway, Kong) · Model/project onboarding.

**Additions to our build list (absorbed into ID-425):**
- Run explorer confirmed as their Trace Explorer analogue; add SEGMENTS (saved filter
  groups by repo/lane/type/model) to it.
- **Tool-call activity view** (their MCP-and-PR view): which tools/MCP servers a
  session called, traced to the PR, needs the transcript join (ID-420/423), high
  value for the trust page.
- Failure-fingerprint table as our RCA events analogue (data already exists in bench
  rows + verifier records).
- Template-based alerts (YAML) fits the plain-files principle when alerts land.
- Custom metrics over span attributes: our stats DuckDB lens already is this; expose
  it in the dashboard rather than inventing an FQL.
- DEFER: embedding visualizations, enrichment zoo, RBAC/compliance certifications
  (team-mode/enterprise tier concerns, ID-414/417 territory).
