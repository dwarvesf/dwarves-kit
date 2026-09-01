---
title: openclaw/acpx absorption analysis (ACP client + flow runtime vs dwarves-kit)
date: 2026-07-25
purpose: Verdict record for the openclaw/acpx repo (ACP client CLI + defineFlow runtime + pr-triage and replay-viewer examples) against dwarves-kit's orchestration machinery. Answers "where does it fit, what do we absorb". Absorbs three mechanisms small, parks two with tripwires, skips wholesale adoption.
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: none
next_review: null
status: active
---

# openclaw/acpx absorption

Source: https://github.com/openclaw/acpx (MIT, TypeScript, v0.12.1 alpha, ~5 months old,
3k stars, thin bus factor: 2-4 real core committers). It is an Agent Client Protocol (ACP)
client CLI: JSON-RPC-over-stdio driving of coding agents (claude/codex/pi/openclaw) as
subprocesses, plus a `defineFlow()` typed-graph runtime (`acpx flow run`). The two examples:
`examples/flows/pr-triage` (autonomous PR triage decision tree) and
`examples/flows/replay-viewer` (React viewer over persisted run bundles).

## Where it sits relative to the kit

Same niche as dwarves-kit, one layer LOWER: protocol client + flow engine vs spec-driven
lifecycle + gates. The kit already owns the layer acpx's flow runtime occupies:
ADR-0030 wavefront (`lib/queue/orchestrate.sh`, event-sourced, replay-derived BOARD),
dispatch-gate disjointness, gate-ledger + lane-telemetry, and ID-390's per-vendor headless
argv adapter. ID-394 (own the ordering graph, fan-in/fan-out) is already scoped to exactly
the gap acpx's graph model covers. Wholesale adoption would be a second orchestration
engine beside a shipped one.

North-star check (PHILOSOPHY §6): wholesale adoption fails N4 (a flow format that only
makes sense with acpx's runtime running is the rejected BMAD-pack shape) and contradicts
Han's explicit ID-394 direction ("build it ourselves"). The absorbs below serve N5
(named failure semantics), N6 (signals made visible), and N1 (loops name their exits).

## Verdict table (per mechanism)

| Mechanism | Verdict | Rationale / landing |
|---|---|---|
| Wholesale acpx adoption (dependency) | SKIP | Alpha ("interface changes anticipated"), thin bus factor, duplicates ADR-0030 + ID-390; solo operator doesn't multiplex agent vendors mid-flow. No claim is benchmarked (structural, not empirical). |
| close/escalate/continue trilemma + "root-cause-vs-symptom" as a NAMED node | ABSORB | Fills N5's stated gap ("failure semantics for mid-graph nodes unnamed"). Kit row ID-398. |
| defineFlow node vocabulary (compute/action/agent node types, decision edges keyed off parsed JSON, per-node timeoutMs) | ABSORB (as prior-art constraint) | Not a dependency: design vocabulary for the ID-394 spec. Annotated onto ID-394. |
| Dual staleness re-check (pre-validation AND post-review/CI, before handoff) | ABSORB (contract line) | Belongs in ID-394's ordered-merge/bisect-on-red failure semantics. Annotated onto ID-394. |
| Two-layer replay: static graph rendered whole, executed trace painted on top | ABSORB | `lane-telemetry.sh trace` is the seam; ASCII render (plain files, no GUI daemon, no mermaid). Kit row ID-399. |
| Permission mode as a first-class DECLARED flow requirement, enforced at load time | PARK | Tripwire: an autonomous kit run stalls or dies on a permission prompt mid-run (visible in the gate ledger / watchdog). Then: a `Permissions:` header on goal files checked at dispatch. |
| acpx as headless driver for the overnight queue (replacing tmux send-keys / argv adapter) | PARK | Tripwire: ID-390's argv adapter proves too brittle in live multi-vendor runs (prompt-delivery failures), or a flow needs mid-turn tool-permission control argv cannot express. Security screen if unparked: npm alpha binary in the driving path of a Max-plan OAuth session = ban-risk review first; official adapter (`@agentclientprotocol/claude-agent-acp`) mitigates but does not clear it. |
| Session-as-state (one persistent agent session across flow steps) | SKIP | Deliberate kit design conflict: fresh-context verifiers are the point (self-review misses what fresh context catches). The lead session already persists. |
| stdout/stderr-tail heuristic (`selectLocalCodexReviewText`: prefer stdout, else grep stderr for the verdict tail) | SKIP (noted) | Two-minute port; apply inline the day a kit worker wraps a noisy third-party CLI. No row. |
| Dated coverage-roadmap doc listing what's NOT implemented | SKIP | Kit already states gaps per criterion in PHILOSOPHY §6 and the registry. |

## Absorption designs (smallest deliverable each)

1. **ID-398, failure-policy vocabulary.** One contract addition, not a new engine: the
   escalation paths in `/kit:execute` (retry-then-escalate) and the ID-394 spec adopt
   close / escalate / continue as the named three-way exit for any judging node, and
   "does this solve the root cause, not the symptom" becomes a distinct judged step in
   the review chain rather than a clause inside one big prompt. Emitter-with-reader: the
   named outcome lands in the gate ledger (existing reader: lane-telemetry/stats).
2. **ID-394 annotation (done in this pass).** The spec's prior-art pickups gain acpx's
   node-type separation, JSON-keyed decision edges, per-node timeout, and the dual
   staleness re-check on the merge path.
3. **ID-399, trace overlay.** `lane-telemetry.sh trace <rid>` grows an intended-vs-executed
   ASCII render: full graph shape always shown, executed path marked. Reads existing
   ledger + orchestrate events.log only; no new store, no daemon, no web viewer.

## Health / failure notes (recon findings worth keeping)

- Open issue #434: macOS XProtect deletes the bundled codex binary post-install (platform
  integration risk of the npm-bundled-binary pattern).
- The org's flagship-repo star count returned by the API summarization (384k) is implausible;
  treat as unverified. acpx's own 3,042/307 cross-checked.
- pr-triage's TUNING.md openly says its routing thresholds are still being calibrated;
  it is a reference example, not a hardened product.

## Routing done

- VERDICTS.md row appended (this file is the source note).
- dwarves-kit `_meta/BACKLOG.md`: ID-398 + ID-399 queued; ID-394 note annotated; two
  parked bullets with tripwires.
- URL ledger: three acpx links recorded via dgst.
