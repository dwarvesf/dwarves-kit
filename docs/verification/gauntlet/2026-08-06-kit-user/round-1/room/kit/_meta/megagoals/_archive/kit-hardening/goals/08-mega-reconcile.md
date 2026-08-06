# Sub-goal 08: mega-lane reconcile (/kit:mega mirror + kit-side auto-merge enforcement)

**Merge policy:** auto , a new command doc + ship-layer enforcement path, testable via fixtures with the escape negative control.
**Time budget:** 3-5 hours.
**Proof:** run-table , `/kit:mega` mirrors the skill's decompose + front-load-questions + per-run merge config · auto-merge fires ONLY past a passing ship-gate (negative control: a failing/missing gate NEVER auto-merges , the ADR's named mis-build risk) · deploy/UAT terminus engages for a deployable mega-goal and not for an inert one · team-run per-PR-review config honored.
**Depends on:** 07 (the deploy/UAT terminus reuses deployable-done's classifier + proof shape).
Model: opus
Effort: high
**Branch:** feat/kit-harden-08-megamirror
**PR base:** mega/kit-hardening

## Outcome

The kit-side half of the mega lane exists (ADR-0028 P2/P3, the brief's SG-C). A `/kit:mega` command mirrors the ops-toolkit `plan-for-mega-goal` skill so bare-kit teammates get the same authoring shape: decompose, gather EVERY sub-goal's clarification question ONCE up front (front-load checkpoint), set the per-run merge config. And the ship layer gains auto-merge ENFORCEMENT: once a sub-goal's ship-gate passes (ADR-0024/0025 still hard-gate), the merge action is automated up to the gated-final human review; for deployable mega-goals the run terminates at the deploy/UAT gates, never past them.

## Quality bar

Auto-merge RIDES ON the ship-gate, never bypasses it , "auto-merge escaping the ship-gate" is the ADR's explicitly named mis-build risk, so the negative control (failing gate -> no merge, logged) is the load-bearing test. Per the decision brief's Q4 cut: NO kit-side merge-autonomy beyond the config , the default is auto-to-final for operator-owned runs, per-run configurable for team runs (a teammate may require per-PR review). The command is a MIRROR of the skill, not a fork: same checkpoint semantics, no drift between the two.

## How to close the loop

Author `commands/mega.md` mirroring the skill's decompose/front-load/merge-config beats; wire the auto-merge action into the ship layer (gate-ledger + ship-gate read path); wire the deploy/UAT terminus off 07's deployable classifier. Verify:

```
cd dwarves-kit && bash tests/test-mega-reconcile.sh   # mirror parity; auto-merge past green gate; NEGATIVE: failing gate never merges; terminus fires deployable-only; per-run config honored
```

Captured evidence: run-table at `docs/verification/mega-reconcile.md` , mirror-parity row, green-gate auto-merge row, the failing-gate-never-merges negative-control row, terminus rows (deployable engaged / inert skipped), team-config row.

**Done =** `test-mega-reconcile.sh` proves `/kit:mega` exists mirroring the skill's front-load + merge-config, auto-merge fires only past a passing ship-gate (negative control green), and the deploy/UAT terminus engages for deployable work only.

**Kit-adopted repo? Record the gates.** `bash lib/lane-classify.sh classify "/kit:mega mirror + ship-layer auto-merge enforcement"` (expect `full`), record build + review via `lib/gate-ledger.sh` before push.

## Handoff on completion

1. Flip 08's box, PR # + SHA.
2. HOT `HANDOFF.md`: if this is the last sub-goal, next action = the TIER-4 close gate on the assembled `mega/kit-hardening` stack, then the LAB_LOG close-out entry.
3. WARM `DECISIONS.md`: the mega lane's kit half now enforces auto-merge past gates and terminates at deploy/UAT; authoring stays in the skill, `/kit:mega` mirrors it.
4. Report IN records, EXIT.

## Scope edges

**In:** `commands/mega.md`, the ship-layer auto-merge action + its gate checks, the deploy/UAT terminus wiring, per-run merge config, tests.
**Out:** the activator loop (`/goal` / ralph , ADR-0017 activator-agnostic); `lib/orchestrate.sh` (exists; activator-side); the skill itself (ops-toolkit-owned; the command mirrors it).
**Not:** kit-side merge-autonomy on shared repos beyond the per-run config (brief Q4 cut); a DAG/scheduler (ADR-0028 Out-of-Scope, GSD-v2); PR creation/dispatch/scheduling beyond planning (SPEC-034 boundary).

## Where to look

`commands/` sibling shape (execute.md, dispatch.md), the ship layer (`hooks/ship-gate.sh`, `lib/gate-ledger.sh`, `lib/proof-gate.sh`), ADR-0028 P2/P3 + the "Where each layer lives" table, the decision brief's SG-C refinement, ops-toolkit `plan-for-mega-goal` SKILL.md (the mirror source), sub-goal 07's deployable classifier.

## PR body

Adds the kit-side mega-lane reconcile (kit-hardening SG-C, ADR-0028 P2/P3): `/kit:mega` mirroring the plan-for-mega-goal skill (decompose + front-load checkpoint + per-run merge config) and ship-layer auto-merge enforcement that rides the ship-gate (negative control: a failing gate never merges), with a deploy/UAT terminus for deployable mega-goals.

Verify: `bash tests/test-mega-reconcile.sh`. Proof: `docs/verification/mega-reconcile.md`.

Roadmap: `ops-toolkit/_meta/megagoals/kit-hardening/ROADMAP.md`. On the integration branch after SG-07.

## Notes

<empty>
