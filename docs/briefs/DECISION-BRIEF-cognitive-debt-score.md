# Decision Brief: cognitive debt score (two tiers) + opt-in peer benchmark

Date: 2026-07-25 · Source: operator ask ("cognitive debt rating and ranking between members based
on usage and kind of question they ask, concrete vs meta"), designed in-session against ADR-0031
and the existing ledger/telemetry substrate. Status: DRAFT (design agreed in session). Consuming
rows: ID-440; stacks on ID-411 (Insights report is the delivery surface) and ID-430 (badge/verify
pattern for the benchmark). Business half (paid-tier placement, benchmark marketing): dfoundation
DF-153 umbrella.

## Verified current state (2026-07-25)

- Cognitive debt is already a first-class kit concept: ADR-0031 (understanding gate) defines
  engage/defer/wave, `lib/classify/significance-classify.sh` produces the tap/wave verdicts,
  `gate-ledger.sh debt` (SPEC-123) writes the append-only `| DEBT |` markers, and
  `lib/learn/weekend-batch.sh` (SPEC-126) is the paydown reader/closer with explicit disposition
  rules (engage = PAID; wave/defer = COLLECT).
- `lib/gate/quiz-gate.sh` records quiz outcomes; `lib/telemetry/lane-telemetry.sh` + stats
  projections carry delegation ratio, rework loops, acceptance data (the ID-411 substrate).
- THE GAP: none of these signals are aggregated per PERSON. And a brand-new kit user has NO ledger
  at all (no gates fired yet), so a ledger-only score cold-starts at zero signal.

## The design: two confidence tiers, one score

```
TIER 1  INFERRED   day-one, transcripts + git only, labeled "estimate"
        signals:   accept latency vs diff size   (large diff merged in seconds = unread)
                   re-derivation questions       ("where are we" about own recent work)
                   concrete:meta prompt mix      (question-kind classifier, sibling of
                                                  lane-classify; all-concrete = consuming
                                                  without modeling)
                   rework returns                (git: edits to just-shipped work in N days)
                   inspection ratio              (hand-read/edited lines vs agent-accepted)

TIER 2  LEDGER     once gates run, the trusted tier
        signals:   quiz first-try pass rate      (quiz-gate)
                   engage / defer / wave ratio   (DEBT ledger)
                   paydown latency               (defer -> weekend-batch mark-paid)

CALIBRATION        members with BOTH tiers validate the inferred proxies against ledger
                   truth (the same precision-tracking pattern as learn-propose, ID-294).
                   Tier 1 stays labeled "estimate" until its precision is measured.

DELIVERY           a section in the ID-411 Insights weekly report: score + trend + the
                   ONE thing to change (doctor pattern). Local, key-gated per ID-410.

BENCHMARK (v1.5)   opt-in, anonymized percentile, signed via the ID-430 verify pattern.
                   NOT a manager-visible leaderboard: that is the surveillance/Goodhart
                   shape N7 rejects; members would game quizzes performatively. Needs
                   the server, same boundary ID-411 already states for peer benchmarks.
```

The Tier 1 report doubles as an onboarding baseline: "your debt profile from week 1, before any
gate fired."

## Build order (strict)

1. **Per-member aggregation over Tier 2**: a `stats` projection that groups the existing DEBT +
   quiz + telemetry markers by author. Zero new stores; ledgers are already append-only files.
2. **Question-kind classifier** (concrete vs meta) as a sibling of `lane-classify`, run over
   session transcripts locally; emits a mix ratio only. Ships with its own precision measurement
   (N6: no unmeasured smart feature).
3. **Tier 1 proxies** (accept latency, rework returns, inspection ratio, re-derivation detection)
   from transcripts + git; folded with the classifier into the inferred score.
4. **Insights report section** (rides ID-411 v1): score + trend + one recommendation.
5. **v1.5 benchmark** (after the server exists): opt-in percentile via the ID-430 signed-stat
   path.

## Conformance (§6)

- **N6**: consumes measurable signals the kit already emits; the inferred tier is itself measured
  against the ledger tier before being trusted (the meta-loop).
- **N7**: makes cognitive off-load visible per member; benchmark is self-owned and opt-in.
- **Conflict surfaced**: a ranking/leaderboard between members conflicts with N7 as stated
  (surveillance + gaming). Reshaped to the opt-in benchmark; if the maintainer wants the
  manager-facing ranking anyway, that is a separate, explicitly-argued decision.
- **Propose, never dispose**: the score recommends; no automated consequence attaches to it.

## Exit criteria

- A member with zero ledger history gets a labeled inferred score from their first week of usage.
- A member with ledger history gets the trusted score, and their inferred score's error against it
  is recorded (calibration set grows with every dual-signal member).
- The Insights report renders the section locally with no new stores and no server.
- No surface ranks members against each other without their opt-in.
