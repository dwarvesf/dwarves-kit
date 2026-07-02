# Spec cc-hyg-04: reduce the Stop-hook + override tax

Cross-repo: sub-goal 04 of the ops-toolkit **cc-hygiene** mega-goal
(`ops-toolkit/_meta/megagoals/cc-hygiene/goals/04-kit-stop-tax.md`). Lane `full`
(kit-machinery: `proof-gate`/`proof-ledger` are hard-gated). Gate-ledger run
`cc-hyg-04`.

## Problem (measured, from research/2026-07-02-process-benchmark.md §1, §5)

1. **slop-cleaner Stop hook** re-flags the same 7 files up to 19 times in a row:
   8,483-8,526 runs / 30d, p50 ~497ms (p95 5.4s, max 11.5s), ~70 min/month
   wall-clock, all re-reporting already-seen files. It has no resolution memory.
2. **session-state-save** runs every Stop: 8,483 x ~271ms ~= 38 min/month. No
   debounce; keep-or-debounce never decided from the data.
3. **proof-gate override** blanket-passes the whole branch once a slug is
   overridden, even when the unproofed remainder touches SOURCE files. The single
   recorded override (2026-07-01, rtk-611) shipped a broken source change reverted
   9h later.

## Solution (decided)

1. **slop-cleaner: KEEP + add resolution memory** (not drop). The hook's signal is
   useful; the tax was pure repetition. A per-session seen-state file
   (`$DWARVES_KIT_LOG_DIR/slop-seen-<session_id>.tsv`, `path<TAB>contenthash`) makes
   a flagged file nudge once per session and re-nudge only when its content changes.
   Keyed by `session_id` (read from the Stop payload); stale seen-files (>7d) pruned.
2. **session-state-save: DEBOUNCE (change-gated), not keep-every-Stop.** A fingerprint
   (`branch | uncommitted-count | HEAD`) is stored; an unchanged Stop skips the whole
   rewrite+rotate. Chosen over time-debounce because it has zero staleness risk (the
   existing state is still correct when nothing changed) and over keep-every-Stop
   because that was ~38 min/month of pure churn. The dirty count excludes the hook's
   own `.claude/session-state/` output (`--untracked-files=all` + filter), else the
   fingerprint never stabilizes.
3. **proof-gate override: reject source remainder.** An override no longer blanket-passes
   the branch. If the diff contains application source-code files (by extension) OUTSIDE
   a `deploy/` path, the override is rejected and a real proof of done is demanded. Deploy
   scripts under `deploy/` stay override-able (verified via deploy-proof/UAT per SPEC-095).
   This closes rtk-611 (a non-deploy source change shipped under a blanket override).

## Scope

**In:** `hooks/slop-cleaner.sh`, `hooks/session-state-save.sh`,
`lib/proof-gate.sh` / `lib/proof-ledger.sh` override path, and their tests.
**Out:** other Stop hooks (em-dash-fix, secret-guard-stop, citation-guard , measured
cheap), gate-ledger durability (kit-telemetry SG-01 owns it), anti-rationalization.sh.
**Not:** no hook-framework rewrite, no new config surface beyond what the fix needs,
no touching kit-telemetry's scope.

## Verification (proof of done)

- New tests: (a) slop-cleaner flags a file; a second Stop with unchanged content
  stays silent; a content change re-flags. (b) proof-ledger override on a batch
  whose remainder touches a source file is rejected / demands the exclusion list.
- The full kit CI suite (test-hooks, test-proof-visual-evidence, test-meta,
  test-e2e, test-lane-classify, test-ledger-durability, test-meta-agent,
  test-orchestrate, test-review-team-plants, test-role-classify) stays green.
- Run-table committed: each command + exit 0 + real stdout slice; plus a
  before/after note on hook behavior.

**Done =** both new behaviors covered by green tests AND the full kit suite passes,
proven by the committed run-table.
