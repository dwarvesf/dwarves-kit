# SPEC-114: docs index expansion

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

`docs/README.md`'s "What's here" table is a good front door but an INCOMPLETE map: it omits two
whole record classes , `implementation-notes/` (per-spec build-deltas) and `verification/`
(proof-of-done records, LOAD-BEARING: the ship-gate keys on `verification/README.md`) , and offers
no way to navigate the large `specs/` set. A maintainer cannot find every record class in one hop.
The mega-goal (roadmap: ops-toolkit `_meta/megagoals/kit-face/`, assumptions 02) resolves this: keep
the front door verbatim, extend it into a navigable thematic map, no rotting counts.

## Solution

Extend `docs/README.md` BELOW the existing content (front door byte-identical) with a "## The full
record, by theme" section grouping every record class:
- **Design + decisions:** `specs/` (enumerate via `bash lib/spec/spec-index.sh`, no per-file rows, no
  rotting count; per-namespace local numbering noted) + `decisions/` (ADRs).
- **Build trail:** `implementation-notes/` + `verification/` (the two the quick map omits) +
  `retro/`. `verification/README.md` is flagged LOAD-BEARING (ship-gate consumer named), linked,
  never moved.
- **Sourcing:** `research/` + `absorption/`.
No counts in the map (the only pinned counts are the README directory-layout ones, SPEC-113); one
central map, no new per-dir READMEs (`specs/` + `verification/` keep their own, deliberately).

## Verification

```bash
cd dwarves-kit
# front door byte-identical (extension is addition-only)
git diff master -- docs/README.md | grep -E '^-' | grep -v '^---'   # empty
# both omitted classes + the load-bearing link + the spec-index pointer present
grep -q 'implementation-notes/' docs/README.md && grep -q 'verification/README.md' docs/README.md
grep -q 'lib/spec/spec-index.sh' docs/README.md
# every relative link resolves; no rotting counts in the map
bash tests/test-meta.sh   # proof-marker + spec-README pins unaffected (661/661)
```

## After state

- `docs/README.md`: the front door verbatim + a "## The full record, by theme" section (all record
  classes, spec-index pointer, verification/ load-bearing link, no counts).
- `docs/verification/docs-index.md`: link-check run-table + front-door-verbatim proof.

## Scope edges

**In:** `docs/README.md` only.
**Out:** new per-dir READMEs (specs/ + verification/ have theirs); moving any file; the README hero
(01); the `architecture.md` prose-count drift (a different doc surface, filed to mega NOTES).
**Not:** an auto-generated index (spec-index.sh is pointed at, not wrapped); per-file annotation of
the specs; any rotting count.

## Open questions

The proof is a link-check + the front-door-verbatim `git diff` + the existing proof-marker/spec pins
staying green , 02 adds no new test-meta pin (scope is docs/README.md only), so it cannot regress
another sub-goal's pins. Counts are deliberately absent from the map (a count rots; SPEC-113's
directory-layout parity pin is the one place counts are asserted, and the map says so).
