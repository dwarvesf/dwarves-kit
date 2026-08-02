# Cloudflare implementation rules

Distills Cloudflare's own storage-options and platform-limits docs, the Architecting on Cloudflare book, and the Workflows GA announcement.

## Compute/storage decision matrix
- Stateless request/response: Workers alone.
- Per-key strong consistency or coordination (websockets, counters, locks): add a Durable Object.
- High-read, low-consistency-need data (config, feature flags): KV. Not for counters/balances/inventory, it is eventually consistent with no monotonic reads.
- Relational/transactional data at small-to-medium scale: D1. No interactive transactions; `batch()` is the atomic unit (each batch runs as one transaction). One write primary per database, not per account; read replication is opt-in via the Sessions API (`withSession()`), otherwise every read also hits the primary.
- Anything file-shaped (blobs, uploads, exports): R2.
- Independent tasks that can fail/retry separately: Queues.
- Dependent multi-step processes needing durable state across days: Workflows, not a hand-rolled state machine.
- Workloads that need a full container runtime, longer execution, or a non-JS/WASM language: Containers (GA April 2026, Workers Paid plan). Wire it behind a Worker for routing; it is not the default compute, reach for it only when Workers' isolate model genuinely doesn't fit.

## Limits to design around
- CPU time and memory (128MB per isolate) are hard ceilings. Chunk synchronous loops into async work, stream instead of buffering; for more CPU, configure `limits.cpu_ms` up to the 5-minute max (available on plain Workers too) or move the work to a Queues consumer. A Durable Object gets the same 30s-default/5-min-max CPU budget as a Worker, reach for it for per-key state and serialization, not extra CPU.

## Configuration
- New projects: use `wrangler.jsonc`, Cloudflare's current recommendation; some newer Wrangler features are gated on JSON config and unavailable in TOML. Existing working `wrangler.toml` configs still work, don't migrate them just for this.

## Secrets and environments
- Secrets go through `wrangler secret put`, never through `vars` or committed config.
- Once a Worker uses gradual deployments (versioned deploys), set secrets via `wrangler versions secret put` instead, the old `wrangler secret put` can silently fail to apply to the active version. Same split applies to delete (`wrangler versions secret delete`).
- Cloudflare's account-level Secrets Store (shared secrets referenced across Workers instead of duplicated per-Worker) is real but still open beta as of mid-2026, not GA, worth knowing about, not yet a default reach.
- Environments (dev/staging/prod) do not inherit bindings or vars from each other. Each is configured explicitly.

## CI/CD
- Workers Builds (native git integration) for a straightforward deploy-on-push pipeline. External CI (`cloudflare/wrangler-action`) when the pipeline needs steps Builds does not support (multi-repo, custom test gates).

## Observability
- Workers Logs are on by default for new Workers. Add Tail Workers or Analytics Engine only once default logs stop being enough.

## Zero Trust / Access
- Gate internal, admin, or staff-only Workers behind Cloudflare Access (identity-based, no app code beyond JWT verification).
- Keep public product-facing Workers public with app-level auth. Reserve Access for deploy-preview and admin surfaces.

## Sources
- [Storage options overview (Cloudflare)](https://developers.cloudflare.com/workers/platform/storage-options/)
- [Workers platform limits](https://developers.cloudflare.com/workers/platform/limits/)
- [Architecting on Cloudflare](https://architectingoncloudflare.com/)
- [Workflows GA announcement](https://blog.cloudflare.com/workflows-ga-production-ready-durable-execution/)
- [CI/CD overview](https://developers.cloudflare.com/workers/ci-cd/)
- [Wrangler configuration (wrangler.jsonc recommendation)](https://developers.cloudflare.com/workers/wrangler/configuration/)
- [Secrets (versions secret put for gradual deployments)](https://developers.cloudflare.com/workers/configuration/secrets/)
- [Secrets Store docs (open beta status)](https://developers.cloudflare.com/secrets-store/)
- [Containers and Sandboxes are now generally available (changelog)](https://developers.cloudflare.com/changelog/post/2026-04-13-containers-sandbox-ga/)

Verified: 2026-08-03.
