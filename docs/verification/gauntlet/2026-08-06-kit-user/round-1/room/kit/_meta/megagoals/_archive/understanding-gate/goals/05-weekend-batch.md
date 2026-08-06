# Sub-goal 05: weekend batch-learning flow (Flow B, the option)

**Merge policy:** auto
**Time budget:** 3-5 hours (cross-repo: dwarves-kit collection + ops-toolkit/dotfiles learning integration).
**Proof:** run-table: the flow COLLECTS the debt-ledger's deferred+waved items (from 02/04) + their impl-notes + explainers (03) · routes through learning-day-process (batch) + learning-ledger (dedup+route) · evergreen bits flush to til (privacy-stripped) · NEGATIVE CONTROL: an already-ENGAGED (paid) item is NOT re-collected, and a non-significant change never entered the ledger · it REUSES the existing learning skills (grep proves the invocations).
**Depends on:** 02 (the significance markers to collect) + 03 (the explainer material).
Model: sonnet
Effort: high
**Branch:** feat/ug-05-weekend-batch
**PR base:** feat/ug-03-explain (stacked on 03)

## Outcome

Flow B (the debt paydown): a weekend batch-learning session that reads the **debt ledger** , the week's DEFERRED and WAVED items (SG-04) plus their impl-notes (`docs/implementation-notes/`, the agent-side decision delta that fed the worthiness signal) and `/kit:explain` artifacts , and routes them through the operator's EXISTING learning kit: `learning-day-process` (batch a period's material into the track structure), `learning-ledger` (multi-store dedup + route to durable homes), `deep-understand` (a gated walkthrough for the ones worth it), evergreen concepts flushed to `til` (privacy-stripped). This is the SDD<>learning MERGE point AND the debt statement: the debt consciously postponed inline gets paid down here, so it never becomes untracked "lost the plot". An IMPROVEMENT to the current weekend cadence, not a parallel system.

## Quality bar

REUSE, don't rebuild: the flow orchestrates learning-day-process/learning-ledger/deep-understand/til , if it forks a new batching or dedup engine it failed. Only SIGNIFICANT changes are collected (02's markers), so the batch is proportional. Privacy gate on the til leg (the standard strip). Cross-repo dotfiles discipline: chezmoi source -> apply -> stage+commit in ONE call.

## How to close the loop

`/spec` + `/spec-validate` first (resolve open-fork 3: cadence + where it runs , a Han-invoked skill vs. a scheduled job). Then a fixture week: collect -> route -> til, with the non-significant-excluded NC + the skill-reuse grep. Assumptions: ROADMAP 05 + open-fork 3.

**Done =** the batch collects a fixture week's significant changes + explainers, routes through learning-day-process + learning-ledger + til, excludes non-significant (NC), reuses the existing skills (grep-proven), tests green.

## Scope edges

**In:** the collection step (reads 02's markers + 03's artifacts), the learning-skill orchestration, the til flush, the cadence entry point (skill or job), tests. Dotfiles/ops-toolkit half for the learning-side wiring.
**Out:** the inline quiz gate (04, Flow A , the batch is the async alternative); generating explainers (03); the significance heuristic (02).
**Not:** a new batching/dedup/capture engine (reuse learning-day-process/learning-ledger/til); collecting non-significant changes; publishing to til without the privacy strip.

## Where to look

the ops-toolkit skills `learning-day-process` (batch a period into the track), `learning-ledger` (the dedup+route spine), `deep-understand` (the gated walkthrough), `knowledge-capture` (the til leg + privacy strip), lib/significance-classify.sh (02, the markers to collect), the learning cadence launchd job pattern (if the flow is scheduled), ADR-0031 §3.

## PR body

Weekend batch-learning flow (ADR-0031 §3, Flow B): collects the week's significant changes + `/kit:explain` artifacts, routes through learning-day-process + learning-ledger + deep-understand, flushes evergreen bits to til (stripped). Reuses the existing learning skills. Stacked on #<03's PR>. Verify: fixture-week collect->route->til + non-significant-excluded NC + skill-reuse grep. Roadmap: ops-toolkit `_meta/megagoals/understanding-gate/ROADMAP.md`.

## Notes

<empty>
