# Implementation notes: session-audit

Delta from `lib/session/audit/SPEC.md`; decisions the spec did not pin down.

## 2026-07-14 17:10 Triage speaks the staging currency, not a bespoke row

Context: the first triage cut printed its own kanban row shape
(`| ?? | change | ... | queued |`) to stdout. A full-repo ETL inventory (19
pipelines) showed the kit already has ONE proposal currency: `## [staged]`
blocks in `_meta/backlog-staging.md`, rendered by `lib/learn/staging-format.py`
and used by BOTH `learn propose` and `stats anomalies --propose`, with
`board promote` as the human gate (ADR-0034 decision 1).
Decision: triage now renders through `staging-format.render_block` and dedups
via `existing_keys` (staging + board), appending to the same buffer. The audit
fields map: change -> title, effect/finding -> Intent, change + metric contract
-> Approach, confidence -> `#u-*` tag, report+owner+finding -> Source citation.
`--dry-run` prints and writes nothing.
Why: a third proposal currency for the same Learn gate is exactly the
fragmentation this work set out to kill; dedup against rejected/expired states
comes free with the shared grammar (a weekly audit MUST NOT re-propose what a
human already rejected).
Alternatives: keep the kanban rows and teach `board` to ingest them (rejected:
two grammars, one gate).
Impact: triage's contract changed before anyone consumed it (verb is unreleased
in this PR); smoke grows 18 -> 24 with idempotence + dry-run negative controls.

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

## 2026-07-14 19:30 Review-lens findings (the ones worth remembering)

Two lenses (advisor + correctness/security) on the SPEC-200 PR found seven defects the green
suite could not see. Recording the two that generalize:

1. **A hand-list beside a deriving resolver is a bug waiting for the next key.** The
   skill-curator alias shipped as a 9-name list next to `cfg()`, which DERIVES
   `SKILL_CURATOR_<KEY>` from its argument. The 8 cfg-only keys silently lost their alias, so
   `CC_SI_ENABLED=false` (an operator who had turned the curator OFF) resolved back to `true`
   and re-enabled it, with no warning. `stats` had already done it right by putting the alias
   INSIDE the resolver. Same problem, two designs, in one PR. Fix: alias in `cfg()`.
2. **A negative control must plant the violation in a shape the author did NOT imagine.**
   Every NC in the first contract suite planted the violation in the exact form its own regex
   matched, so four rules were vacuous (blind to single-quoted `environ.get`, extensionless
   executables, flagless `rg`, and a comment name-dropping the renderer). The NCs proved the
   regexes matched themselves.

Also: `render_block` did not collapse newlines, so LLM-authored text (which now reaches it via
session-audit, i.e. transcript content, i.e. attacker-influenceable) could forge a second
`## [staged]` block into the proposal buffer. Sanitized at the ONE renderer, which is exactly
the leverage SPEC-200 I1 exists to give.
