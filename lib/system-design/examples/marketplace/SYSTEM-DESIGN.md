# Agent Marketplace UML

An agent-ready marketplace. Merchants list physical goods for US buyers. Buyer agents such as Grok Bot, OpenAI Dots or any MCP-capable agent find, quote and buy for their owners. A human owner approves every payment. Stripe Connect Express runs KYC and payouts, so the platform never holds merchant funds.

## Use cases

Every actor sits outside the system boundary. Stripe and the carrier are external systems.

```uml
id: use-cases
type: usecase
title: Use case diagram
level: L1
system: Agent-ready marketplace
actors:
  - {id: merchant, name: Merchant, kind: human}
  - {id: merchant-agent, name: Merchant agent, kind: system}
  - {id: reviewer, name: Reviewer, kind: human}
  - {id: buyer-agent, name: Buyer agent, kind: system}
  - {id: owner, name: Owner, kind: human}
  - {id: stripe, name: Stripe, kind: external}
  - {id: carrier, name: Carrier, kind: external}
cases:
  - {id: UC-M1, name: Onboard with Stripe, actor: merchant, include: [kyc]}
  - {id: UC-M2, name: Set store policies, actor: merchant}
  - {id: UC-M3, name: Create listing, actor: [merchant, merchant-agent], include: [UC-M4]}
  - {id: UC-M4, name: Readiness check}
  - {id: UC-M5, name: Receive order, actor: merchant}
  - {id: UC-M6, name: Mark shipped, actor: merchant, with: [carrier]}
  - {id: UC-M7, name: Refund or cancel, actor: merchant, include: [stripe-refund]}
  - {id: UC-R1, name: Review merchant, actor: reviewer}
  - {id: UC-R2, name: Review listing, actor: reviewer}
  - {id: UC-R3, name: Suspend, actor: reviewer}
  - {id: UC-B1, name: Search, actor: buyer-agent}
  - {id: UC-B2, name: View product, actor: buyer-agent}
  - {id: UC-B3, name: Build quote, actor: buyer-agent, include: [UC-B9]}
  - {id: UC-B4, name: Preview checkout, actor: buyer-agent}
  - {id: UC-B5, name: Pay with single-use card, actor: buyer-agent, include: [charge]}
  - {id: UC-B6, name: Send quote link to owner, actor: buyer-agent}
  - {id: UC-B7, name: Track order, actor: buyer-agent}
  - {id: UC-B8, name: Request return, actor: buyer-agent}
  - {id: UC-B9, name: Verify agent}
  - {id: UC-O1, name: Approve and pay quote, actor: owner, include: [charge], extend: UC-B6}
  - {id: UC-O2, name: Reject quote, actor: owner}
  - {id: UC-O3, name: View order, actor: owner}
  - {id: kyc, name: KYC, with: [stripe]}
  - {id: stripe-refund, name: Stripe refund, with: [stripe]}
  - {id: charge, name: Charge, with: [stripe]}
```

## Domain model

A merchant owns one store policy; a product owns its variants; a quote becomes at most one order. ReviewDecision and AuditEvent stand alone and point at their subject by type and ID.

```uml
id: domain
type: class
title: Class diagram (domain model)
level: L2
classes:
  - {name: Merchant, attrs: [id, name, status, stripeAccountId, supportEmail], ops: [approve(), suspend()]}
  - {name: StorePolicy, attrs: [shipsFrom, "usDeliveryDays[min,max]", shippingFlatCents, dutyMode = DDP, returnWindowDays]}
  - {name: Product, attrs: [id, title, summary, "attributes{}", gtin, status], ops: [submit(), publish(), reject(reason)]}
  - {name: Variant, attrs: [id, sku, "options{}", priceCents, stock], ops: [reserve(qty)]}
  - {name: ReadinessReport, attrs: ["passed: bool", "missing: [field]"]}
  - {name: QuoteLine, attrs: [variantId, qty, unitPriceCents]}
  - {name: Agent, attrs: [id, provider, displayName, verifiedBy, status], ops: [suspend()]}
  - {name: Quote, attrs: [id, status, shipTo, ownerEmail, subtotal, shipping, tax, duty, total, heldUntil], ops: [addLine(), reprice(), preview(), send(), approve(), expire()]}
  - {name: Order, attrs: [id, status, paymentIntentId, applicationFeeCents], ops: [markShipped(track), cancel(), refund()]}
  - {name: Shipment, attrs: [carrier, trackingNo, shippedAt]}
  - {name: Refund, attrs: [amount, reason, stripeId]}
  - {name: ReviewDecision, attrs: [subject (merchant | product), decision, notes, reviewer]}
  - {name: AuditEvent, attrs: ["actorType, actorId", action, subject, at]}
relations:
  - {from: Merchant, to: StorePolicy, kind: comp, mult: ["1", "1"]}
  - {from: Merchant, to: Product, kind: assoc, mult: ["1", "*"]}
  - {from: Product, to: Variant, kind: comp, mult: ["1", "*"]}
  - {from: Product, to: ReadinessReport, kind: assoc, mult: ["1", "*"]}
  - {from: Variant, to: QuoteLine, kind: assoc, mult: ["1", "*"]}
  - {from: Quote, to: QuoteLine, kind: comp, mult: ["1", "*"]}
  - {from: Agent, to: Quote, kind: assoc, mult: ["0..1", "*"], label: creates}
  - {from: Quote, to: Order, kind: comp, mult: ["1", "0..1"], label: becomes}
  - {from: Order, to: Shipment, kind: assoc, mult: ["1", "*"]}
  - {from: Order, to: Refund, kind: assoc, mult: ["1", "*"]}
```

The core calls only the three interfaces. Each adapter realizes one of them, so Stripe, email or the agent check can change without touching the core.

```uml
id: ports
type: class
title: Ports and adapters
level: L2
classes:
  - {name: PaymentGateway, stereotype: interface, ops: [createConnectAccount(), charge(quote), refund(order), tax(quote)]}
  - {name: Notifier, stereotype: interface, ops: [orderPaid(), orderShipped(), quoteSent()]}
  - {name: AgentVerifier, stereotype: interface, ops: ["verify(request): Agent | anonymous"]}
  - {name: StripeAdapter}
  - {name: EmailAdapter}
  - {name: WebhookAdapter}
  - {name: WebBotAuthVerifier}
  - {name: ApiKeyVerifier}
relations:
  - {from: StripeAdapter, to: PaymentGateway, kind: realize}
  - {from: EmailAdapter, to: Notifier, kind: realize}
  - {from: WebhookAdapter, to: Notifier, kind: realize}
  - {from: WebBotAuthVerifier, to: AgentVerifier, kind: realize}
  - {from: ApiKeyVerifier, to: AgentVerifier, kind: realize}
```

## Data

Tables with their keys. `review_decisions`, `audit_events` and `stripe_events` carry no foreign keys. `quotes.idempotency_key` makes a retried create return the same quote. `orders.quote_id` unique: one paid quote yields exactly one order.

```uml
id: schema
type: erd
title: ERD (Postgres)
level: L3
tables:
  - name: merchants
    cols: [[id, PK], [name], [status], [stripe_account_id, UQ], [support_email], [created_at]]
  - name: store_policies
    cols: [[merchant_id, PK FK], [ships_from], [us_delivery_min_days], [us_delivery_max_days], [shipping_flat_cents], [duty_mode], [return_window_days], [return_condition]]
  - name: api_keys
    cols: [[id, PK], [merchant_id, FK], [key_hash, UQ], [scopes]]
  - name: webhook_endpoints
    cols: [[id, PK], [merchant_id, FK], [url], [secret_hash]]
  - name: products
    cols: [[id, PK], [merchant_id, FK], [title], [summary], [attributes, JSONB], [gtin, NULL], [status], [created_at]]
  - name: product_images
    cols: [[id, PK], [product_id, FK], [url], [position]]
  - name: review_decisions
    cols: [[id, PK], [subject_type], [subject_id], [decision], [notes], [reviewer], [decided_at]]
  - name: variants
    cols: [[id, PK], [product_id, FK], [sku, UQ*], [options, JSONB], [price_cents], [stock_on_hand], [stock_reserved], [active]]
  - name: refunds
    cols: [[id, PK], [order_id, FK], [amount_cents], [reason], [stripe_refund_id, UQ], [status]]
  - name: audit_events
    cols: [[id, PK], [actor_type], [actor_id], [action], [subject_type], [subject_id], [request_id], [at]]
  - name: quote_lines
    cols: [[id, PK], [quote_id, FK], [variant_id, FK], [qty], [unit_price_cents]]
  - name: orders
    cols: [[id, PK], [quote_id, FK UQ], [merchant_id, FK], [status], [payment_intent_id, UQ], [application_fee_cents], [paid_at]]
  - name: shipments
    cols: [[id, PK], [order_id, FK], [carrier], [tracking_no], [shipped_at]]
  - name: stripe_events
    cols: [[id, PK], [type], [processed_at]]
  - name: quotes
    cols: [[id, PK], [merchant_id, FK], [agent_id, FK NULL], [idempotency_scope, UQ], [idempotency_key, UQ], [request_hash], [owner_email, NULL], [status], [ship_to, JSONB], [subtotal_cents], [shipping_cents], [tax_cents], [duty_cents], [total_cents], [tax_calculation_id, NULL], [payment_intent_id, UQ NULL], [held_until], [approve_token_hash, UQ], [created_at]]
  - name: agents
    cols: [[id, PK], [provider], [display_name], [key_hash, UQ NULL], [verified_by], [status], [first_seen_at]]
  - name: outbox
    cols: [[id, PK], [topic], [aggregate_type], [aggregate_id], [payload, JSONB], [created_at], [available_at], [locked_until, NULL], [attempts], [last_error, NULL], [sent_at, NULL], [dead_at, NULL]]
rels:
  - {from: merchants, to: products, cardinality: "1:N"}
  - {from: products, to: variants, cardinality: "1:N"}
  - {from: variants, to: quote_lines, cardinality: "1:N"}
  - {from: quotes, to: quote_lines, cardinality: "1:N"}
  - {from: merchants, to: store_policies, cardinality: "1:1"}
  - {from: merchants, to: api_keys, cardinality: "1:N"}
  - {from: merchants, to: webhook_endpoints, cardinality: "1:N"}
  - {from: products, to: product_images, cardinality: "1:N"}
  - {from: quotes, to: orders, cardinality: "1:0..1"}
  - {from: orders, to: shipments, cardinality: "1:N"}
  - {from: orders, to: refunds, cardinality: "1:N"}
  - {from: agents, to: quotes, cardinality: "0..1:0..N", label: agent_id NULL}
  - {from: merchants, to: quotes, cardinality: "1:N"}
  - {from: merchants, to: orders, cardinality: "1:N"}
```

## Architecture

Agents pass the Cloudflare edge first. Web pages and the MCP server both call the same Core API. The core reaches Stripe and email only through its ports, and Stripe calls back through `/stripe/webhook`.

```uml
id: architecture
type: component
title: Architecture (components)
level: L1
nodes:
  - {id: grok, name: Grok Bot, kind: sys, group: Callers}
  - {id: dots, name: Dots, kind: sys, group: Callers}
  - {id: mcp-agents, name: MCP agents, kind: sys, group: Callers}
  - {id: people, name: "Owners, merchants", kind: sys, group: Callers}
  - {id: edge, name: Cloudflare edge, note: "Web Bot Auth, rate limit, WAF, cache GETs"}
  - {id: web, name: Web, note: server-rendered HTML, group: Go monolith (one binary)}
  - {id: mcp, name: MCP server, note: (adapter), group: Go monolith (one binary)}
  - {id: core, name: Core API, note: "/v1 REST, JSON, idempotency keys", group: Go monolith (one binary)}
  - {id: postgres, name: Postgres, note: (+ FTS), kind: store}
  - {id: r2, name: R2 images, kind: store}
  - {id: stripe, name: Stripe, note: "Connect, Link, Tax, Refunds", kind: ext}
  - {id: email, name: Email + merchant webhooks, note: (outbox table + worker), kind: ext}
edges:
  - {from: grok, to: edge}
  - {from: dots, to: edge}
  - {from: mcp-agents, to: edge}
  - {from: people, to: web}
  - {from: edge, to: web}
  - {from: edge, to: mcp}
  - {from: web, to: core}
  - {from: mcp, to: core}
  - {from: core, to: postgres}
  - {from: core, to: r2}
  - {from: core, to: stripe, label: PaymentGateway}
  - {from: stripe, to: core, label: webhooks, dashed: true}
  - {from: core, to: email, label: Notifier}
```

## Sequences

The merchant does KYC on Stripe; Stripe's `account.updated` webhook moves the merchant to review. The first listing fails readiness once, gets fixed, then goes live after review.

```uml
id: seq-onboarding
type: sequence
title: Merchant onboarding and first listing
level: L3
participants: [Merchant, Web, Core, Stripe, Reviewer]
messages:
  - {from: Merchant, to: Web, text: sign up, kind: call}
  - {from: Web, to: Core, text: createMerchant, kind: call}
  - {from: Core, to: Stripe, text: createConnectAcct, kind: call}
  - {from: Stripe, to: Core, text: onboarding URL, kind: return}
  - {from: Core, to: Web, text: "", kind: return}
  - {from: Web, to: Merchant, text: redirect, kind: return}
  - {from: Merchant, to: Stripe, text: KYC on Stripe, kind: call}
  - {from: Stripe, to: Core, text: "webhook account.updated (charges_enabled)", kind: async}
  - {from: Core, to: Core, text: status=in_review, kind: call}
  - {from: Core, to: Reviewer, text: review task, kind: call}
  - {from: Reviewer, to: Core, text: approve, kind: call}
  - {from: Merchant, to: Web, text: "add product (form | CSV | API)", kind: call}
  - {from: Web, to: Core, text: "", kind: call}
  - {from: Core, to: Core, text: readiness check (fail), kind: call}
  - {from: Core, to: Merchant, text: "missing: return_window", kind: return}
  - {from: Merchant, to: Web, text: fix + save, kind: call}
  - {from: Web, to: Core, text: "", kind: call}
  - {from: Core, to: Core, text: readiness pass, kind: call}
  - {from: Core, to: Core, text: status=in_review, kind: call}
  - {from: Core, to: Reviewer, text: review task, kind: call}
  - {from: Reviewer, to: Core, text: approve, kind: call}
  - {from: Core, to: Core, text: "status=live, JSON-LD published", kind: call}
  - {from: Core, to: Merchant, text: '"Product is live"', kind: return}
```

The owner approves the spend in the Link app; Grok Bot pays with the single-use card it gets back. The order becomes `paid` only when Stripe's webhook arrives.

```uml
id: seq-grok-buy
type: sequence
title: Grok Bot buys with a single-use card
level: L3
participants: [Owner, Grok Bot, Edge, Web/Core, Stripe Link, Stripe]
messages:
  - {from: Owner, to: Grok Bot, text: '"buy X"', kind: call}
  - {from: Grok Bot, to: Edge, text: GET /search, kind: call}
  - {from: Edge, to: Edge, text: verify sig, kind: call}
  - {from: Edge, to: Web/Core, text: "", kind: call}
  - {from: Web/Core, to: Grok Bot, text: results (HTML+JSON-LD), kind: return}
  - {from: Grok Bot, to: Web/Core, text: "POST /quotes (lines, ship_to, idem key)", kind: call}
  - {from: Web/Core, to: Web/Core, text: "reprice, tax, duty", kind: call}
  - {from: Web/Core, to: Grok Bot, text: "quote, total, held_until", kind: return}
  - {from: Grok Bot, to: Stripe Link, text: "spend request: $total", kind: call}
  - {from: Stripe Link, to: Owner, text: approve in Link app, kind: call}
  - {from: Owner, to: Stripe Link, text: approve, kind: call}
  - {from: Stripe Link, to: Grok Bot, text: single-use card, kind: return}
  - {from: Grok Bot, to: Web/Core, text: "checkout page: card + quote_id", kind: call}
  - {from: Web/Core, to: Stripe, text: "PaymentIntent (destination=merchant, fee)", kind: call}
  - {from: Stripe, to: Web/Core, text: webhook payment_intent.succeeded, kind: async}
  - {from: Web/Core, to: Web/Core, text: "order=paid, stock reserved", kind: call}
  - {from: Web/Core, to: Grok Bot, text: order id + status page, kind: return}
  - {from: Web/Core, to: Web/Core, text: "outbox: email owner + merchant", kind: call}
```

The agent holds no card. It builds and previews a quote, then sends the owner an approve link; the owner pays on the platform's checkout.

```uml
id: seq-mcp-quote-link
type: sequence
title: An MCP agent hands the owner a quote link
level: L3
participants: [Owner, Dot (MCP), MCP server, Core, Stripe]
messages:
  - {from: Owner, to: Dot (MCP), text: '"find a gift"', kind: call}
  - {from: Dot (MCP), to: MCP server, text: "search, get_product", kind: call}
  - {from: MCP server, to: Core, text: "", kind: call}
  - {from: Dot (MCP), to: MCP server, text: create_quote, kind: call}
  - {from: MCP server, to: Core, text: "", kind: call}
  - {from: Core, to: Core, text: "quote open, held 48h", kind: call}
  - {from: Dot (MCP), to: MCP server, text: preview_checkout, kind: call}
  - {from: MCP server, to: Core, text: "", kind: call}
  - {from: Core, to: Core, text: exact charge, kind: call}
  - {from: Dot (MCP), to: MCP server, text: send_to_owner, kind: call}
  - {from: MCP server, to: Core, text: "", kind: call}
  - {from: Core, to: Core, text: "status=sent, email with approve_url", kind: call}
  - {from: Core, to: Owner, text: "email: approve $X", kind: async}
  - {from: Owner, to: Core, text: open approve_url, kind: call}
  - {from: Core, to: Core, text: Checkout (Link or card), kind: call}
  - {from: Core, to: Stripe, text: "", kind: call}
  - {from: Stripe, to: Core, text: webhook succeeded, kind: async}
  - {from: Core, to: Core, text: order=paid, kind: call}
  - {from: Dot (MCP), to: MCP server, text: order_status, kind: call}
  - {from: MCP server, to: Core, text: "", kind: call}
  - {from: Core, to: Dot (MCP), text: "paid, ships in 7 to 10 days", kind: return}
```

Every status change notifies the owner or agent through the outbox. A refund also reverses the transfer and the fee on Stripe.

```uml
id: seq-ship-refund
type: sequence
title: Ship, then refund
level: L3
participants: [Merchant, Core, Stripe, Owner / agent]
messages:
  - {from: Merchant, to: Core, text: "mark shipped (carrier, tracking)", kind: call}
  - {from: Core, to: Core, text: order=shipped, kind: call}
  - {from: Core, to: Owner / agent, text: outbox email + webhook, kind: async}
  - {from: Merchant, to: Core, text: refund (reason), kind: call}
  - {from: Core, to: Stripe, text: refund(order), kind: call}
  - {from: Stripe, to: Stripe, text: refund + reverse transfer + refund fee, kind: call}
  - {from: Stripe, to: Core, text: webhook charge.refunded, kind: async}
  - {from: Core, to: Core, text: order=refunded, kind: call}
  - {from: Core, to: Owner / agent, text: outbox email, kind: async}
```

## State machines

```uml
id: sm-merchant
type: state
title: Merchant states
level: L4
states:
  - {name: pending_kyc}
  - {name: in_review}
  - {name: approved}
  - {name: suspended}
  - {name: rejected}
transitions:
  - {from: pending_kyc, to: in_review, event: kyc ok}
  - {from: in_review, to: approved, event: approve}
  - {from: approved, to: suspended, event: suspend}
  - {from: in_review, to: rejected, event: reject}
  - {from: suspended, to: approved, event: reinstate}
```

A failed readiness check or a rejected review sends the listing back to `draft`. Stock at zero keeps the product `live` with a sold out flag.

```uml
id: sm-product
type: state
title: Product states
level: L4
states:
  - {name: draft}
  - {name: readiness}
  - {name: in_review}
  - {name: live}
  - {name: archived}
  - {name: live (sold out flag)}
transitions:
  - {from: draft, to: readiness, event: submit}
  - {from: readiness, to: in_review, event: pass}
  - {from: in_review, to: live, event: approve}
  - {from: live, to: archived, event: archive}
  - {from: readiness, to: draft, event: fail}
  - {from: in_review, to: draft, event: reject}
  - {from: live, to: live (sold out flag), event: stock 0}
```

A paid quote is frozen: no edits. `paying` sits between approval and money: entering it reserves stock and cuts the hold to 30 minutes.

```uml
id: sm-quote
type: state
title: Quote states
level: L4
states:
  - {name: open}
  - {name: sent}
  - {name: paying}
  - {name: paid}
  - {name: cancelled}
  - {name: expired}
transitions:
  - {from: open, to: sent, event: send}
  - {from: sent, to: paying, event: owner pays}
  - {from: sent, to: cancelled, event: owner rejects}
  - {from: open, to: paying, event: agent pays (card)}
  - {from: paying, to: paid, event: payment_succeeded}
  - {from: paying, to: cancelled, event: owner rejects, guard: PI cancelled}
  - {from: paying, to: expired, event: held_until passes, guard: PI cancelled}
  - {from: open, to: expired, event: held_until passes}
```

Cancel from `paid` is a full refund before shipping and ends in `cancelled`. A refund from `shipped` or `delivered` (return or lost parcel) ends in `refunded`. Both are final states.

```uml
id: sm-order
type: state
title: Order states
level: L4
states:
  - {name: paid}
  - {name: shipped}
  - {name: delivered}
  - {name: cancelling}
  - {name: refunding}
  - {name: refunded, final: true}
  - {name: cancelled, final: true}
transitions:
  - {from: paid, to: shipped, event: ship}
  - {from: shipped, to: delivered, event: carrier}
  - {from: paid, to: cancelling, event: cancel, guard: before shipping}
  - {from: cancelling, to: cancelled, event: charge.refunded}
  - {from: shipped, to: refunding, event: refund}
  - {from: delivered, to: refunding, event: refund}
  - {from: refunding, to: refunded, event: charge.refunded}
```

## Deployment

Cloudflare in front, two instances of the Go binary on the app host, managed Postgres behind. Stripe and the email provider hang off the app host. Staging has the same shape with Stripe in test mode.

```uml
id: deployment
type: component
title: Deployment (v1)
level: L1
nodes:
  - {id: cloudflare, name: Cloudflare, note: "DNS, edge, Web Bot Auth, R2"}
  - {id: bin-1, name: Go binary, note: «executable», kind: sys, group: app host}
  - {id: bin-2, name: Go binary, note: «executable», kind: sys, group: app host}
  - {id: pg, name: managed Postgres, note: "daily backup, PITR", kind: store}
  - {id: stripe, name: Stripe, note: "(Connect, Link, Tax)", kind: ext}
  - {id: email, name: email provider, kind: ext}
edges:
  - {from: cloudflare, to: bin-1}
  - {from: cloudflare, to: bin-2}
  - {from: bin-1, to: pg}
  - {from: bin-2, to: pg}
  - {from: bin-1, to: stripe}
  - {from: bin-2, to: email}
```

## Cross-cutting concepts

- Idempotency keys are scoped per caller. The same key from two callers never collides.
- Every notification goes through the outbox. No code path sends email directly.
- Money is integer cents. Rounding is half-up, applied per line.
- Every state move is a conditional UPDATE on the current status. A lost race updates zero rows and stops.
- The Stripe webhook and the browser redirect share one confirm path.

## Risks and technical debt

- Two app instances race on the outbox and on expiry. Bites when we scale past one instance. Mitigated by SKIP LOCKED on both queries.
- A Stripe Tax rate change lands inside a 48h hold. Bites when a quote is priced before the change and paid after. The platform absorbs the difference.
- Agent payment rails are early access. Bites if the vendor changes terms or access. No fallback rail yet.
- The duty estimate is a flat rate per category. Bites on items whose real duty differs from the category rate. Shown to the buyer as an estimate.
