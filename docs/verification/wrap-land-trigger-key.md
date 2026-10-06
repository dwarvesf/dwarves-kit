# Verification -- wrap-land-trigger-key

The 300s land hold armed on the word `pull_request` anywhere in a workflow. The kit's own `test.yml` (trigger: `workflow_dispatch` and tags) names it inside an `if:`, so landing PR #949 waited the full 300s for checks that never come. The long hold now needs a real trigger key: `pull_request:`, `pull_request_target:`, a `- pull_request` list item, or `on: [... pull_request]`.

Lane: bug. Files: `lib/wrap/wrap-land.sh`, `tests/test-wrap-land.sh`.

## Green run
```
Command: bash tests/test-wrap-land.sh
Exit: 0
Output: test-wrap-land: all 582 passed
Verdict: PASS
```
PG4g: an `if:`-only mention pays the short grace (at most 5 rollup reads, no long-wait notice). PG4h: the inline `on: [push, pull_request]` form still holds long.

## Negative control
```
Command: bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Mutation: git show HEAD~1:lib/wrap/wrap-land.sh >| lib/wrap/wrap-land.sh
Changed: lib/wrap/wrap-land.sh
Exit: 1 (under mutation, RED expected)
Output: test-wrap-land: 580 passed, 2 FAILED of 582 (both PG4g)
Restore: git checkout HEAD -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven
- A trigger written as a multi-line flow sequence (`on: [\n push,\n pull_request ]`) reads as no trigger and gets only the short grace.
