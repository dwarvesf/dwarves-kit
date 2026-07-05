# Sub-goal 06: advisor-visibility (an invocation path + a first-class ledger row for advisor P5/P6)

**Merge policy:** auto
**Time budget:** 1.5-2 hours of loop work
**Proof:** full reviewable proof: fixture rid whose review-team pass + convergence-gate dispatch produce `advisor` gate-ledger rows (`mode=P5|P6 findings=N`) parsed by the merged kit_gates reader; both NC captures.
**Design:** obvious
**Depends on:** 02 (stacked; same files: `commands/review-team.md`, `agents/advisor.md`).
Model: sonnet
**Branch:** `feat/advisor-visibility`
**PR base:** `feat/review-findings-memory`
**Over-test: no** (observability only; the two NCs below are still absolute)

## Outcome

2026-07-04 audit finding: advisor is reachable ONLY via `/kit:review-team` Step 2b (critique P5) or a conductor-level convergence-gate dispatch (P5+P6), and it leaves NO ledger row even when it runs (free text inside `review`/`ACTION` lines). In subagent-delegate mega runs, workers self-record review rows "instead of a /kit:review-team dispatch" per the worker contract, so advisor had NO invocation path at all in the recent runs (zero trace across 96 rid logs). Fix, observability only:

(a) **Emit**: every advisor dispatch records `bash lib/gate-ledger.sh record "$rid" advisor ran "mode=P5|P6 findings=N actor=<git user.name>"`; review-team Step 2b embeds it; grammar MUST parse with the merged kit_gates reader (#683). RID CONVENTION (pin in DECISIONS): convergence-gate rows (advisor P5/P6, /kit:verify's rows) record under the FINAL sub-goal's rid, the de-facto convention of the older TIER-4 ACTION lines (kit-telem-05, kit-clean-05 logs), so observatory queries find close-time rows deterministically. Telemetry side needs NO code change: kit_gates takes gate names as free strings and gate-yield is data-driven (verified 2026-07-04 against adapters.py + cli.py).
(b) **Invocation path in delegate runs**: the convergence-gate step in `commands/mega.md` (+ the skill mirror if the never-diverge checklist requires) names advisor P5 (critique) + P6 (over-suggest) as an explicit in-harness dispatch at the assembled-stack close, with the emit.
(c) `agents/advisor.md` documents its emit so future dispatch sites inherit it.

## Quality bar

NO gate-requirement change: advisor stays advisory; a missing advisor row never blocks anything. Fail-open: an emit failure must not fail the review. NCs are absolute: (1) honest-zero, a rid with no advisor dispatch renders zero/absent in kit_gates, never fabricated coverage; (2) emit-failure-never-blocks, with a visible warning.

## How to close the loop

- Fixture: drive the review-team Step 2b flow (or the dispatch step) on a fixture rid; capture the advisor rows; parse with the kit_gates reader (run the actual query).
- NC 1: fixture rid without advisor rows -> lens renders honest zero. NC 2: emit blocked (read-only ledger dir) -> review output intact + visible warning captured.
- Kit-adopted: run the lane, record gates before push.

**Done =** fixture advisor rows parsed by kit_gates + both NC captures committed.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: kit stack fully done. 3. `DECISIONS.md`: the advisor KV grammar verbatim. 4. EXIT.

## Scope edges

**In:** `commands/review-team.md` (Step 2b emit), `commands/mega.md` convergence-gate step (+ skill mirror per the never-diverge checklist), `agents/advisor.md` (emit note), tests/fixtures.
**Out:** the ops-side self-attested-row split (cockpit ID-270); any new advisor capability; changes to P5/P6 content.
**Not:** a required advisor gate; a new gate-matrix row; auto-dispatch anywhere beyond review-team + the convergence gate.

## Where to look

2026-07-04 audit (this session's LAB_LOG line + PR body): advisor dispatch sites `commands/review-team.md:114-138`; older convergence-gate ACTION-line traces in the kit-telem-05 / kit-clean-05 / pane-viewer-push rid logs; kit_gates grammar tolerance in harness-observatory `DECISIONS.md`.

## PR body

Advisor visibility: first-class `advisor` gate-ledger rows (`mode=P5|P6 findings=N`) emitted from review-team Step 2b + an explicit convergence-gate dispatch step in mega.md, parseable by kit_gates. Observability only, advisor stays advisory, fail-open. NCs: honest-zero + emit-failure-never-blocks. Stacked on review-findings-memory. Covers the 2026-07-04 advisor-invisibility audit finding.

## Notes
