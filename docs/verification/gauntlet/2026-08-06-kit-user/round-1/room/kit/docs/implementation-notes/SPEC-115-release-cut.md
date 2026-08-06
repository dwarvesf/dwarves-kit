# Implementation notes: SPEC-115 release-cut

Delta from the spec.

- **08 is a GATE + FINAL.** The loop PREPARES everything (changelog, bumps, pin, BREAKING map, tag +
  Release text as files, HELD-pair review) and OPENS the PR, then STOPS. It never tags, never merges,
  never runs `gh release create`. Those are Han's manual steps (documented in the proof's "What Han
  does" block); ship.md is NOT extended for this once-per-cycle step (per assumption 08).
- **HELD-pair review ran FIRST** (before the tag), per assumption 08. Both #117 + #124 SHIP-AS-IS;
  findings in `docs/releases/v2.0.0/held-review.md`. Two informational (non-blocking) notes recorded
  for Han: #117's marking-scope limitation (ID-089) and #124's shipped-inert `--files` future-wiring
  contract.
- **Consumer grep, honest result:** the three old rename-names appear in sibling consumer repos ONLY
  in historical research/notes/BACKLOG + the plan-for-mega-goal invocation-template , NO live
  `subagent_type:` dispatch wiring. Documented in the BREAKING section as such (not a false "all
  clean").
- **CHANGELOG folds, does not rewrite:** the accumulated `[Unreleased]` content (kit-hardening +
  kit-telemetry waves) is retained under `[2.0.0]`; the kit-face per-spec bullets + BREAKING are
  added above it; a fresh empty `[Unreleased]` sits on top. Released sections untouched.
- **tool.toml was the drift:** it sat at 1.6.0 while VERSION/plugin.json were 1.7.0 (the v1.7.0 cut
  missed it). The new three-surface pin makes that class fail the suite next time.
- **fish noclobber gotcha:** `printf > VERSION` failed (fish `noclobber`); used a python write. Noted
  for the next release-cut author.
