# Implementation notes -- spec-reserve-worktree

Deltas from SPEC-318. Nothing here repeats what the spec already states.

## 2026-09-26 Key derivation dropped `--path-format=absolute`
- Context: the brief suggested `git rev-parse --path-format=absolute --git-common-dir`.
- Decision/Change: the key comes from `cd "$(git rev-parse --git-common-dir)" && pwd -P`, run from `$ROOT`.
- Why: `--path-format` needs git 2.31. An older git echoes the flag back and prints a relative `.git` in the main checkout but an absolute path in a worktree, so the keys would differ. `pwd -P` also resolves macOS `/var` to `/private/var` the same way from every checkout.
- Impact: none on git 2.31+; older git now gets a correct key too.

## 2026-09-26 Three existing tests changed shape
- T1, T7 and T12 built their ledger lines from `basename` of the repo. They now use the repo's physical path, the new key. T12 still proves the anchored suffix match: a line for `<path>` does not count for `<path>-bar`.

## 2026-09-26 The worktree spec scan also feeds the realized-prune
- `_prune_reservations` calls `_scan_numbers`. A live reservation whose spec file now exists in any worktree is pruned as realized, not only one in the current checkout. The spec's Failure modes row says this; no extra code.

## 2026-09-26 Pre-existing lint left alone
- `shellcheck` SC2010 (`ls | grep`) fires on the scan line. It fired on the old single-checkout line too, and the change keeps the same idiom.
