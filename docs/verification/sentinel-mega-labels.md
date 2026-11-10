# Verification -- sentinel-mega-labels

The migration sentinel now means content is present at the new root: a symlinked legacy dir writes `.migrate-refused` and no `.migrated`, and the next run migrates once the dir is real. Mega reconcile labels are declared once in `lib/mega/labels.tsv`.

| Check | Command | Result |
|---|---|---|
| Sentinel suite | `bash tests/test-migrate-sentinel.sh` | 10 passed |
| Labels suite | `bash tests/test-mega-labels.sh` | 6 passed |
| Negative control | old `kit-migrate.sh` restored | 3 FAIL, restored |

## Green run

```
Command: bash tests/test-migrate-sentinel.sh
Exit: 0
Output:
  PASS symlink: nothing copied through the link
  PASS symlink: no .migrated sentinel (nothing was copied)
  PASS symlink: refusal reason recorded in .migrate-refused
  PASS symlink: refusal announced on stderr
== symlink replaced by a real dir: the next run migrates ==
  PASS retry: files now copied
  PASS retry: sentinel written
  PASS retry: stale refusal marker cleared
== no legacy dir at all (fresh install) ==
  PASS fresh: sentinel written (nothing to copy, nothing missing)

Results: 10 passed, 0 failed
```

```
Command: bash tests/test-mega-labels.sh
Exit: 0
Output:
== output unchanged: mega.sh status prints every label ==
  PASS status labels
== a label added to the table reaches both readers ==
  PASS bash reader sees the new label
  PASS python reader parses the new label
  PASS the real table is untouched by the copy

Results: 6 passed, 0 failed
```

## Rollback

Revert the PR. A `.migrate-refused` marker left on a host is inert to the old code (it only reads `.migrated`), so no host needs cleanup; delete the marker by hand if wanted. `lib/mega/labels.tsv` has no stored data.
