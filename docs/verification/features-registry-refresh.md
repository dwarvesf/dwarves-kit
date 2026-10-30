# Verification -- features-registry-refresh

Regenerate `docs/reference/FEATURES.md` so the generated registry matches the tree again. The `/kit:next` row counted 73 test refs; the generator now finds 74 after the `--artifacts` suite landed in `lib/session/recall/tests/test_recall.py`.

## Green run
```
Command: bash tests/test-meta-docs-registry.sh
Exit: 0
Output:
  PASS docs/reference/FEATURES.md is fresh (check verb, SPEC-219)
  === Results ===
  Passed: 120 / 120
  All meta tests passed.
Verdict: green after `feature-registry.sh check --fix docs/reference/FEATURES.md` (one row changed).
```

## Negative control
```
Command: git checkout -- docs/reference/FEATURES.md && bash tests/test-meta-docs-registry.sh
Exit: 1
Output:
  FAIL docs/reference/FEATURES.md is fresh (check verb, SPEC-219)
  Passed: 119 / 120
Verdict: red with the stale registry. The regenerated file was then restored with `check --fix`.
```

## Not proven
- Which line of the new recall tests adds the extra `/kit:next` reference; the generator is deterministic and the diff is one cell.
