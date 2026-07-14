# Implementation notes: session-audit

Delta from `lib/session/audit/SPEC.md`; decisions the spec did not pin down.

## 2026-07-14 14:30 Vocabulary reconciliation (five legs, not a new taxonomy)

Context: the first cut of `docs/feedback-loop.md` named its own five stages
(COLLECT -> REPORT -> TRIAGE -> ENHANCE -> MEASURE), a parallel vocabulary to
the kit's canonical five legs (ADR-0034 Specify/Execute/Observe/Govern/Learn),
whose Learn leg already owns the propose gate (`learn propose`, `stats
anomalies --propose`, `/kit:retro`).
Decision: rewrote the doc in leg terms; `run` = the deep Observe pass, `triage`
= a Learn-leg proposer under the same propose-don't-dispose rule (ADR-0034
decision 2/5). The five stage words survive only as lowercase prose.
Why: one engine one truth; a second taxonomy for the same loop is exactly the
drift the kit-fold contract forbids.
Alternatives: keep both vocabularies cross-referenced (rejected: two names for
one thing is how docs rot).
Impact: feedback-loop.md, audit README, module-registry row.

## 2026-07-14 14:35 No kit.toml audit sub-toggle

Context: the config surface (SPEC-198) could carry a `session.audit` toggle.
Decision: none added; the coarse `[modules] session = true` covers it, and the
audit only runs when explicitly invoked (no hook, no cron inside the kit), so
there is nothing to toggle off.
Why: no config for a value that never changes; an unused knob is debt.
Impact: if a consumer later schedules audits from a kit-owned hook, revisit.

## 2026-07-14 14:40 No slash command; dispatcher wiring only

Context: the session subsystem has no slash-command surface at all (none of
the 32 commands/ call session-*), and an audit run costs ~$3.5 and ~10 min.
Decision: wire `session.sh audit)` (the one-grammar entry, ADR-0034 decision 7)
plus registry/env rows; do NOT add a /kit:audit command or an onboard-wizard
offer in this PR.
Why: an expensive weekly/on-demand CLI fits the existing session-module shape;
a slash command invites casual per-session runs of a $3.5 tool. Onboard wizard
touch is a separate surface with its own spec (SPEC-199) and review.
Alternatives: /kit:audit thin wrapper (parked; add if usage shows demand).
Impact: reachable as `session audit run|triage` wherever the session module's
PATH shim is installed; onboard/config wizard integration stays open debt,
logged in the PR description.

## 2026-07-14 14:45 Digest overlap left standing, with a named fold path

Context: three weekly artifacts now read the same transcripts (stats digest
numeric scorecard; session-intel deterministic digest; the audit report).
Decision: coexist for now; feedback-loop.md documents the division of labor
and names the fold path (audit report becomes a session-intel source) instead
of building it.
Why: session-intel is deterministic-by-design (its README forbids LLM inside);
folding an LLM artifact in deserves its own decision, not a rider.
Impact: revisit when the third digest demonstrably annoys.
