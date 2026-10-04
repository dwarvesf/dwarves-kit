# Verification: master test reds

Two suites were red on master. Both are fixed by `b655f7b8`.

| Suite | Before | After | Fix |
|---|---|---|---|
| `tests/test-config-registry.sh` | 2 FAIL (orphans, root-only set) | 56/56 | Register `MEGA_BACKEND` (env-only, queue), `KIT_WRAP_CI_ON_MERGE` (env-only, wrap), `MEGA_ROOT` (script-local allowlist), `lanes.default` (root-only table) |
| `tests/test-kit-contract.sh` | 24/25, offender `sd` | 25/25 | Rename the python variable `sd` to `sweep_dir` in `tests/test-harvest-sweep.sh` |
| `tests/test-harvest-sweep.sh` | 637/637 (BSD PATH) | 637/637 on BSD and on GNU coreutils first in PATH | GNU PATH exposed `stat -f %Lp` (filesystem stat under GNU); replaced with a python mode read |
| `tests/test-meta.sh` | n/a | 887/887 | no FEATURES regeneration needed |

Notes: `MEGA_ROOT` is a shell variable in `lib/board/work.sh` set from `--megagoals-root`, not an env read, so it sits beside `MEGA_SH` in the allowlist. `KIT_WRAP_CI_ON_MERGE` was a third orphan beyond the two named. PR 842 touches none of these files.

## Negative controls

| Change reverted (`git checkout HEAD~1 -- <file>`) | Suite | Result |
|---|---|---|
| `lib/config/module-registry.md` | `test-config-registry.sh` | 54/56, FAIL orphans and root-only set |
| `tests/test-harvest-sweep.sh` | `test-kit-contract.sh` | 24/25, FAIL `offenders: sd` |

Both files were restored with `git checkout HEAD -- <file>`; the tree was clean after.
