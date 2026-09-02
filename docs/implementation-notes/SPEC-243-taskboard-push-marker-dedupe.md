# Implementation notes, SPEC-243 taskboard push marker dedupe

Delta from the spec only. The spec is the contract; this file records what the
build decided that the spec left open, and what it deliberately did not do.

## 2026-09-02 DEC-004: an adoption counts as work on the run that writes it

Context: the spec's open question asks whether `src_adopt` should count toward
`Plan.empty()`.

Decision: `Plan.empty()` stays unchanged (adoption excluded). The run that
performs an adoption prints `adopted N` via `describe()`'s per-adoption line,
so that run is visibly not idle even though `empty()` reports no board/spoke
mutation was queued. A steady-state run afterward (the adopted bid is now in
`known`) prints `(nothing to do)`, matching the reading operators already
trust.

Why: an adoption is plan data with a real side effect (a state-map write), so
the run that makes it should not look silent, but it queues no create/update
against either side, which is what `empty()` guards for dry-run headers and
callers that branch on "is there work to preview." Splitting "did this run
change anything" from "does the plan contain a create/update" keeps both
readings honest.

Alternatives: fold `src_adopt` into `empty()`'s tuple (rejected: a dry-run
preview would then claim work exists for a row that produces zero writes to
either side, which is the "(nothing to do)" reading dfoundation operators
already rely on); print no adoption line at all (rejected: silent state
mutation is what caused the tag-filter stopgap `.kit.toml` in the first place).

Impact: `describe()` gains one line class (`= spoke <bid> bound to an existing
Notion page (pull marker), not created`), rendered whenever `plan.src_adopt`
is non-empty, dry-run or live.

Open questions: none.
