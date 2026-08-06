# Mega-goal: gate-review-absorptions

**Destination:** Human gates get a real surface and reviews get a memory: gate decisions carry structured feedback into the ledger (plannotator `--gate --json` trial), review lenses stop re-flagging what was already rejected (per-repo rejected-findings ledger + `findings=/rejected=` emits), the observatory can price a lens's false-positive cost (`review-yield`), the ops contracts absorb the three one-liner batches (stale-ADR inversion, gate-deny triage-first contract, counterfactual/honest-negative principles), and advisor P5/P6 dispatches become first-class ledger rows (2026-07-04 audit: advisor had no invocation path in subagent-delegate runs and no ledger row even when dispatched).
**Quality bar:** NO gate-REQUIREMENT changes anywhere (surfaces, memory, and emits only; the plannotator wrapper is an OPTIONAL surface for gates that already exist). Every emitter lands with its reader in the same PR family (kit_gates is merged, #683). Behavior-bearing sub-goals (02, 03, 04) are OVER-TESTED with load-bearing negative controls.
**Terminus:** non-deployable: build + merge closed by the convergence-gate demo run (one REAL human-gate review through the wrapper with its ledger line; `review-yield` over a golden fixture + real ledgers; a live review dispatch showing the stale-ADR lens + the rejected-findings check).
**Stacking tool:** gh (stacked PRs, two per-repo stacks)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final
**Started:** 2026-07-04 (drafted; launch guard CLEARED same day, both siblings closed; advisor P5/P6 pre-launch pass applied; LAUNCHABLE)

## Sub-goals

- [x] 01-stale-adr-inversion, code-vs-ADR drift is a finding + docs never blanket-mute, kit review surfaces, `auto`, PR #172, merged e54397b
- [x] 02-review-findings-memory, per-repo rejected-findings ledger + pre-flag check + `findings=/rejected=` emit, `auto`, PR #173, merged 0904e74
- [x] 03-plannotator-gate-trial, verified install + `pl-gate` wrapper + ledger emit + live trial + phone checkpoint, `gate`, PR #698, merged e79ae40 (verdict: PARK the binary, KEEP the pattern; live trial reached no approve/deny, fail-open proven twice with the real binary)
- [x] 04-review-yield-lens, rejected-findings adapter (counts only) + `review-yield` FP-rate query, `auto`, PR #701, merged 3b2221e
- [x] 05-ops-contracts-batch, three one-liners (deny contract, numbers-with-an-n, counterfactual/honest-negative principles) each with its own check, `auto`, PR #697, merged 4400fce
- [x] 06-advisor-visibility, advisor P5/P6 dispatch step at the convergence gate + first-class `advisor` ledger row (observability only), `auto`, PR #174, merged b628549 (SPEC-145)

## Dependencies (only if non-trivial)

- Two per-repo stacks: dwarves-kit 01 -> 02 -> 06; ops-toolkit 05 -> 03 -> 04.
- 04 depends on 02 (the `findings=/rejected=` grammar + the repo-file format must exist first). Cross-stack: verify 02's PR merged via `gh pr view` before starting 04.
- Reader-first is already satisfied: the `kit_gates` reader merged as harness-observatory PR #683; 02's emit grammar must PARSE with it (its DECISIONS.md names the grammar tolerance).

## Assumptions (front-loaded answers, baked at draft time; flip before launch)

1. **LAUNCH GUARD: hold until BOTH sibling megas close** (ID-260 harness-observatory, ID-261 kit-absorptions; check their ROADMAP boxes all flipped + final PRs merged). Reason: 01/02 overlap kit-absorptions' dwarves-kit command edits (review/grill/emit sweep touches the same files); 04 overlaps harness-observatory's ledger-observatory work; 05 touches OPERATE.md which ID-246 may convert to an overlay. Verify, do not assume.
2. **Gates: 03 and the final PR only.** 03 is `gate` because the trial IS Han's hands-on review session (he drives the browser UI) and it installs a third-party binary. Everything else machine-verifiable, auto.
3. **plannotator install is verify-then-run, never curl|bash:** download the release binary + verify checksum/attestation, pin the version in the experiment README. The wrapper never feeds it secrets; server binds loopback (Tailscale reach is a checkpoint, not a config change shipped by default).
4. **No new required gate:** the wrapper is an optional SURFACE for existing human gates. If plannotator is absent or the decision JSON is malformed, the gate falls back to the current manual flow, visibly (fail-open surface, fail-visible logging; never a silent pass).
5. **OPERATE.md mirror rule for 05 (RESOLVED pre-launch):** ID-246 landed (dotfiles #195). ops `_meta/megagoals/OPERATE.md` stays the full local copy; the skill bundles the portable copy with a never-diverge contract. 05 mirrors its two generic contract lines into the portable copy in the same run (scoped chezmoi apply only).
6. **SPEC numbers conductor-reserved up front** in dwarves-kit (01/02); ops-toolkit sub-goals need specs only where the repo contract demands (03/04 write specs under the tool/experiment; 05 is docs-only).
7. **Cross-repo conductor rule** (same as kit-absorptions): dwarves-kit sub-goals get hand-made worktrees (`git -C <repo> worktree add ...`), never Agent isolation:worktree from the ops-toolkit session.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read pr; do
      gh pr view "${pr#PR #}" --json state,reviewDecision,statusCheckRollup
    done
