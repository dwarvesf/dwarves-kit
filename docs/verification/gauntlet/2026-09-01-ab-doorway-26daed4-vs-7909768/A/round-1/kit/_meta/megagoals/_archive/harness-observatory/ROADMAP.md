# Mega-goal: harness-observatory

**Destination:** The harness benchmark loop CLOSES on the observatory side: `gate-yield` / `defect-correlation` / `deviation-rate` answer "which process steps actually pay" on real ledger data, the session/safety/memory telemetry planes are read (numbers only), and the north-star metrics (token efficiency, time-to-done, coverage) are standing queries behind one `ledger digest` command.
**Quality bar:** A wrong benchmark is worse than none. Every sub-goal is OVER-TESTED with load-bearing negative controls (a correctly-skipped gate never flagged ceremony; an honest zero-deviation note never flagged SUSPECT; no transcript CONTENT ever lands in the sessions table; the memory sweep never mutates a memory).
**Terminus:** non-deployable (a local CLI lens): build + merge IS the terminus, closed by the PAYOFF RUN (the first real benchmark scorecard rendered from live ledgers) in TIER-4. The missing deploy/UAT gates are intentional.
**Sibling run:** `kit-absorptions` (dotfiles + dwarves-kit lanes) runs IN PARALLEL, disjoint repos, portfolio wave v1 practiced. Cross-mega coupling: its grill/emit sub-goals hold until THIS run's sub-goal 01 (the `kit_gates` reader) merges.
**Stacking tool:** gh (stacked PRs, one ops-toolkit chain)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-04 (drafted; launch pending Han's go)

## Sub-goals

- [x] 01-kit-gates-lens, `kit_gates` per-gate table + `gate-yield` correct on golden fixture + real 63+ run ledgers, `auto`, PR #683
- [x] 02-defect-correlation, `git_fixes` adapter + `defect-correlation` (retrospective control arm), `auto`, PR #684
- [x] 03-deviation-rate, `impl_notes` adapter + UNDER-SPECCED/CLEAN/SUSPECT + `unknown-density` anomaly, `auto`, PR #687
- [x] 04-anomalies-advisor, ceremony + token-runaway + time-to-done advisor detectors, `auto`, PR #688
- [x] 05-sessions-digest, numeric-only `sessions` adapter + `safety` counters + `ledger digest` scorecard, `gate`, PR #690, merged a6e0c72 (privacy-boundary review passed)
- [x] 06-memory-lens, memory-verify sweep + `memories` hygiene lens, `auto`, PR #692, merged 7d6c94d (was #691, remade stacked on #690)

## Dependencies

Single stacked chain: 01 -> 02 -> 03 -> 04 -> 05 -> 06 (every sub-goal touches
`tools/ledger-observatory/**`, so the chain is honest, not decorative). 06 logically
needs only 01's schema pattern; if the run drags it is the safe one to re-base onto
01 and pull forward.

## Assumptions (front-loaded answers, baked at draft time; flip before launch)

1. **05 is `gate` (privacy boundary):** the sessions adapter reads ALL
   `~/.claude/projects/*` transcript dirs but extracts NUMBERS ONLY; the privacy NC
   (fixture fake-secret provably absent from the db) is load-bearing; Han reviews
   the field whitelist before merge.
2. **06 scope v1:** memory STORES only (repo `.claude/memory/`, auto-memory project
   dirs, MEMORY.md indexes); global CLAUDE.md sweeping deferred. Propose-only,
   NEVER auto-delete.
3. **Digest is a manual command** (no cron/daemon; minimum infra).
4. **SPEC numbers conductor-reserved up front** (spec-next reserve); workers never
   self-pick (wavefront race).
5. **`reason=` column ships tolerant-of-absence:** the emitter arrives via the
   kit-absorptions sibling; this run's parser must not require it.
6. **Launch after the `worktree-benchmark-followup` family PR merges** so the loop
   runs against the scaffold on main.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read pr; do
      gh pr view "${pr#PR #}" --json state,reviewDecision,statusCheckRollup
    done
