# Testing strategy rules

Distills Martin Fowler's Practical Test Pyramid. Covers what deserves a test and at which layer; the per-language idiom files above cover test syntax and tooling, this file covers test design. Cross-language; applies on top of whichever per-language file governs the code being written, same as `coding-hygiene.md` and `security.md`.

## The pyramid
- Most tests are fast, isolated unit tests (pure functions, single modules). Fewer integration tests (a component plus its real dependency: a real DB, a real filesystem). Fewest end-to-end tests (the whole system, through its real interface).
- A slow or flaky test belongs at a lower layer if the same bug class can be caught there. Do not default to e2e because it "feels more real."

## What deserves a test
- Any branch, loop, parser, or money/security path gets a test. A trivial one-liner does not.
- Test behavior, inputs and outputs, not implementation details. A refactor that preserves behavior should not break the test.

## At personal scale
- For a solo-maintained tool, e2e tests are worth writing only for the golden path plus the highest-cost failure mode, not exhaustive coverage. A single smoke test against the real deployed thing beats a large e2e suite nobody maintains.

Once the layer is picked, how to design the individual cases: `test-case-design.md`.

## Sources
- [The Practical Test Pyramid (Martin Fowler / Ham Vocke)](https://martinfowler.com/articles/practical-test-pyramid.html)

Verified: 2026-07-29.
