# Implementation notes -- coverage-map-warn (ID-466)

Task: warn (advisory, never block) at the ship boundary when the active spec carries a `## Test plan` but the proof-of-done doc has no coverage map, or the map leaves matrix rows unmapped.

## 2026-08-10 parsing home: proof-gate.sh subcommand, not inline awk in the hook

Context: the task scoped the change to `hooks/ship-gate.sh` and/or `lib/gate/proof-gate.sh` without picking a split.
Decision: the matrix/map parsing lives in `proof-gate.sh coverage <spec> [proof.md ...]` (always exit 0, one-line verdict); the hook only wires the call and prints the `[advisory]` line.
Why: proof-gate.sh is the proof-shape brain and is directly unit-testable; the hook stays a thin wiring layer like every other advisory it carries.
Alternatives: all-inline in ship-gate.sh (untestable without driving the whole hook); proof-ledger.sh (out of the task's named scope).
Impact: one new subcommand, no new files in lib/.

## 2026-08-10 row identity: `#` column when numeric, ordinal fallback otherwise

Context: real specs use two matrix dialects, the canonical `| # | Case | ... |` (numbered) and the older `| Category | Case | How |` (no id column, e.g. SPEC-195).
Decision: a row's id is its first cell when that cell is a bare integer, else its ordinal position (1..N) among data rows. The coverage map's `Row` column uses the same rule.
Why: the task says "each matrix row id" but half the fleet has no id column; ordinals keep the older dialect covered without retrofitting specs.
Impact: documented in docs/verification/README.md next to the owed shape.

## 2026-08-10 which proof files the hook scans

Decision: the hook hands proof-gate.sh the repo-root convention files for the slug, `docs/verification/<slug>.md` plus `docs/verification/<slug>/*.md` and `<slug>/runs/*.md`. Co-located `tools/*/docs/proof-of-done.md` is NOT scanned.
Why: the advisory keys on the spec's slug; a co-located proof has no slug linkage the hook can resolve cheaply, and a false warning on a monorepo tool is an acceptable advisory miss for now.
Open question: extend to co-located proofs if a consumer repo hits the false warning in practice.

## 2026-08-10 header/separator detection is look-ahead, not keyword

Decision: inside the section, a `|` row is a separator when it contains only `| :-` chars; a row is a header when the NEXT row is a separator. No header keyword list.
Why: keyword lists (`#`, `Case`, `Category`) break on every new dialect; the separator-follows-header rule is structural and dialect-free.

## 2026-08-10 section match is exact

Decision: the spec section matches `^## Test plan[ \t]*$` only, so `## Test plan critique` (written by /kit:test-plan-review-team) never counts as a plan. The proof section is `^## Test plan coverage[ \t]*$`.

## 2026-08-10 new test file is not registered in CI

Context: `.github/workflows/test.yml` lists tests explicitly, but this unattended run must not write `.github/*`.
Decision: `tests/test-ship-gate-coverage-map.sh` ships unregistered, matching the existing `test-ship-gate-fail-closed.sh` / `test-ship-gate-profiles.sh`, which are also absent from CI.
Open question: operator may want to add all three ship-gate tests to the workflow in a follow-up.
