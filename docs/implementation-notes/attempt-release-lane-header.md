# Implementation notes: attempt-release-lane-header

Delta from `docs/specs/SPEC-293-attempt-release-lane-header.md`.

## 2026-09-16 The `- ` list-marker form is refused, not accepted

Context: the follow-up asked to accept a leading `- ` list marker "if other headers in existing
specs use it".
Decision: refuse it.
Why: the marker is used in specs for prose bullets, not headers. `docs/specs` already contains
`- **Lane:** the WORKFLOW.md risk tier (...)` as a sentence. Accepting the marker would make
`grep -m1` pick that line and parse `the` as the lane, which is a wrong lane silently enforced
instead of a visible block.
Impact: only `Lane:`, `**Lane**:` and `**Lane:**` parse.

## 2026-09-16 `commands/spec.md` did not emit a Lane header at all

Context: the follow-up expected the spec template to already emit the plain form.
Decision: add `Lane: [tiny | normal | full | bug | backfill ...]` to the template block in Step 3.
Why: the template wrote `Generated:` and `Status:` and no lane, so every spec `/kit:spec` writes
starts lane-less and the ship-gate blocks it later. That is the upstream half of the same defect.
Impact: one added line in the template; no behavior change to the command's steps.

## 2026-09-16 `tests/test-picture-section.sh` keeps the old parse

Context: that suite mirrors the ship-gate parse in a local helper.
Decision: leave it.
Why: it is a test fixture reader, not a parser the kit ships, and all of its fixtures use the
plain header. Changing it would widen the diff with no behavior covered.
Open questions: if a future fixture uses a bold header, that helper needs the same expression.
