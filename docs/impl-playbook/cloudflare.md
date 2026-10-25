# Cloudflare implementation + placement rules

Read this BEFORE designing any new tool, service, or data flow, not only when deploying to Cloudflare. Two jobs: (1) placement, decide whether the piece belongs on Cloudflare, on a host you run yourself (a home server, an office machine, a private VPS), or nowhere; (2) implementation, the rules for building on Cloudflare once placed. The official catalog is at `https://developers.cloudflare.com/llms.txt` (each entry links a per-product `llms.txt`; fetch it before building on an unfamiliar product).

## Placement ladder: Cloudflare vs your own host

Cloudflare when the world must reach it; your own host when the data must not leave. Ask in order:

1. Does PII, per-person financial data, or a source document touch it, and your data policy keeps that off third-party platforms? Yes: your own host. Hard rule, stop.
2. Must it survive your own host being off, or be reachable by clients, team, phone, webhooks? Yes: Cloudflare.
3. Does it need local muscle (GPU, big disk, a logged-in browser, a local keychain or secret manager, a specific OS)? Yes: your own host.
4. Neither: leave it where the code already lives. Do not migrate for sport.

The seam pattern: **your own host produces, Cloudflare stores and serves.** The host holds secrets and touches raw data, pushes only derived numbers and neutral labels over HTTPS; CF makes them durable, queryable, reachable. Traffic flows host to CF, never CF into the host. Anything crossing to CF is counts, totals, neutral labels. The host stays a single point of failure by design (back it up); do not chase HA for internal jobs.

## Before you build it: the capability lookup

About to build or pay for one of these? Cloudflare already runs it. DEFAULT = reach for it; (trigger) = adopt only when the trigger is real.

| Need | Managed option |
|---|---|
| Public HTTP endpoint, API, site | Workers / Pages, DEFAULT |
| Multi-step job that must complete exactly once (payroll, recon, invoice chase) | Workflows, DEFAULT; never hand-roll the state machine |
| Per-key state, coordination, websockets, rate limits | Durable Objects, DEFAULT |
| Relational data for an edge app / config-cache / blobs | D1 / KV / R2, DEFAULT |
| Metrics from any producer, SQL out | Analytics Engine, DEFAULT for rolling-window metrics |
| Log digging on Workers | Workers Observability Query Builder; discipline: log structured JSON everywhere |
| Charts over CF product data | Custom Dashboards, free, prompt-to-build (does NOT read AE datasets) |
| LLM API-key traffic | AI Gateway, DEFAULT: spend dashboard + caching + fallback for a base-URL change (subscription-plan OAuth traffic stays direct) |
| Alert on CF-visible events (cert expiry, DDoS, Worker exceptions) | Notifications (your own monitor keeps daemon liveness) |
| Site analytics | Web Analytics, free, cookieless |
| External uptime checks on a public property | Health Checks |
| Event/telemetry archive, queryable | (new stream) Pipelines to R2 Iceberg; query with DuckDB or R2 SQL |
| High-volume independent messages | (real fan-out/burst only) Queues; low-volume ops flows stay on Workflows |
| Binary/container dependency on a public path | (isolate can't run it AND independence from your own host needed) Containers; else your own host |
| Reach an existing external Postgres/MySQL from a Worker | (that need exists) Hyperdrive |
| Email in/out of code | (beta pricing accepted) Email Service; inbound routing is free |
| Public form spam | Turnstile, free reCAPTCHA replacement |
| Internal/admin surface auth | Access (identity at the edge, JWT check in app) |
| Shared secrets across many Workers | (secret sprawl) Secrets Store, beta; your existing secret manager stays the source of truth |
| RAG over non-personal docs | (client/docs/demo) AI Search: upload bucket, get hybrid search + built-in MCP endpoint; personal or sensitive knowledge stays local |
| Glue inference / embeddings in a Worker | Workers AI / Vectorize |
| Hosted always-on agent, public | (not touching data that stays on your own host) Agents SDK; memory via Agent Memory (watch-status) |
| Governed MCP access for team agents | MCP Server Portals (Zero Trust, beta): one Access-authed audited endpoint |
| Unattended cloud browser | (your local machine asleep, or an unattended-cloud need) Browser Run; a local browser first |
| Untrusted generated code at the edge | Sandbox SDK / Dynamic Workers; run it in a local sandbox first |
| Feature flags | (client-facing rollout or non-engineer toggles) Flagship, beta; a KV read covers solo needs |
| Domain registration | (next renewal) Registrar: at-cost + free registry lock |
| AI crawler control / paid crawling | AI Crawl Control on content zones |
| Expose home/private services | Tunnel, DEFAULT (no inbound ports opened on your own host) |

Do not adopt: deprecated Firewall Rules (WAF custom rules instead), Version Management (Enterprise-gated), Pulumi (Terraform is the one IaC fallback), enterprise network products (Magic Transit/WAN, BYOIP, Interconnect, Load Balancing, Waiting Room) at this scale. Artifacts: status unclear, watch only.

## Compute/storage decision matrix
- Stateless request/response: Workers alone.
- Per-key strong consistency or coordination (websockets, counters, locks): add a Durable Object.
- High-read, low-consistency-need data (config, feature flags): KV. Not for counters/balances/inventory, it is eventually consistent with no monotonic reads.
- Relational/transactional data at small-to-medium scale: D1. No interactive transactions; `batch()` is the atomic unit (each batch runs as one transaction). One write primary per database; read replication is opt-in via the Sessions API (`withSession()`).
- Anything file-shaped: R2.
- Independent tasks that can fail/retry separately: Queues.
- Dependent multi-step processes needing durable state across days: Workflows, not a hand-rolled state machine.
- Full container runtime, longer execution, or non-JS/WASM language: Containers (Workers Paid), wired behind a Worker for routing; not the default compute.

## Limits and gotchas to design around
- CPU time and memory (128MB per isolate) are hard ceilings. Chunk synchronous loops, stream instead of buffering; `limits.cpu_ms` up to 5 min, or move work to a Queues consumer. Durable Objects get the same CPU budget; reach for them for state, not extra CPU.
- Analytics Engine: writes only via Worker binding (no direct HTTP ingest; Pipelines is the direct-HTTP option), retention ~3 months (dual-write to CSV/DuckDB or Pipelines for history), ingest eventually consistent (~1 min), invisible to custom Dashboards.
- Some networks filter egress to workers.dev IPs. If a daemon on your own host calls a Worker and the call fails there, give the endpoint a custom domain.
- Right after `wrangler deploy`, requests can return error 1042 for a minute; retry before diagnosing.
- Dashboard resources are per-account (for example personal vs organization): an empty product page usually means the wrong account picker selection, not a missing deployment.
- Beta products (Pipelines, R2 Data Catalog/SQL, Email, Flagship, VPC, Secrets Store, Sandbox): pricing unannounced. Fine for internal telemetry, not for client-facing SLAs.

## Configuration
- New projects: `wrangler.jsonc` (newer Wrangler features are JSON-gated). Existing `wrangler.toml` configs keep working; do not migrate them just for this.

## Secrets and environments
- Secrets via `wrangler secret put`, never `vars` or committed config.
- Once a Worker uses gradual deployments, use `wrangler versions secret put` / `versions secret delete`; the old command can silently miss the active version.
- Environments (dev/staging/prod) do not inherit bindings or vars; each is explicit.

## CI/CD
- Workers Builds (native git integration) for deploy-on-push. External CI (`cloudflare/wrangler-action`) when the pipeline needs steps Builds does not support.

## Observability
- Workers Logs on by default for new Workers; log structured JSON so Query Builder fields work. Add Tail Workers or Analytics Engine only once default logs stop being enough.

## Zero Trust / Access
- Gate internal, admin, or staff-only Workers behind Access. Public product-facing Workers stay public with app-level auth. Reserve Access for deploy-preview and admin surfaces.

## Sources
- Full catalog index: `curl -s https://developers.cloudflare.com/llms.txt`
- [Storage options overview](https://developers.cloudflare.com/workers/platform/storage-options/), [Workers platform limits](https://developers.cloudflare.com/workers/platform/limits/), [Architecting on Cloudflare](https://architectingoncloudflare.com/), [Workflows GA](https://blog.cloudflare.com/workflows-ga-production-ready-durable-execution/), [CI/CD overview](https://developers.cloudflare.com/workers/ci-cd/), [Wrangler configuration](https://developers.cloudflare.com/workers/wrangler/configuration/), [Secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [Secrets Store](https://developers.cloudflare.com/secrets-store/), [Containers/Sandbox GA changelog](https://developers.cloudflare.com/changelog/post/2026-04-13-containers-sandbox-ga/)

Verified: 2026-08-07.
