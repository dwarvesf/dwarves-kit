# Implementation notes: validate-round-verb

Delta from `docs/specs/SPEC-363-validate-round-verb.md`.

Spec written and recorded; fresh-context validation pending. Build not started, so no deviation yet.

## Decided at spec time, flagged for the validators

- Brackets move from per-episode to per-round (DEC-B). This rewords one step 5 sentence ("so `dur_s` measures the validation"). A reviewer may treat it as a semantic change to the `caught=` meaning: `caught=true` now marks the round that caught, not the episode.
- The incomplete stop keeps step 5's unpaired `design-record end` (Out of Scope). Pairing it would add a `design-record skipped` record that step 5 does not name today.
