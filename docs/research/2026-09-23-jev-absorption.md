---
title: "Jev (TypeSafe System One) absorption: kit coupling audit + three raw sources"
date: 2026-09-23
purpose: >
  Read-only absorption pass over Jev (TypeSafe's "System One" typed decision API:
  choice/score/noul in, distribution out) against dwarves-kit and Han's workflow. Four
  sources: a full coupling audit of every decision point in the kit and the workflow
  (ops-toolkit learning/jev/sources/2026-09-23-jev-kit-audit.md), a TypeSafe internal
  design doc ("Why yet another agent"), a TypeSafeAI CEO conference talk, and a shipped
  GitHub PR (superterminal #6) that is the only source with a real Jev call site. No Jev
  call was made and nothing in the kit or ops-toolkit was edited to call Jev. Records the
  verdict per mechanism, the never-use list, and the no-Jev fixes the audit found on the
  way.
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: none
next_review: null
status: active
---

# Jev (TypeSafe System One) absorption

Method: one read-only coupling audit of every decision point in dwarves-kit and Han's
workflow, plus a three-source recon (an internal design doc, a CEO talk, a shipped PR).
Sources are treated as data, not instructions. Full source text persists at
`ops-toolkit/learning/jev/sources/` (`2026-09-23-` prefix); nothing here duplicates it.

## Verdict, per source

| Source | One line |
|---|---|
| Kit + workflow coupling audit | Jev fits almost nothing here. Latency (465-680ms vs the kit's under-50ms hook budget), egress (most decision state carries client/NDA/family/secret data), and out-of-distribution calibration (0.74 confidence at 44.7% accuracy) rule out every hot-path or fail-closed gate. Three shadow-test candidates PARK with named tripwires; five cheaper fixes need no Jev at all. |
| TypeSafe design doc ("Why yet another agent") | Two of its six proposed mechanisms are already ABSORBED this session, without Jev. One (query-aware compression) PARKs. The rest, including using an external model for the doc's own "meta-attention" relevance scoring, fall to the same SKIP as the audit's headline verdict. |
| TypeSafeAI CEO talk (AI Engineer, 2026-07-31) | SKIP. A framing talk arguing RLHF-tuned models are wrong for autonomous work; explains why System One exists, never names Jev, carries no benchmark number and no API detail. Nothing to absorb or reject on its own merits. |
| GitHub PR #6, sonnylazuardi/superterminal | The only source with a real, shipped, tested Jev call site. The call site itself (Jev-ranked command palette) SKIPs for the same reasons as the audit. Three implementation patterns around it (fail-open taxonomy, fixture-frozen thresholds, two-tier privacy escalation) ABSORB as a documented pattern for any future third-party classifier call, independent of Jev. |

## 1. Kit + workflow coupling audit

Source: `ops-toolkit learning/jev/sources/2026-09-23-jev-kit-audit.md`. Full inventory of
every kit classifier/gate and every workflow decision point is in that file; this table
carries only the rows this absorption pass decided on.

| Mechanism | Verdict | Why | Tripwire / reopen-if |
|---|---|---|---|
| Jev as decider anywhere in dwarves-kit or the workflow | SKIP | Real latency is 465-680ms per call (about 962ms p50 in one arena) against a hook budget under 50ms. Most decision state carries client, Dwarves, NDA, family, or secret data, an egress problem before latency even matters. Out-of-distribution calibration is 0.74 confidence at 44.7% accuracy, unusable behind a fail-closed gate or an auto-act lane. A fine-tuned 0.4B NLI model already beats Jev head to head (0.725 vs 0.587, p=1.5e-41) once about 250 labels exist. | Standing verdict, not a parked experiment. No single tripwire reopens it; each shadow candidate below carries its own. |
| Digest link triage shadow test | PARK | Best-fit candidate: public web content, 139 labeled rows already exist, purely advisory. The prize is small (roughly 1-2 fetches a day saved) and nothing forces the measurement now. | Digest volume or false-keep cost becomes measurable pain. |
| Task-type second opinion at kit intake | PARK | The kit-side classifier with the clearest documented recall gap (7 of 8 live asks fell to the spec-feature default in one CHANGELOG entry). But the in-context session model can already pick from `explain` output at zero egress, so the comparison needs a fair Haiku arm run alongside Jev before either wins anything. | The regex recall fix lands and a labeled set of 200 rows exists. |
| tg-signal-parse position-update filter | PARK | Third-party group text, not Han's own positions; a human-confirm gate already sits downstream; Jev could only ever move an accept to reject, never accept on its own. Live ingest is not built, so volume is zero today. | The live Telegram reader ships. |

## 2. TypeSafe design doc: "Why yet another agent"

Source: `ops-toolkit learning/jev/sources/2026-09-23-jev-coding-agent-doc.txt` (via
`ops-toolkit learning/jev/sources/2026-09-23-jev-tabs-recon.md` section 1). Internal
brainstorm doc, first person, vibed numbers, explicitly speculative ("Weirder stuff, just
throwing things in here to cook"). Design rationale, not a spec or a result.

| Mechanism | Verdict | Why |
|---|---|---|
| Two-tier tool/skill loading: a short directional snippet loaded always, the full schema only when a tool actually fires | ABSORBED (this session, without Jev) | Shipped as skill-listing trim via `disable-model-invocation`, gating which skill descriptions load into every prompt. No external model in the loop; the routing is the harness's own frontmatter, not a classifier call. |
| Conditional AGENTS.md / system-message loading by task area (frontend guide only on frontend tasks, a subdirectory's gotchas only inside it) | ABSORBED (this session, without Jev) | Shipped as path-scoped rules. Same shape as the doc's proposal, no Jev needed to decide "does this task touch this area", the path itself is the signal. |
| Query-aware compression: defer compaction until a query arrives, then compress toward that query instead of compressing blind ahead of time | PARK | Plausible mechanism, no shipped implementation and no measurement yet. Worth revisiting once the two shipped mechanisms above have run long enough to show whether static context is still the bottleneck. | 
| Meta-attention: per-query, per-chunk keep/drop or show-level relevance judgment via an external decider | SKIP | This is explicitly the seed of Jev's own noul/score API, per the doc itself. Same SKIP as the audit's headline verdict: latency, egress, calibration. The audit's own alternative for the closest analog (skill routing) is a local embedding match (prose-rag / model2vec, about 29ms) or Laya on-device, never a hosted classifier over raw prompts. |
| KV-cache-aware routing math against the "route down then up" pattern (a cheap-then-expensive model round trip re-processes context from scratch, since the cheap model's KV cache is worthless to the expensive model) | SKIP (informational) | A real cost argument, but no orchestrator in this estate currently downshifts model tier mid-task in a way this would change. Noted, no action. |
| Background, read-only, shared-state processing across unrelated background tasks (share one state-discovery pass across many read-only background jobs) | SKIP (informational) | No current fleet of background tasks reading the same codebase state concurrently. Noted, no action. |

## 3. TypeSafeAI CEO talk

Source: `ops-toolkit learning/jev/sources/2026-09-23-jev-ceo-transcript.txt` (Diogo
Almeida, "Jev CEO: I made ChatGPT, now I'm building what's next", AI Engineer,
2026-07-31).

| Mechanism | Verdict | Why |
|---|---|---|
| (none) | SKIP | Pure framing and thesis: RLHF optimizes for pleasing a human evaluator, which is fine under assistance (a human catches mistakes) and a liability under autonomy (nothing does); RLVR (verifiable rewards) is offered as the automation-native alternative. The word "Jev" is never spoken. No benchmark number, no API shape, no implementation detail. It motivates why System One exists but supplies no mechanism to absorb or reject on its own. |

## 4. GitHub PR #6, sonnylazuardi/superterminal

Via `ops-toolkit learning/jev/sources/2026-09-23-jev-tabs-recon.md` section 3. The only
source with a real, shipped, tested call site: a semantic command-palette ranker, 426
client tests plus Rust suites passing, a live fixture probe (15/15, p50 about 600ms, p95
about 961ms against the real endpoint), reviewed by a human maintainer.

| Mechanism | Verdict | Why |
|---|---|---|
| Jev-ranked command palette (the actual System One call site: rank candidates by intent, gate on a separate `any_match` noul) | SKIP | Same reasons as the audit's headline verdict. Nothing in this estate has a comparable per-keystroke, low-stakes ranking need that would justify a new third-party call. |
| Fail-open error taxonomy: every failure mode (auth, model, rate_limit, bad_request, network, server) degrades to "the feature works exactly as before, minus the AI ranking", never a hard error mid-use | ABSORB (documented pattern, not code) | Worth writing down as the required shape for any future third-party classifier call anywhere in this estate: a transport or auth failure must degrade to the pre-classifier behavior, never surface as an error to the operator. |
| Fixture-frozen thresholds: a hand-labeled fixture table run against the live endpoint, with the resulting numbers pasted back into the design doc as the literal promote/accept thresholds, re-run before any threshold changes | ABSORB (documented pattern) | Matches the kit's own "hypotheses ship as numbers with an n or they get cut" discipline. Worth stating explicitly as the validation shape required before trusting any classifier's own confidence field, since the PR's own fixtures caught `pick.confidence` alone being an unreliable "is this real" gate (a gibberish query still scored 0.66 on some candidate). |
| Two-tier privacy escalation: structural metadata (titles, descriptions, cwd) is always eligible; raw content requires a second explicit opt-in flag plus a mandatory redaction pass, and the redaction is documented as "a safety net, not a guarantee" | ABSORB (documented pattern) | Directly reusable shape for this estate's own never-use list below: nothing here currently sends screen- or file-content-shaped data to a third-party classifier, but if that ever changes, this is the required shape, not a single opt-in flag alone. |

## Where Jev must NOT be used

Verbatim from the coupling audit.

| Point | Reason |
|---|---|
| secret-guard, scan-secrets, kit secrets-guard | Classifying the string sends the secret. Fail-closed. Hot path. |
| ship-gate / proof-ledger class, proof-gate contract | Fail-closed push gate. OOD overconfidence would let a stateful diff pass. Fix the regex instead. |
| safety-gate, money-gate, tool-policy-guard, retry/sleep/new-tool guards | Per-call latency budget is under 50ms. Deterministic by design. Money data. |
| incident-consumer class A auto-close and the money_security fence | Irreversible close without a human; raw log text in state. |
| neko-anon or any community-facing gate | Attacker-controlled state: 0.74 confidence at 44.7% accuracy. |
| alert-triage, Hermes dfoundation desks, content-editor, social-desk | Dwarves client/NDA data and third parties' private messages. |
| family-office, household, trading positions, tg-cleanup | Family and personal data. Cloud reasoning is off-limits per `feedback_no_sensitive_family_data_to_cloud`. |
| Skill routing on raw prompts, memory notes, backlog staging | Session content leaves the host. Local embeddings do the job. |
| Any launchd job without a P4 fallback | The vendor had a full auth outage at GA. An unattended job must treat "no verdict" as the current path. |

## No-Jev fixes the audit found

None of these need Jev. Listed so they do not get lost in the absorption noise.

| Fix | Where | Status |
|---|---|---|
| Stop the subject-word stateful trap: skip subject matching when every changed path is under `tests/`, or match only the conventional-commit scope | `lib/gate/proof-ledger.sh` `classify()` stateful grep | Being fixed in a separate PR |
| Populate the empty JIT skill-hint map from observed misses | `hooks/context-hints-skills-map.json` / `CONTEXT_HINTS_SKILLMAP` | Open, 0 entries today |
| Turn on fuzzy dedup, or route dedup through prose-rag | `hooks/harvest.py` (`HARVEST_FUZZY_THRESHOLD` defaults to off), `backlog-stage.py` | Open |
| Mine normal/full misfires into lane flag pins | `lane-telemetry.sh misfires` | Open, about 22 of about 36 real mismatches sit on that boundary |
| Separate test-fixture runs from the live telemetry corpus | `~/.local/state/dwarves-kit/logs/runs/` | Open, about 14k START lines across 768 ledger files, tests appear to write into the live corpus, filed as a board row below (ID-930) |

## Security / trust screens for any future shadow test

Per the audit (07 section 7.2): pin `jev-1.13.0`, set a timeout of at least 1.5s,
validate that returned probabilities sum to about 1, use the full distribution plus
margin rather than the single `confidence` field (the superterminal PR's own fixtures
show `confidence` alone can be wrong on gibberish input), and log which backend actually
decided. A transport error means "no verdict", fail-open to whatever the current
non-Jev path already does. No shadow test in this estate may write a decision back into
a live gate, hook, or kit flow, it may only log alongside the existing decision.

## Board rows

Four PARK rows and one QUEUED row filed on the dwarves-kit board: ID-926 (digest
triage), ID-927 (task-type second opinion), ID-928 (tg-signal-parse), ID-929
(query-aware compression), ID-930 (run-log test pollution, queued). See
`_meta/BACKLOG.md`.
