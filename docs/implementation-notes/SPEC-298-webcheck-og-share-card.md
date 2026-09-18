# Implementation notes: SPEC-298 webcheck og share card

The delta from the spec. Contract and design live in `docs/specs/SPEC-298-webcheck-og-share-card.md`.

## Decisions

- One validation lens (Opus, brief-reviewer) stood in for the full `/kit:spec-validate` six-lens panel and `/kit:devs-team`. The change is two warnings in one function with no new request, and one lens covered design critique and spec clarity. The gate ledger records both gates as `ran` with that scope.
- Validation returned NEEDS-REVISION with eight findings, all taken. Two widened the contract past the first draft: a `data:image/svg+xml` URI and a declared `og:image:type` both count as SVG. Both are free, since neither needs a request.
- The warning text carries no page value, so the `!r` forgery rule has nothing to apply to. The first draft's conditional `!r` bullet was dropped as ambiguous.

- Review (Opus, APPROVE) found that `urlsplit` raises `ValueError` on a malformed page value such as `https://[x`, which aborted the whole audit. The path check now treats that as not an SVG. The href path at `core.py` `urljoin` has the same pre-existing crash and is left as it was: it is outside this spec.
- Added a test that two triggers still yield exactly one warning. The "no new request" bullet has no dedicated test: the check reads only parsed meta values and has no fetch call to count.

## Open questions

- None.
