# v2.0.0 HELD-pair review , #117 + #124 (release-blessing re-review)

Fresh-context re-review of the two PRs merged "[HELD for Han]" that this tag blesses. Both re-run
green on the release branch. **Neither blocks the v2.0.0 tag.**

## PR #117 , mega-merge code-level gate/held-final exclusion (SPEC-100) , SHIP-AS-IS
- `_merge_exclusion` runs BEFORE the gate; a held PR is refused even with passing gates; malformed
  state fails closed (refuse). Hold-label parsing uses quoted `read -ra` (the glob-injection BLOCKER
  is fixed); bracketed-title marker via pure-bash `case`-glob (macOS-CI-safe).
- The bundled gate-ledger `check()` fail-closed fix verified: a valid zero-gate lane (`tiny`) still
  passes; an unknown lane fails closed. No regression (`test-mega-merge` 30/30, `test-mega-reconcile`
  35/35).
- Informational (non-blocking): the guard defends a MARKED PR; it cannot synthesize a mark (B1,
  filed ID-089). The held PRs in this wave ARE marked, so the guard protects them. A non-canonical
  hold label (`gated final` with a space) normalizes to `gatedfinal` and would not block , an
  under-block edge; not practical since `mark` applies the canonical `do-not-merge` exactly.

## PR #124 , lane-classify edit-vs-mention `--files` signal (SPEC-105) , SHIP-AS-IS
- `--files` escalates the `kit-machinery` gate only on an actual `lib/`/`hooks/` edit; without
  `--files` the text-only path is byte-unchanged. Both directions pinned (`test-lane-classify`
  23/23). bash-3.2 empty-array + word-split footguns handled.
- Informational (non-blocking): the capability ships INERT , grep of `commands/`/`lib/`/`hooks/`
  confirms ZERO live callers wire `--files`. The one hazard (under-gating if a future caller sources
  `--files` from model free-text instead of `git diff --name-only`) is documented in-code + SPEC-105
  + flagged by TIER-4 security; watch it when the ID-088 wiring lands.

## Verdict
Both clean, fail-safe, well-pinned, green on the release branch. Nothing blocks the tag.
