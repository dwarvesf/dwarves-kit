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
