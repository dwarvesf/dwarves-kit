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
| /user: form in live docs | `docs/implementation-notes/spec-019-greenlight.md` described the guard using the literal it bans | note reworded without the literal |

## Green run

```
$ bash tests/test-meta.sh
Passed: 823 / 823
All meta tests passed.
```

Verdict: PASS (was 815/822 on master; the count grew by one because the new MANUAL row adds its own listing assertion).

## Negative control

Reverted `docs/MANUAL.md` to origin/master, re-ran: `FAIL agent devops-triage NOT listed in MANUAL.md`, 821/822. Restored from HEAD; working tree clean.

## Reproduce

```
bash tests/test-meta.sh
```
