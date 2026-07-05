# Sub-goal 06: memory-lens (memory-verify sweep + `memories` hygiene lens)

**Merge policy:** auto
**Time budget:** 1.5 hours of loop work
**Proof:** run-table: sweep over the real memory stores (captured paydown table) + fixture assertions (dead ref flagged, live ref not, stale-date flagged) + the never-delete NC; coverage-delta row (stores covered vs global-CLAUDE.md deferred).
**Design:** bearing
**Depends on:** 05 (chain position; logically only needs 01's schema pattern)
Model: sonnet
**Branch:** `feat/lo-memory-lens`
**PR base:** `feat/lo-sessions-digest`
**Over-test: yes** (light: fixtures + the never-delete NC)

## Outcome

Stale-but-confident gets a meter: a memory-verify sweep command (manual-first, weekend-batch paydown pattern, NO daemon) walking the memory stores (repo `.claude/memory/`, built-in auto-memory project dirs, MEMORY.md indexes), extracting referenced paths/flags/commands, testing them against the live environment, and emitting a paydown table (dead refs, notes unverified > 180d). Plus a `memories` lens table (`store, slug, written, last_verified, dead_ref_count`) + a hygiene anomaly (propose-not-autofile). Dead-ref rate = the v1 retrieval-precision proxy.

Covers: ID-251.

## Quality bar

PROPOSE-ONLY, the sweep never deletes or edits a memory (Han's NEVER-delete rule is absolute here). Reference extraction is conservative: only clearly-pathlike/flag-like tokens; a false dead-ref costs trust.

## How to close the loop

- Fixtures: a memory referencing a dead path -> flagged; a live path -> not; an old note -> stale-flagged; asserted.
- Never-delete NC (load-bearing): the sweep run leaves every memory file byte-identical (shasum before/after over the fixture store), asserted.
- Real run: sweep over this repo's stores; captured paydown table = the run-table (expected to catch the known MIGRATED tombstones).
- Kit lane + gate-ledger records before push.

**Done =** fixture assertions + never-delete NC green AND the real paydown table captured in the proof.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HOT `HANDOFF.md`: next is TIER-4 close (the ops chain is complete); name the payoff-run commands. 3. `DECISIONS.md`: extraction heuristics + staleness threshold. 4. EXIT.

## Scope edges

**In:** sweep command + memories adapter + hygiene anomaly + tests + proof; `tools/ledger-observatory/`.
**Out:** global `~/.claude/CLAUDE.md` reference sweeping (explicit v2, in the coverage-delta); any memory WRITES.
**Not:** runtime recall instrumentation; auto-fixing dead memories; a daemon or cron.

## Where to look

`research/2026-07-04-scaling-the-harness-audit.md` §4.1; the repo-memory shape in global CLAUDE.md (Memory routing section); `.claude/memory/MEMORY.md` here; weekend-batch.sh in dwarves-kit for the paydown-table shape.

## PR body

Memory-verify sweep + `memories` hygiene lens: the stale-but-confident meter. Propose-only, never deletes (NC-asserted). Stacked; review after sessions-digest. Covers ID-251.

## Notes

