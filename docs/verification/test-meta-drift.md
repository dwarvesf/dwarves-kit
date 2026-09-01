# Proof of done: doc-projection drift repair (ID-639)

Seven pre-existing `tests/test-meta.sh` failures on master, all drift from the SPEC-239-era ship that added `devops-triage` and reworded AGENTS.md paths without the doc-projection sweep. Root cause per failure and the fix:

| Failure | Root cause | Fix |
|---|---|---|
| agent devops-triage NOT listed in MANUAL.md | agent shipped without a MANUAL row | row added to the agents table |
| devops-triage OFF the ADR-0029 naming axis | read-only agent with no axis suffix | grandfathered pending operator rename decision (recorded in the test comment + ID-639 row) |
| architecture.md inventory 65 vs 68 | `/kit:battery`, `/kit:greenlight`, `devops-triage` never got V-phase rows | three rows added (battery: right arm; greenlight + devops-triage: cross-phase) |
| V-model lens missing 'Design critique (default full lane, opt-in normal)' | SPEC-231 renamed the phase in the cycle table; the lens prose still said "(opt-in)" | lens prose updated to the canonical phase name |
| AGENTS.md/WORKFLOW.md intake story (SPEC-057) | PR #402's `${DWARVES_KIT:...}` quoting broke the test's fixed-string greps (`backlog.sh" next`); the story itself never left | test greps made quote-tolerant (`backlog\.sh"? next`); AGENTS.md untouched |
| docs/FEATURES.md stale | registry drift | regenerated via `lib/registry/feature-registry.sh generate` |
| dead user-prefix form in live docs | `docs/implementation-notes/spec-019-greenlight.md` described the guard using the literal it bans | note reworded without the literal (as is this row: the battery's acceptance leg caught the first draft of this very table reintroducing it) |

## Green run

```
$ bash tests/test-meta.sh
Passed: 823 / 823
All meta tests passed.
```

Verdict: PASS (was 815/822 on master; the count grew by one because the new MANUAL row adds its own listing assertion).

## Negative control

Reverted `docs/MANUAL.md` to origin/master, re-ran: `FAIL agent devops-triage NOT listed in MANUAL.md`, 821/822. Restored from HEAD; working tree clean.

## Battery round (three independent legs, parallel)

- **Acceptance verifier (sonnet)**: caught a self-inflicted regression the author missed: the first draft of THIS proof doc reintroduced the banned user-prefix literal in its failure table (822/823). Fixed, re-verified 823/823. It also independently confirmed all 7 fixes file-by-file.
- **Reviewer (opus)**: verdict SHIP. Confirmed the grep loosening is not a weakening (the old fixed-string pin asserted a string that no longer exists anywhere: a dead pin). Two LOWs, both fixed: a third phase-name spelling at WORKFLOW.md's rigor table; the grandfather list now mirrored into ADR-0029 as a live register with a no-row-no-entry rule.
- **Advisor (sonnet)**: named the root cause both drift repairs (ID-467, ID-639) skipped: no gate runs the projection checks at ship time. Fixed in this branch: `lib/gate/doc-projection-check.sh` (grep-only subset, ~0.1s: MANUAL rows per agent, architecture inventory count, V-model lens phases) wired into `hooks/ship-gate.sh`, firing only on kit-repo pushes whose diff touches a projection surface; the slow FEATURES regen (~17s) stays in the full suite. Escape: `DWARVES_KIT_SKIP_DOC_PROJECTION=1`. The advisor also flagged mid-session master movement; the branch was merged onto current master and the suite re-run before ship.
- Gate negative control: a scratch tree with the devops-triage MANUAL row deleted → `doc-projection: agent 'devops-triage' has no docs/MANUAL.md row`, exit 1. Positive control (simulated): running the new ship-gate block's logic against this branch (its diff touches MANUAL/architecture/WORKFLOW → trigger matches, check exits 0) allows the push. Note the hook that ran on this branch's actual push was the INSTALLED master copy; the new gate goes live for real pushes once this merges and the installed checkout pulls.
- Dogfood note: the new check script itself tripped the hooks-roster parity pins while it lived in `hooks/` (819/823), which is those pins working; it moved to `lib/gate/` where a non-event helper belongs.

## Reproduce

```
bash tests/test-meta.sh
bash lib/gate/doc-projection-check.sh "$(git rev-parse --show-toplevel)"
```
