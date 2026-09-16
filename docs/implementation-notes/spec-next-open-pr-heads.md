# Implementation notes: spec-next open-PR-head scan

No spec doc for this change (ID-904, override recorded via gate-ledger: scoped in
the dispatch prompt, a single additive scan function on an existing script).

## 2026-09-16 09:00 Bootstrap-failure scope

Context: the task says "when any call fails, behave exactly as today." A per-PR
`gh api .../contents/docs/specs?ref=<head>` call 404s whenever that PR does not
touch `docs/specs/`, which is the common case, not a failure.

Decision: only `gh auth status`, `gh repo view`, and `gh pr list` are treated as
bootstrap calls whose failure triggers the local-only fallback + stderr note. A
per-PR contents-API miss is silently skipped (that PR contributes no numbers).

Why: treating every PR's 404 as "the scan failed" would print a misleading note
on the majority of runs and would still be correct behavior (that PR just holds
no spec numbers), so scoping the failure note to bootstrap calls only avoids
false alarms without losing the fallback contract.

Alternatives: fail the whole scan on any single PR's API error. Rejected: one
PR without a `docs/specs/` dir would silently blind the scan to every other
open PR's numbers, defeating the point.

Impact: `lib/spec/spec-next.sh::_scan_pr_numbers`.

Open questions: none.
