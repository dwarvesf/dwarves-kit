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

## 2026-09-26 Design critique (REVISE) fixed in-branch: CDPATH fail-open in the repo-key `cd`
- Context: a design critique of this branch's diff found the key-derivation `cd "$_cd"` honors
  an inherited `CDPATH`. A `CDPATH` entry with its own `.git` subdir makes the bare `cd` search
  `CDPATH`, jump into the decoy, and print the found path to stdout; the surrounding command
  substitution then captures two lines and `REPO` becomes a key no ledger line's suffix match
  ever hits. `_reservations()` reads nothing live for the repo, so `reserve` re-derives the same
  `max+1` every call. Reproduced live: two `reserve` calls under a decoy `CDPATH` both returned
  `006`, with a 4-line ledger for 2 logical entries.
- Decision/Change: `lib/spec/spec-next.sh` gained a named `_git_common_dir()` helper; the `cd`
  onto the relative common dir is now `CDPATH= cd -- "$cd_rel"`, one statement per line instead
  of the prior dense one-liner.
- Why: `CDPATH=` on the one `cd` call closes the search without touching the caller's shell
  (the whole helper runs inside a `$(...)` subshell already, same as the code it replaced).
  `--` guards a `.git` string that could theoretically start with `-`.
- Test: `tests/test-spec-reserve.sh` T24 builds a decoy `.git` under a `CDPATH` entry, reserves
  twice, and asserts the numbers differ and the ledger has one physical line per entry. Red on
  the old code (both reserves returned `006`, ledger held 4 lines for 2 entries), green after
  the fix.
- Also fixed in the same critique pass: T21/T22 reached the real `gh` PR scan (no test needed
  it; hermeticized with one `export SPEC_NEXT_NO_PR_SCAN=1` at the top of the test file), and
  the header comment's stale "byte-identical to before" claim (narrowed to the reservation
  ledger; the worktree-wide `docs/specs/` scan already made that claim inexact).
- Deferred, pre-existing, out of scope for this branch: `reserve` runs the open-PR `gh` scan
  while holding the mkdir-mutex, serializing every other reserving worker on the machine behind
  one network round trip when `gh` is slow. Named in the spec's Design critique, not fixed here.
