# Sub-goal 05: the boundary in one table, and the terminus check

**Merge policy:** auto
**Time budget:** 2 hours
**Proof:** run-table: dwarves-kit `WORKFLOW.md`, `AGENTS.md`, `README.md`, learning-kit `README.md` + `docs/ARCHITECTURE.md`, context-kit `README.md` each carry the same three-row boundary table (kit, learner or plane, what it owns, the seam it fills); `docs/specs/SPEC-249-estate-seams.md` `## Seams` lists `wrap.learn`; `bash bin/config seams --check` exits 0 on the operator machine with `wrap.after`, `wrap.learn`, `knowledge.root` all `filled` and `Filled by` naming the kit that filled each; `bash bin/kit-health` (if present) clean; NEGATIVE CONTROL: the boundary lint from 01 is RED when one moved skill's old name is planted in `commands/wrap.md`.
**Depends on:** 02, 03, 04.
Model: sonnet
Effort: medium
**Branch:** docs/learning-boundary-terminus (one per repo)

## Outcome

The doc statement of what this mega-goal made true, in one table copied verbatim into each kit's front door so a reader of any one kit sees the whole cut. The terminus check is `config seams --check` on the operator machine: every seam filled, every filler the kit the table names. Then the mega-goal folder moves to `_meta/megagoals/_archive/`.

## Quality bar

One table, no prose restating each move. Each README names only what that kit owns and points at the table for the rest. No count of skills anywhere (the roster will change).

## How to close the loop

Write the table once in ROADMAP.md, paste it, open one docs PR per repo, run the terminus check, archive.

**Done =** the proofs above and the folder archived.

## Scope edges

**In:** the docs, the SPEC-249 row, the terminus check, the archive move.
**Out:** any code beyond the seams table row.
**Not:** a new doc file; the table lives in files that already exist.
