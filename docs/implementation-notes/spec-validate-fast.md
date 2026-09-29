# Implementation notes: spec-validate-fast

Delta from `docs/specs/SPEC-361-spec-validate-fast.md`.

The build has not started; the spec is awaiting a second validation.

## Reversed: the section-hash cache is dropped

Context: the first draft cached per-reviewer section hashes and re-ran only reviewers whose sections changed.
Decision: drop it. No `lib/spec/validate-cache.sh`, no cache file, no test for it.
Why: the fresh-context validator returned NEEDS REVISION with 4 criticals, each a way the cache carries a stale verdict.
- Reviewer 6 did not read Technical Design.
- Reviewer 2 did not read Design.
- `store` hashed the working tree, not the validated sha.
- A missing spec file failed open.
A fifth finding removed the benefit: `commands/spec-validate.md` requires a Decision Log entry per fix, Decision Log was outside the section map, so every re-validation re-ran all 7 anyway.
Impact: the design is now 7 parallel fresh-context reviewers plus one merge, and every round re-runs all 7. The re-validation diff is context only.

## Warnings that became moot

Warnings 1, 4, 5, 6, 8, 9, 10, 11 and 13 applied only to the cache and are dropped with it. Warnings 3 (name the rejected cache in Approaches), 7 (explicit `operator_directed_build: true` field) and 12 (Design pointer) are folded into the spec.

## Precedent

`precedent find --surface inventory "validate cache"` found no existing home. Moot now that no helper is added.
