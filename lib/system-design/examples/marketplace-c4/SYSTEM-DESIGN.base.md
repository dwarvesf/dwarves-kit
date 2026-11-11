---
rev: A
decided:
  - "One Go binary serves web, MCP and the Core API, so the container view draws it as one frame."
---
# Agent Marketplace C4

The same agent-ready marketplace as the UML example, drawn as four C4 views: context, container, component and deployment. C4 shows structure, so the UML set keeps the behavior and data diagrams. Click a magnifier to zoom from a box into the view that opens it.

## System context

Three kinds of people and one kind of software meet the marketplace. A human owner approves every payment in Stripe Link; the buyer agent only quotes and pays with the card it gets back.

```uml
id: c4-context
type: c4
view: context
title: System context
level: L1
review:
  - Is the owner's approval in Stripe Link the only spend gate?
elements:
  - {id: owner, name: Owner, c4: person, desc: Approves every payment., at: [0, 0]}
  - {id: buyer-agent, name: Buyer agent, c4: system, ext: true, desc: "Grok Bot, OpenAI Dots or any MCP agent. Finds, quotes and buys.", at: [1, 0]}
  - {id: merchant, name: Merchant, c4: person, desc: Lists goods and ships orders., at: [0, 1]}
  - {id: reviewer, name: Reviewer, c4: person, desc: Approves merchants and listings., at: [0, 2]}
  - {id: marketplace, name: Agent marketplace, c4: system, desc: "Listings, quotes and orders. Never holds merchant funds.", zoom: c4-containers, at: [2, 1]}
  - {id: stripe, name: Stripe, c4: system, ext: true, desc: "Connect KYC and payouts, Link cards, Tax, refunds.", at: [3, 0]}
relations:
  - {from: owner, to: buyer-agent, label: Asks to buy}
  - {from: owner, to: stripe, label: Approves spend, tech: Link app, via: [[0, -0.5], [3, -0.5]]}
  - {from: buyer-agent, to: marketplace, label: Searches and quotes, tech: "HTTPS, MCP"}
  - {from: merchant, to: marketplace, label: Lists goods and ships, tech: HTTPS}
  - {from: reviewer, to: marketplace, label: Reviews, tech: HTTPS}
  - {from: marketplace, to: stripe, label: Onboards and charges, tech: REST}
  - {from: stripe, to: marketplace, label: Payment events, tech: webhook, dashed: true}
```

## Containers

Agents pass the Cloudflare edge first. Web and the MCP server call the same Core API. All three live in one Go binary. The core reaches Stripe and email only through its ports.

```uml
id: c4-containers
type: c4
view: container
title: Containers
level: L2
review:
  - Should the outbox worker leave the monolith before a second instance runs?
boundaries:
  - {id: mkt, name: Agent marketplace, kind: system}
  - {id: mono, name: Go monolith (one binary), kind: container, in: mkt}
elements:
  - {id: merchant, name: Merchant, c4: person, desc: Lists goods and ships orders., at: [0, 0]}
  - {id: reviewer, name: Reviewer, c4: person, desc: Approves merchants and listings., at: [0, 1]}
  - {id: buyer-agent, name: Buyer agent, c4: system, ext: true, desc: "Finds, quotes and buys.", at: [0, 3]}
  - {id: edge, name: Cloudflare edge, c4: container, tech: "Workers, Web Bot Auth", desc: "Verifies agent signatures, rate limits, caches GETs.", boundary: mkt, at: [1, 2]}
  - {id: web, name: Web, c4: container, tech: "Go, server-rendered HTML", desc: Owner pages., boundary: mono, at: [2, 1]}
  - {id: mcp, name: MCP server, c4: container, tech: Go adapter, desc: Exposes the Core API as MCP tools., boundary: mono, at: [2, 3]}
  - {id: cron, name: Expiry cron, c4: container, tech: Go, desc: Expires quotes after the 48h hold., boundary: mono, at: [3, 3]}
  - {id: core, name: Core API, c4: container, tech: "Go, REST /v1, JSON", desc: "Quotes, orders, merchants. Idempotency keys on writes.", boundary: mono, zoom: c4-core, at: [3, 2]}
  - {id: stripe, name: Stripe, c4: system, ext: true, desc: "Connect, Link, Tax, refunds.", at: [4, 0]}
  - {id: postgres, name: Postgres, c4: db, tech: "Postgres, FTS", desc: "Catalog, quotes, orders, outbox.", boundary: mkt, at: [4, 1]}
  - {id: email, name: Email provider, c4: system, ext: true, desc: Order and quote notices., at: [4, 4]}
relations:
  - {from: merchant, to: web, label: Uses, tech: HTTPS}
  - {from: reviewer, to: web, label: Reviews, tech: HTTPS}
  - {from: buyer-agent, to: edge, label: Calls, tech: "HTTPS, MCP"}
  - {from: edge, to: web, label: Forwards, tech: HTTPS}
  - {from: edge, to: mcp, label: Forwards, tech: HTTPS}
  - {from: web, to: core, label: Calls, tech: in-process}
  - {from: mcp, to: core, label: Calls, tech: in-process}
  - {from: cron, to: core, label: Expires quotes, tech: in-process}
  - {from: core, to: postgres, label: Reads and writes, tech: SQL}
  - {from: core, to: stripe, label: Charges, tech: REST}
  - {from: stripe, to: core, label: Webhooks, tech: HTTPS, dashed: true}
  - {from: core, to: email, label: Notifier, tech: outbox worker}
```

## Components

The Core API is a set of services behind two ports. Stripe and email can change without touching the services, because only the ports know them.

```uml
id: c4-core
type: c4
view: component
title: Core API components
level: L3
review:
  - Is one webhook handler enough, or does each Stripe object type get its own?
boundaries:
  - {id: core, name: Core API, kind: container}
elements:
  - {id: web, name: Web, c4: container, tech: Go, desc: Owner and merchant pages., at: [0, 0]}
  - {id: mcp, name: MCP server, c4: container, tech: Go, desc: MCP tools., at: [0, 1]}
  - {id: catalog, name: Catalog, c4: component, tech: Go service, desc: Listings and the readiness check., boundary: core, at: [1, 0]}
  - {id: quotes, name: Quotes, c4: component, tech: Go service, desc: "Prices, holds stock 48h, owns the quote state machine.", boundary: core, at: [1, 1]}
  - {id: orders, name: Orders, c4: component, tech: Go service, desc: Turns a paid quote into one order., boundary: core, at: [1, 2]}
  - {id: payments, name: PaymentGateway, c4: component, tech: Go port, desc: "createConnectAccount, charge, refund, tax.", boundary: core, at: [2, 1]}
  - {id: notifier, name: Notifier, c4: component, tech: Go port, desc: Writes notices to the outbox., boundary: core, at: [2, 2]}
  - {id: postgres, name: Postgres, c4: db, tech: Postgres, desc: "Catalog, quotes, orders, outbox.", at: [3, 2]}
  - {id: stripe, name: Stripe, c4: system, ext: true, desc: "Connect, Link, Tax.", at: [3, 3]}
relations:
  - {from: web, to: catalog, label: Reads listings}
  - {from: mcp, to: quotes, label: Creates quotes}
  - {from: quotes, to: payments, label: Charges}
  - {from: orders, to: payments, label: Refunds}
  - {from: orders, to: notifier, label: Notifies}
  - {from: payments, to: stripe, label: Calls, tech: REST}
  - {from: notifier, to: postgres, label: Writes outbox, tech: SQL}
```

## Deployment

Cloudflare sits in front. Two instances of the Go binary run on app hosts in one region, with managed Postgres behind. Staging has the same shape with Stripe in test mode.

```uml
id: c4-deploy
type: c4
view: deployment
title: Deployment (production)
level: L4
review:
  - Two hosts share one Postgres. Is a failover replica needed before launch?
boundaries:
  - {id: cf, name: Cloudflare, kind: account}
  - {id: host, name: Hosting provider, kind: account}
  - {id: region, name: us-east, kind: region, in: host}
elements:
  - {id: cf-edge, name: Cloudflare edge, c4: node, tech: "DNS, WAF, Web Bot Auth", desc: Terminates TLS and verifies agents., boundary: cf, at: [0, 1]}
  - {id: r2, name: Image bucket, c4: db, tech: Cloudflare R2, desc: Product images., boundary: cf, at: [0, 3]}
  - {id: app-1, name: App host 1, c4: node, tech: "VM, systemd", desc: One Go binary instance., boundary: region, at: [1, 0]}
  - {id: pg, name: Managed Postgres, c4: db, tech: "Postgres 16, PITR", desc: Daily backup., boundary: region, at: [2, 1]}
  - {id: stripe, name: Stripe, c4: system, ext: true, desc: "Connect, Link, Tax.", at: [3, 0]}
  - {id: email, name: Email provider, c4: system, ext: true, desc: Order and quote notices., at: [3, 2]}
relations:
  - {from: cf-edge, to: app-1, label: Forwards, tech: HTTPS}
  - {from: app-1, to: pg, label: Reads and writes, tech: SQL over TLS}
  - {from: app-1, to: stripe, label: Charges, tech: REST}
  - {from: app-1, to: email, label: Sends, tech: API}
```
