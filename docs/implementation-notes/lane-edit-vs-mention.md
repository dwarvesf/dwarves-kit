# Implementation notes: lane-edit-vs-mention (SPEC-105)

Delta from the spec. Reference, do not restate.

## 2026-07-02 machinery-file predicate = "touches lib/ or hooks/"

**Context:** the goal says "escalate on an actual edit to `lib/<machinery>.sh`."
**Decision:** the predicate is any touched path under `lib/` or `hooks/`, not a match against the
specific machinery basenames.
**Why:** SPEC-069 already defines the enforcement layer as `lib/`/`hooks/`; reusing it is drift-free
(no second copy of the basename list to rot alongside `_hard_re`). Matching specific basenames would
duplicate that list.
**Tradeoff:** conservative -- a non-enforcement `lib/` helper edit also escalates. Fail-safe
(over-gate, never under-gate), consistent with SPEC-069. Noted in SPEC-105 Open questions.

## 2026-07-02 scoped to the kit-machinery gate only

**Context:** the classifier has 7 hard-gates.
**Decision:** the `--files` discriminator applies ONLY to `kit-machinery`; `auth`/`data-model`/
`audit-security`/etc. are unchanged.
**Why:** those are semantic (a task ABOUT auth is auth-risky regardless of which files it touches);
only `kit-machinery` is a file-surface proxy. A pin asserts `auth` stays `full` even with a doc
`--files`.

## 2026-07-02 --files parsed in the dispatch, stripped before classify_core

**Context:** `classify_core` is also called by `escalate` (on spec text) and `lane_check`.
**Decision:** `_extract_files` runs in `main` for `classify`/`explain`/`check`, sets the
`FILES`/`FILES_SET` globals, and passes the remaining (description) args via a `REMAIN` array;
`escalate` never sets them so `FILES_SET=0` -> legacy path.
**Why:** keeps `classify_core`'s signature (`"<desc>"`) intact for its other callers. Each CLI
invocation is a fresh process, so the globals start at defaults with no cross-call leakage.
**bash 3.2:** `REMAIN` is expanded with the set-u-safe `${REMAIN[@]+"${REMAIN[@]}"}` idiom (same
class of bug the SG-04 mark verb hit); verified on `/bin/bash` 3.2.57.
