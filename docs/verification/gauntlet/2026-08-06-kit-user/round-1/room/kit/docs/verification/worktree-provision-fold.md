# Proof of done: worktree-provision fold + installer CLI shims

Change under proof:
1. `lib/worktree-provision/` folds in ops-toolkit `tools/worktree-provision`
   (kit-foldin's one deferred tool), orphan module at `lib/` root like
   `skill-curator`/`plugin-check`.
2. Stable `bin/` entrypoints (SPEC-184) for the six kit CLIs: `cc-intel`,
   `cc-observe`, `cc-semantic`, `cc-recall`, `cc-vps-report`,
   `worktree-provision`.
3. `install.sh` step 5b + `kit_write_cli_shim`: enabled modules expose their CLIs
   on `~/.local/bin` as exec-shim files (new `worktree` module, hookless; `session`
   gains its five CLIs). Plugin-compat installs wire every module's CLIs. This is
   the kit-owned replacement for ops-toolkit's cc-elevation `redeploy.sh` symlink
   dance.

## Confirmation run-table

| # | Check | Command | Result | Verdict |
|---|---|---|---|---|
| 1 | New installer CLI test (20 checks incl. 3 negative controls) | `bash tests/test-install-clis.sh` | all 20 passed | PASS |
| 2 | Module machinery unchanged | `bash tests/test-install-modules.sh` | 37 passed, 0 failed | PASS |
| 3 | Plugin-compat path unchanged | `bash tests/test-install-compat.sh` | PASS: install compat | PASS |
| 4 | Contract deploy unchanged | `bash tests/test-install-contract.sh` | PASS=4 FAIL=0 | PASS |
| 5 | Ported tool behaves | `bash lib/worktree-provision/tests/smoke.sh` | smoke: all 14 passed | PASS |
| 6 | bin/ chain runs from repo | `bin/cc-intel --help; bin/worktree-provision --dry-run --base /tmp` | usage printed; `no-op` | PASS |

## Negative controls

Baked into `tests/test-install-clis.sh` and run green in row 1:
- **Spine-only install exposes no CLIs** (`--prune`): `~/.local/bin/cc-intel` and
  `worktree-provision` absent.
- **A user-owned (non-kit) file at the shim path is never clobbered**: pre-seeded
  `cc-intel` file survives verbatim; install log carries the
  `not kit-managed; left untouched` warning.
- **A stale symlink at the shim path IS replaced** (the exact ops-toolkit
  cc-elevation shape this feature retires).

## Reproduce

```
bash tests/test-install-clis.sh
bash tests/test-install-modules.sh
bash lib/worktree-provision/tests/smoke.sh
```
