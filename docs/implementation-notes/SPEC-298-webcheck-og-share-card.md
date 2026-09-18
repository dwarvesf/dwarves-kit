# Implementation notes: SPEC-298 webcheck og share card

The delta from the spec. Contract and design live in `docs/specs/SPEC-298-webcheck-og-share-card.md`.

## Decisions

- One validation lens (Opus, brief-reviewer) stood in for the full `/kit:spec-validate` six-lens panel and `/kit:devs-team`. The change is two warnings in one function with no new request, and one lens covered design critique and spec clarity. The gate ledger records both gates as `ran` with that scope.
- Validation returned NEEDS-REVISION with eight findings, all taken. Two widened the contract past the first draft: a `data:image/svg+xml` URI and a declared `og:image:type` both count as SVG. Both are free, since neither needs a request.
- The warning text carries no page value, so the `!r` forgery rule has nothing to apply to. The first draft's conditional `!r` bullet was dropped as ambiguous.

## Open questions

- None.
