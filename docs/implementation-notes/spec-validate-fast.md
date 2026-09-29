# Implementation notes: spec-validate-fast

Delta from `docs/specs/SPEC-361-spec-validate-fast.md`.

The build has not started; the spec is awaiting its last validation.

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

## Reversed: the merge subagent is removed

Context: the redesign had an Opus merge subagent write the report.
Decision: the lead merges mechanically (any CRITICAL means NEEDS REVISION, else APPROVED; duplicates keep the highest severity). Lead decision after round 2, which had already worked that way.
Why: the merge is a rule, not a judgment. A subagent added a dispatch and its own failure modes.
Impact: Interfaces, Picture and Failure modes lose the merge dispatch.

## Corrected: reviewer model tiers

Context: the redesign ran six reviewers on Sonnet by default.
Decision: reviewers inherit the lane's validator model (Opus on full, Sonnet on normal and backfill), Reviewer 6 on Opus on every lane, and the sequential fallback runs at the lane's model.
Why: four reviewers raised it as a critical. Sonnet-by-default downgraded the full lane's gate.
Impact: `commands/execute.md` preflight joins the change set.

## Warnings that became moot

Warnings 1, 4, 5, 6, 8, 9, 10, 11 and 13 applied only to the cache and are dropped with it. Warnings 3 (name the rejected cache in Approaches), 7 (explicit `operator_directed_build: true` field) and 12 (Design pointer) are folded into the spec.

## Precedent

`precedent find --surface inventory "validate cache"` found no existing home. Moot now that no helper is added.
