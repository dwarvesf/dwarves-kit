# Sub-goal 06: Reasoning sweeps (backlog triage + learning flush)

**Time budget:** ~3-5 hours loop work, after 05 merges
**Depends on:** 05 (built on the sweep harness); reuses `_meta/learned-ledger.md` (also fed by 04)
**Branch:** feat/cc-elevation-06-reason
**PR base:** feat/cc-elevation-05-sweeps

## Outcome

Two reasoning-grade sweeps built on the 05 harness: (a) backlog-triage reads each repo's BACKLOG/TODOs/FIXMEs, dedups, re-prioritizes, and flags stale rows into one digest (the work-intake "reconcile the board", automated); (b) learning-flush flushes any leftover `queued` rows in `_meta/learned-ledger.md` to their homes and proposes cross-session merges (the "same concept seen 3x" case). Both need judgment, so they run as a Routine or a Hermes-agent job, not a pure script.

## Quality bar

These propose, humans dispose: triage emits a suggested re-order + flags, it does not silently rewrite the board; flush proposes merges for review, it does not auto-merge concepts into durable homes. Output is a clean digest a human acts on in minutes.

## How to close the loop

- The triage module, given fixture backlogs across two repos: emits a deduped, re-prioritized digest with at least one stale-row flag.
- The learning-flush module, given a fixture ledger with 2 queued rows + 1 cross-session duplicate: proposes flushing the 2 and merging the duplicate, writing nothing to durable homes without confirmation.
- Stacked on 05: the PR diffs against `feat/cc-elevation-05-sweeps`; note this in the body so reviewers read 05 first.
- Lane via lane-classify; extend `tools/repo-sweep/docs/proof-of-done.md` (repo-sweep is now multi-feature) with these two runs.

**Done =** the two reasoning sweeps run on fixtures (triage emits a deduped reprioritized digest with a stale flag; learning-flush proposes flush+merge writing nothing to durable homes unconfirmed), proof updated, on PR #NN (stacked on 05) with green CI.

## Scope edges

**In:** the backlog-triage + learning-flush reasoning modules in `tools/repo-sweep/`, fixtures, tests, proof update.
**Out:** the deterministic sweeps (05); the auto-harvest hook (04); actually scheduling (runbook only).
**Not:** auto-rewriting `BACKLOG.md`; auto-flushing to til/GLOSSARY without human confirm; a new tool dir (extend repo-sweep).

## Where to look

The 05 harness, `_meta/BACKLOG.md` + the `_meta/board` wrapper + the work-intake skill, `_meta/learned-ledger.md` + the learning-ledger skill (flush + dedup), knowledge-capture consolidation.

## PR body

Outcome: two reasoning sweeps on the repo-sweep harness, backlog-triage (dedup/reprioritize/flag stale) and learning-flush (flush leftover queued ledger rows + propose cross-session merges).
Verify: run both on fixtures (triage digest with stale flag; flush proposes flush+merge, nothing written to durable homes unconfirmed).
Stacked on #<05 PR>; review after it.
Roadmap: `_meta/megagoals/cc-elevation/ROADMAP.md` (sub-goal 06).

## Notes
