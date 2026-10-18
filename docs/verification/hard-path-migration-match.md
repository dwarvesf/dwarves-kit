# Verification: hard-path-migration-match

The migration hard path in `lib/classify/lane-classify.sh` now matches Liquibase changelog layouts only, so a content file such as `apps/memo/src/data/qa/changelog-2025-01-15-ten-years-strong.json` no longer forces the full lane.

New pattern (the changelog alternative of `_HP_migration`, all other alternatives and every other `_HP_*` unchanged):

`(^|/)db\.changelog[^/]*\.(xml|ya?ml|json|sql)$|(^|/)changelog-master\.(xml|ya?ml|json|sql)$|(^|/)(db|liquibase)/([^/]+/)*([^/]*changelog[^/]*|changelog/[^/]+)\.(xml|ya?ml|json|sql)$`

## Green run

| Command | Exit | Verdict |
|---|---|---|
| `bash tests/test-lane-classify.sh` | 0 | PASS, 46/46 including 6 Liquibase positives and 2 content negatives |
| `bash tests/test-lanes-data.sh` | 0 | PASS |
| `bash tests/run-all.sh --changed` | 0 | PASS, all 20 suites passed, 0 skipped |

```
Command: bash tests/test-lane-classify.sh
Exit: 0
Output:
=== migration hard path: Liquibase changelogs match, content changelog files do not ===
  PASS changelog: db.changelog-master.xml -> full (full)
  PASS changelog: db/changelog/db.changelog-1.0.yaml -> full (full)
  PASS changelog: src/main/resources/db/changelog/*.xml -> full (full)
  PASS changelog: changelog-master.xml -> full (full)
  PASS changelog: liquibase/changelog.xml -> full (full)
  PASS changelog: liquibase/changelog/x.sql -> full (full)
  PASS changelog [NC] memo data file changelog-<date>-<slug>.json -> not full (normal)
  PASS changelog [NC] docs/changelog-notes.json -> not full (normal)
=== 46/46 passed, 0 failed ===
Verdict: PASS
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Output:
run-all: all 20 suites passed, 0 skipped for missing tooling
Verdict: PASS
```

## NEGATIVE CONTROL

The fix was committed first. The old pattern was then restored with `git show HEAD~1:lib/classify/lane-classify.sh >| lib/classify/lane-classify.sh`, the suite run, and the fix restored with `git checkout -- lib/classify/lane-classify.sh`.

| Step | Command | Exit | Verdict |
|---|---|---|---|
| fixed | `bash tests/test-lane-classify.sh` | 0 | PASS, 46/46 |
| old pattern | `bash tests/test-lane-classify.sh` | 1 | RED as designed, 42/46 |
| restored | `bash tests/test-lane-classify.sh` | 0 | PASS, 46/46 |

```
Command: bash tests/test-lane-classify.sh   (old pattern in place)
Exit: 1
Output:
  FAIL changelog: src/main/resources/db/changelog/*.xml -> full -- got 'normal', expected 'full'
  FAIL changelog: liquibase/changelog/x.sql -> full -- got 'normal', expected 'full'
  FAIL changelog [NC] memo data file changelog-<date>-<slug>.json -> not full -- got 'full', expected 'normal'
  FAIL changelog [NC] docs/changelog-notes.json -> not full -- got 'full', expected 'normal'
=== 42/46 passed, 4 failed ===
Verdict: PASS (the negative cases went red under the old pattern, as required)
```

## Not proven

- Liquibase files named `changelog.<ext>` outside a `db/` or `liquibase/` directory no longer match; the narrow rule trades that for not flagging content files. A repo with such a layout adds it through `[lanes] extra_hard_paths`.
