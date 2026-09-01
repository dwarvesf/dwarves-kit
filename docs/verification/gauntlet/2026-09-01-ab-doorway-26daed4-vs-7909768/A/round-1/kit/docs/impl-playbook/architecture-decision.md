# Architecture decision: which shape for this piece of work

Distills Dan McKinley's "Choose Boring Technology" (the innovation-token budget) plus a GCP-style compute decision tree, adapted to personal-scale tooling.

## The heuristic
Default to boring: the option with well-understood failure modes (a cron job over a new daemon, Postgres/SQLite/DuckDB over a novel datastore, a CLI over a service). Spend an "innovation token" only where the new/exciting choice is the actual differentiator for this piece of work, not because it is more interesting to build.

## Shape decision tree
- Runs once, human-triggered, no state between runs: a CLI script.
- Runs on a schedule, no listener needed: cron/launchd plus a CLI script, not a daemon.
- Must react to external events in near-real-time, or hold in-memory state across requests: a daemon or long-running process.
- Must be reachable from the public internet, stateless per request: an edge function/Worker (Hono on Cloudflare Workers).
- Must hold connections or state across many concurrent clients (websockets, coordination): a Durable Object or a stateful service, not an edge function.
- Genuinely CPU- or perf-bound, not "might be slow someday": Go or Rust. Otherwise Python or TypeScript ship faster.

Pairs with a "minimum infra first" discipline: do not reach past the shape the actual requirement demands.

Before building any capability that is network-reachable or data-plane-shaped (metrics, logs, event archive, alerting, RAG, flags, email, browser fleet), check `cloudflare.md`'s "Before you build it" lookup first: a managed Cloudflare option often replaces the build entirely, and its placement ladder decides Cloudflare vs the Mini.

## Sources
- [Choose Boring Technology (Dan McKinley)](https://mcfunley.com/choose-boring-technology)
- [Choosing the right compute option in GCP: a decision tree](https://cloud.google.com/blog/products/gcp/choosing-the-right-compute-option-in-gcp-a-decision-tree) (2017; cited for the decision-tree shape, not the product names, which predate Cloud Run)

Verified: 2026-07-29.
