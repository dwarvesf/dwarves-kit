# Implementation notes -- ship-gate-review-verdict

No spec: the operator brief fixed the rule, the key, the tests and the docs scope. Proof: `docs/verification/ship-gate-review-verdict.md`. These notes record only what the brief left open.

## Decisions

| Decision | Why |
|---|---|
| The rule lives in `lib/gate/ship-rules.sh` (`ship_rule_review_verdict`), called from the hook right after the spec resolves | Same home and shape as `ship_rule_identities`; the hook stays a thin caller. The mega merge gate is not wired in, because it does not call the identities rule either. |
| It runs before the lane checks | It reads only the spec, so it holds whatever `Lane:` says and whether or not `lane_gates` is on. Its own key is the only switch. |
| Key `review_verdict`, default ON | The docs called this block HARD, so the shipped default has to match. The kit already has two default-on keys (`board_row_gate`, `fixture_identities`); `DEFAULT_ON` in `gate-policy.sh` and the kit-root `kit.toml` both say true. |
| The switch is read at the merge base | Same as the floor and the identities rule: a branch cannot switch off the check it is held to. An opt-out must already be on the default branch. |
| Only the exact heading `## Review` counts, and the LAST canonical verdict line wins | `/kit:review` replaces the section, so a re-run clears the block. `## Review disposition` and `## Spec validation` carry other verdict vocab (`REVISE`, `SOLID`) and must not match. |
| A line counts only when its value starts with `SHIP`, `FIX THEN SHIP` or `DO NOT SHIP` | Real specs carry `Verdict: SECURE`, `APPROVED`, `Verdict after fixes: SHIP.` and a bold form. Non-ship words neither block nor clear. The unfilled template `SHIP / FIX THEN SHIP / DO NOT SHIP` reads as SHIP. |
| Code fences are skipped | A review that quotes the grammar in a fence must not block itself. |
| `commands/review-team.md` now says the verdict is a `###` line inside the spec | Its report template shows `## Verdict:`, a level-2 heading that would end the `## Review` section and hide the verdict from the gate. |

## Deviations from the brief

None. The other docs that claimed the block (`docs/MANUAL.md`, `docs/architecture.md`, `docs/workflow-map.md`, `docs/hooks.md`, `commands/ship.md`) were corrected too. `docs/SYSTEM-DESIGN.md` and `docs/design/kit-uml.html` are left to the session that owns them.
