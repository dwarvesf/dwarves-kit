# Sub-goal 02: docs index expansion

**Merge policy:** auto
**Time budget:** 1-2 hours.
**Proof:** run-table: every link in the expanded docs/README.md resolves (link-check loop over relative paths) · the 23-line front door is byte-identical above the extension point · `docs/verification/README.md` linked, untouched in place (ship-gate still keys on it, `test-meta.sh` proof-marker checks green).
**Depends on:** none.
Model: sonnet
Effort: medium
**Branch:** feat/kit-face-02-docsindex
**PR base:** master

## Outcome

The EXISTING `docs/README.md` (23 lines, good front door) extends into a navigable map: thematic clusters over the 111 specs (with a `lib/spec-index.sh` pointer for enumeration, no per-file rows), the 30 ADRs, research/retro/absorption, plus the two dirs the current index misses entirely , `implementation-notes/` (48 files) and `verification/` (76 files, LOAD-BEARING: ship-gate keys on its README; link, never move). Files stay put; no unpinned counts anywhere.

## Quality bar

A maintainer finds any record class in one hop; a user still reads "you do NOT need this to USE the kit" first. Zero counts that can rot (the README 11-vs-18 lesson).

## How to close the loop

`/spec` + `/spec-validate` first. Then a link-check over every relative path in the file + `bash tests/test-meta.sh` (proof-marker + spec-README pins unaffected). Assumptions: ROADMAP 02 block.

**Done =** expanded index committed, all links resolve, front-door text verbatim, no unpinned counts, test-meta green.

## Scope edges

**In:** docs/README.md only.
**Out:** new per-dir READMEs (specs/ + verification/ already have theirs, deliberately); moving any file.
**Not:** an auto-generated index (spec-index.sh is pointed at, not wrapped); annotating 111 specs per-file.

## Where to look

docs/README.md (current 23 lines), docs/specs/README.md (numbering convention, test-pinned), lib/spec-index.sh, the dir listing of docs/.

## PR body

Expands docs/README.md into a thematic map (adds implementation-notes/ + verification/, spec clusters + spec-index.sh pointer); front door verbatim; files stay put; no unpinned counts. Verify: link-check run-table in the proof + `bash tests/test-meta.sh`. Roadmap: ops-toolkit `_meta/megagoals/kit-face/ROADMAP.md`.

## Notes

<empty>
