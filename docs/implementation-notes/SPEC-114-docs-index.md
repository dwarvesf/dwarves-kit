# Implementation notes: SPEC-114 docs-index

Delta from the spec.

- **Front door kept verbatim; extension appended below** (not woven into the existing "What's here"
  table). git diff shows ZERO removed lines , the quick map stays as the getting-started subset;
  the new "## The full record, by theme" section is the complete map incl. the two omitted classes.
- **No unpinned counts** , the map points at `bash lib/spec/spec-index.sh` for spec enumeration and
  describes each dir without a rotting number. The only pinned counts are the README directory-layout
  ones (SPEC-113's parity pin); the map explicitly says so.
- **verification/ LOAD-BEARING** , linked, never moved; the note names `hooks/ship-gate.sh` as the
  consumer so a future maintainer does not relocate `verification/README.md`.
- **02 adds no test-meta pins** (scope: docs/README.md only) , the proof is a link-check + the
  existing proof-marker/spec-README pins staying green. No test-meta footer edit, so no risk to
  other sub-goals' pins.
- **Not fixed here (out of 02's docs/README.md scope):** `docs/architecture.md:77` prose total
  ("15 agents / 40 entries") is stale (now 24 agents / 51 entries) , flagged in the 09 review, a
  DIFFERENT doc surface; filed to mega NOTES for TIER-4 / a follow-up (the gate-covered inventory
  TABLE is correct; only the human-readable prose total is uncovered).
