# Proof of done: config-registry drift reconciliation

Change: `tests/test-config-registry.sh` was 17/19 on master (pre-existing,
identical on a pristine master worktree). Two failures, both fixed:

- AC1 drift lint: 22 seed-regex env vars in `lib/hooks/bin` had no registry
  row. 21 are real env-overridable knobs, registered with their source
  defaults; 1 (`QUEUE_SH`) is a computed script-local path, allowlisted like
  its sibling `MEGA_SH`.
- AC5: the `TIER4_CLOSE` registry cell said the default was `` `1` (truthy) ``
  but kit.toml sets `tier4_close = true`, so `config get` (which resolves
  kit.toml, above the registry default) returned `true`. Aligned the cell to
  `true` and fixed the stale assertion.

## Green run

| Field | Value |
|---|---|
| Command | `bash tests/test-config-registry.sh` |
| Exit | 0 |
| Verdict | PASS (19/19; was 17/19) |

## Negative control (revert -> RED -> restore)

Reverted ONLY `lib/config/module-registry.md` to `origin/master`, re-ran:

```
ORPHAN: QUEUE_SANITIZE_PROMPT
ORPHAN: QUEUE_SH
ORPHAN: QUEUE_WAIT_POLL_SECS
=== 18/19 passed ===
```

The orphans return and AC1 fails again, proving the registry rows are
load-bearing. Restored via `git checkout HEAD -- lib/config/module-registry.md`
(from the feature commit): back to 19/19.

## Regression check

| Command | Result |
|---|---|
| `bash tests/test-meta.sh` | 799/799, all pass |

## Notes

- The 22nd orphan `QUEUE_WAIT_POLL_SECS` was introduced by PR #378 (the
  `queue wait` verb); it did not regress a green test (this lint was already
  red on master) but is folded into this reconciliation with its family.
- The `QUEUE_*` knobs are registered `env-only [impl] queue` matching the
  existing queue-section rows; defaults are transcribed from the `${VAR:-...}`
  assignments in `lib/queue/queue.sh` and `lib/queue/sanitize.sh`.
