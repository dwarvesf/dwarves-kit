# Implementation notes: session observe burn (SPEC-254)

## 2026-09-10 14:40 Lane chosen below the classifier

Context: `lane-classify.sh` returned `full` for the task text.
Decision: ran the `normal` lane; the ledger `start` records chosen `normal`, classified `full`.
Why: SPEC-240 set the precedent for a read-only projection with no store and no schema change.
Alternatives: `full` (14 gates) for one view in an existing CLI.
Impact: none on behavior; the gate set is spec, build, ship plus lite gates.
Open questions: confirm the classifier should weigh "read-only view" lower.

## 2026-09-10 15:05 Sidechain tokens count in the window totals

Context: the spec filters `ctx` to the main chain and rolls subagent transcripts into the parent, but does not say whether sidechain entries inside the main file count toward `reqs` and token totals.
Decision: count them. Only `ctx` filters to the main chain.
Why: subagent spend is real spend of that session; "rolls into parent" implies it.
Alternatives: main-chain-only totals, which would hide fan-out cost.
Impact: `reqs` reads higher than a main-chain count (the live check showed 750 for the busiest session).
Open questions: none.

## 2026-09-10 15:05 Title field names for summary and custom-title are unverified

Context: only `ai-title` / `aiTitle` was seen in a live transcript.
Decision: read `summary` and `customTitle` by naming convention.
Why: harmless when absent; the title column falls back to blank.
Alternatives: drop those two types.
Impact: a wrong field name shows a blank title, never a wrong row.
Open questions: confirm the field names from a transcript that carries them.

## 2026-09-10 15:05 Smoke pins fixture mtimes

Context: `--since` skips files by mtime against real time, while entry filtering uses `SESSION_OBSERVE_NOW`.
Decision: the smoke setup touches fixture mtimes so the coarse file skip cannot drop them.
Why: fixtures carry fixed timestamps; a checkout's mtime is arbitrary.
Alternatives: make the mtime skip honor `SESSION_OBSERVE_NOW` too.
Impact: test-only.
Open questions: none.

## 2026-09-10 15:40 Review found crash paths on untrusted input

Context: a fresh-context correctness review of PR #563 reported six findings. The lead reproduced four on the branch: a non-dict JSONL line, a non-dict `message`, and a non-dict pid file each raised `AttributeError` and killed the whole view; a trailing main-chain usage entry with no timestamp left `ctx` at the earlier 900001 instead of 7001.
Decision: fix all six on the branch before merge. Skip non-dict entries, messages, usage blocks and pid files. Count id-less usage entries without dedup. Update `ctx` in file order, whatever the timestamp. F5 found no code bug: the mtime skip already reads the burn clock. It got smoke cases 54 and 55.
Why: one malformed line in any transcript must not blank the view for every session; the spec defines `ctx` by file order.
Alternatives: guard only the reproduced crashes; this leaves the undercount and the untested mtime skip.
Impact: the edge fixtures live in `tests/burn-edge/`, outside `tests/fixtures/`. The non-dict line would crash `session-semantic`, which walks `tests/fixtures/` in smoke 27 to 30.
Open questions: the older views share the non-dict crash. On master, `session observe cost --file` with one `["x"]` line raises `AttributeError`, and `session-semantic` does too. This spec does not cover them; they need a follow-up.
