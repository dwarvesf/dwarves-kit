# Tool and framework picks by category

Extends a tech-stack-preferences table with a status column, borrowed loosely from the ThoughtWorks Radar (Adopt/Trial/Assess/Hold), for categories not already pinned elsewhere. Do not duplicate rows already pinned in your own stack preferences (Python tooling, versions, Node, containers, IaC, secrets); this file is the overflow.

| Category | Pick | Status | Why | Reconsider when |
|---|---|---|---|---|
| Static web | Astro + Cloudflare Pages | Adopt | Ships fast, zero JS by default, matches existing sites | The project needs heavy client interactivity as its core feature; also: Cloudflare is now steering new full-stack projects toward Workers static assets over Pages (Durable Objects, Workers Logs, Logpush, Cron Triggers are Workers-only), Pages still fine for a pure static site |
| Dynamic/edge backend | Hono on Cloudflare Workers | Adopt | Thin, fast, matches the edge-first default | Needs long-lived connections or state a Worker cannot hold |
| Local ETL transform | DuckDB SQL | Adopt | Fast, no server, matches the quick-glue default | Data outgrows single-machine memory or disk |
| CLI framework (Go) | stdlib `flag`, `cobra` once subcommands appear | Adopt | Boring, well understood | Rarely; this is the stable default |
| State management (frontend) | React state/context first, a library only once state genuinely outgrows it | Adopt | Avoids a dependency for a problem that does not exist yet | Cross-component state sharing becomes the actual bottleneck |
| UI components | shadcn free blocks first, Tremor as fallback | Adopt | Matches the existing default-prototype-UI preference | A paid/Pro block is the only option that fits; note Tremor now ships a copy-paste blocks distribution (blocks.tremor.so, shadcn-style) alongside the npm package, not npm-only |

Add a row here the next time a category comes up with no existing default. Do not leave the same decision ad hoc twice.

## Sources
- [ThoughtWorks Technology Radar](https://www.thoughtworks.com/en-us/radar)
- [Choose Boring Technology (Dan McKinley)](https://mcfunley.com/choose-boring-technology)

Verified: 2026-08-03.
