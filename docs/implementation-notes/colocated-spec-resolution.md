# Implementation notes: colocated-spec-resolution

Spec: `docs/specs/SPEC-386-colocated-spec-resolution.md`. This file holds the delta from the spec only.

## Decisions not in the brief

- Scope grew from three callers to five. `proof-ledger.sh` `_negctl_required` and `pitch.sh` `_find_spec` carry the same root-only glob (spec DEC-5).
- Gates think, design and design-critique are overrides, not runs. The operator brief fixed the problem and the done list; the draft PR exists for the operator's design review.

## Open questions for the operator

- Depth 4 and the tie-break (root, then shallow, then C order) are the two choices to confirm on the draft PR.
