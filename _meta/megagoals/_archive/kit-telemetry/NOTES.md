# NOTES , kit-telemetry

## Active blockers

<none yet>

## Proposed additions

- 2026-07-02: instrumentation , this is the FIRST auto-bottom-up stacked run (kit-hardening used integration-branch). Capture how the retarget-child-before-delete dance behaves in practice: any auto-closed child PR, any conflict on retarget, any gate-checked merge refusal. The lesson feeds the plan-for-mega-goal skill's merge-mode guidance.
- 2026-07-02: instrumentation , second production run of the HANDOFF/DECISIONS contract (first was kit-hardening). Same capture: per-sub-goal token/turn data via the run ledgers.

### From the TIER-4 advisor (P6 over-suggest, 2026-07-02) , NOT built, for Han to triage

1. **[HIGH] Do ID-085 next** (emit `gate-ledger start` in `commands/mega.md`'s sub-goal dispatch). Root cause blinding eval metrics 1/2/4/7; the fix is cheap , `commands/assign.md:126` already calls `start` correctly, mega.md just needs the same call. Every future SPEC-073 re-run is worthless until this lands.
2. **[HIGH] Wire ID-089** (auto-mark held/gated-final PRs as draft + `do-not-merge`) into `commands/mega.md`'s PR-open step. This wave's held-final PR is the first live test of the SPEC-100 guard, which only defends a MARKED PR; the manual-mark path already slipped once (premature board flip, caught by the advisor). Automating the mark removes both failure modes.
3. **[MED] A lint/hook: `status: shipped` in a BACKLOG row requires a non-placeholder PR ref.** Generalizes the premature-flip finding; cheap now because SPEC-100 already built PR-state reading (`_pr_info`) a lint could reuse.
4. **Re-run SPEC-073's eval once ID-085 lands**, on a START-complete corpus (the eval report + SPEC-098/099 caveats already flag this as the natural fast-follow).
5. **Bundle ID-086 + ID-087 with ID-085** in one noise-reduction wave (board-match-by-PR/ID; stop test fixtures leaking DWARVES_KIT_LOG_DIR-unset writes into the real corpus) , both would otherwise pollute the #4 re-run.
6. **ID-088 (edit-vs-mention signal)** is now cheaply scoped: this wave's own docs are fresh over-classification fixtures. Lower urgency (fails safe toward over-gating).
7. **[STRUCTURAL] Extend the SPEC-100 code-guard pattern to stack-base verification** (dependent sub-goal PRs must base off their parent , currently prompt-level only, same shape as the ID-083 gap SPEC-100 just closed). Pair with ID-084 (DAG-wavefront), now unblocked.
8. **Turn the "measure, don't assert" lens on the kit's OWN LAB_LOG/impl-notes discipline** , the parent audit verdicted them ceremony at the general-operator level; this wave never checked whether dwarves-kit's SDD loop enforces or wastes that ceremony specifically. Now measurable with the durable telemetry substrate this wave built.

## Event log

2026-07-02 HH:MM · scaffold · kit-telemetry mega-goal created from board rows kit ID-082/067/083 + ops ID-149/150 (post-kit-hardening reconciliation chain). 5 sub-goals, gh-stacked + auto-bottom-up + gated-final, cross-repo (roadmap in ops-toolkit, PRs in dwarves-kit).

2026-07-02 · EXECUTED (loop complete) · All 5 sub-goals built + verified. SG-01..04 auto-merged bottom-up (dwarves-kit PRs #112/#113/#114/#115); SG-05 (final) was held per gated-final; Han then authorized the merge (PR #117 merged a07d992; draft+do-not-merge cleared, the guard had refused its own auto-merge as designed). TIER-4 close ran on the assembled result: integration-verifier=WIRED (5/5, all suites green), advisor P5=3 doc/board findings fixed + P6=8 additions surfaced above, cross-cutting security=1 BLOCKER fixed (gate-ledger check() unknown-lane vacuous-pass -> fail-closed) + 2 SHOULD-FIX. Auto-bottom-up merge posture worked cleanly: since I merged each sub-goal before creating the next, no child-retarget dance was needed (each branched off the updated master); no auto-closed child PRs, no retarget conflicts, no gate-checked merge refusals on the auto tier. Kit board rows ID-082/067/083 flipped inside their PRs; eval/review findings filed as ID-085..089; ops rows ID-149/150 flipped shipped in the close-out branch. Notable: CI portability (bash-3.2 empty-array + set -u) cost 4 red-CI rounds on SG-05; isolated via a diagnostic dump. CLOSED: Han merged PR #117 (a07d992); ID-083 -> shipped + ROADMAP 05 box checked in this close-out. Mega-goal complete.
