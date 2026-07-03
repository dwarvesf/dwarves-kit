# Implementation notes: coverage-delta gate (SPEC-130)

The DELTA from the spec: decisions the spec did not pin, deviations, constraints found.

## 2026-07-04 Hook point: Review phase, NOT ship-gate (deviation from recon, matches spec)

Context: the wiring-recon subagent recommended adding an advisory line to `hooks/ship-gate.sh`
(next to the existing SPEC-069/071/076 `[advisory]` lines), because that is the most easily
testable live invocation path.
Decision: wire the gate at the **Review phase** via `commands/review-team.md` instead.
Why: the sub-goal contract is explicit , "(c) where the gate hooks ... NOT the push blocker"
and "keep this OFF the block path". `hooks/ship-gate.sh` runs on the push/PR-create path; even
a warn-only line there sits ON the push path, which the contract forbids. The Review phase is
the cycle table's designated `advisory` enforcer at the Build->Review boundary , the correct
phase boundary. Studied ship-gate.sh only to learn the advisory-vs-block boundary (per the
Where-to-look), not to host the gate.
Alternatives: ship-gate advisory line (rejected, on the push path); the Build verification
pipeline (rejected, it retries/escalates , wrong home for a warn-only signal).
Impact: the live invocation path is `commands/review-team.md` calling `bash lib/coverage-delta.sh`,
the same pattern the file already uses for `lib/role-classify.sh`. The no-orphan wiring gate
(sub-goal 06 / TIER-4) sees a live path there.

## 2026-07-04 Reuse the anchored test-detection globs, not fresh regex

Context: `lib/explain.sh:_rank` (rank 3 = tests) and `lib/quiz-gate.sh` already anchor their
test/doc globs (`tests/*`, `*/tests/*`, `*_test.*`, `*.test.*`, `*.spec.*`) to avoid
misclassifying names like `latest-value.js` as a test.
Decision: mirror that anchored `[[ ==` glob style for the test class in `coverage-delta.sh`,
rather than the loose regex the spec table sketches.
Why: consistency with the kit's existing classifier + the same anti-false-positive anchoring.
Impact: the spec's classification TABLE is the contract; the implementation realizes it with
anchored globs. Behavior matches the table.

## 2026-07-04 Base resolution reuses the ship-gate/proof-ledger merge-base pattern

Context: no deviation. The spec pins `git merge-base HEAD <default>` with the three-way
default-branch fallback. Implemented exactly as `hooks/ship-gate.sh:_resolve_base` does
(`origin/main` -> `main` -> `master`), extended to also try `origin/HEAD`/`master` so it works
in the kit's own `master`-default repo and downstream `main` repos alike.
Impact: the gate measures the same branch change the proof-gate keys on.
