# Proof of done: FEATURES.md freshness regeneration

Change: `docs/FEATURES.md` is a generated projection
(`lib/registry/feature-registry.sh generate`). It went stale after #380
changed which tests reference several features (the projection tracks those
refs), failing the SPEC-219 freshness check in `test-meta.sh` (798/799).
Regenerated; no hand edits.

## Green run

| Field | Value |
|---|---|
| Command | `bash tests/test-meta.sh` |
| Exit | 0 |
| Verdict | PASS (799/799; was 798/799) |

Freshness + determinism assertions:

```
PASS docs/FEATURES.md is fresh (regenerate == committed, SPEC-219)
PASS feature-registry generator is deterministic (double run byte-identical, SPEC-219)
```

## Negative control (revert -> RED -> restore)

Reverted `docs/FEATURES.md` to `origin/master`, re-ran the freshness check:

```
FAIL docs/FEATURES.md is fresh (regenerate == committed, SPEC-219)
```

Restored via `git checkout HEAD -- docs/FEATURES.md` (from the feature
commit): back to PASS.

## Notes

- Deterministic: a second `feature-registry.sh generate` leaves the same
  changeset (no nondeterministic bytes).
- This was the mechanical task chosen for the passive-Mini-runner pilot
  (ID-472 pattern). The autonomous run on the Mini was BLOCKED: the Mini's
  queue-launched `claude` session is not logged in ("Please run /login"),
  which only Han can fix interactively. The fix was therefore done on the
  authed Air. The Mini-runner autonomous path remains blocked on two
  Han-only auth gaps: the `claude` session login and the `gh` token.
