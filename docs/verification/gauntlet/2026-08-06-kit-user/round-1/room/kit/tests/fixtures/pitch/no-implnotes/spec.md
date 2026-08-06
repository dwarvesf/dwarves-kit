# Spec: Fixture full-coverage change (test fixture, tests/test-pitch.sh)

Generated: 2026-07-04
Status: VALIDATED
Lane: normal

## Problem

The fixture problem statement: a fictitious small change used only to exercise
`lib/pitch.sh`'s full-source render path (spec, proof, and implementation-notes all
present), never a real shipped change.

## Solution

The fixture solution paragraph: ships a small change with a spec, a proof-of-done, and an
implementation-notes file all present, so `tests/test-pitch.sh` can assert the full-source
output is populated and contrastively assert the two absence lines do NOT appear.

## Out of Scope

- Explicitly excludes fixture-feature-x, deliberately deferred (test-only exclusion text).
- Not changed: fixture-module-y stays as-is for this fixture.

## Acceptance criteria

| # | Criterion | Evidence |
|---|---|---|
| AC1 | Fixture-only, no real behavior | this file |
