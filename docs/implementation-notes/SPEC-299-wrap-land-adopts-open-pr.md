# Implementation notes: SPEC-299 wrap land adopts an open PR

The delta from the spec at `docs/specs/SPEC-299-wrap-land-adopts-open-pr.md`.

## Decisions

- One Opus validation lens stood in for the six-lens spec panel. It returned NEEDS-REVISION with seven findings, all taken: an open-by-head stub answer, draft handling through `gh pr ready`, a fork filter, reuse of the `_open_own_prs` login read and compare, pinned failure texts and streams, a note for ignored flags, and the two `commands/wrap.md` lines.
- Found on dwarves-kit #704, the first full-lane PR the session opened by hand before landing.
- Review (Opus) found three contract gaps, all fixed: the kept-flags note went to stdout, unparseable lookup JSON fell through to create, and an adopted PR number was not checked as numeric. Unparseable JSON and a non-numeric number now refuse as a failed lookup.

## Open questions

- None.
