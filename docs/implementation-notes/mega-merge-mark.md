# Implementation notes: mega-merge-mark (SPEC-104)

Delta from the spec. Reference, do not restate.

## 2026-07-02 mark is an executable verb, not just mega.md prose

**Context:** goal-file 04 says "the mark goes on at the ONE place PRs are opened (commands/mega.md)."
**Decision:** the mark is an executable `mark` verb in `lib/mega-merge.sh`; `commands/mega.md`'s
held-PR step calls it.
**Why:** the "ensure the label exists idempotently" requirement + the end-to-end testability need
executable code; prose alone can't be pinned. The verb is the single mark point; mega.md points at it.
**Impact:** one new verb, gh routed through `MEGA_MERGE_GH` (mirrors the existing
`MEGA_MERGE_PR_INFO_CMD` / `MEGA_MERGE_GATE_LEDGER` test seams), so the pins run offline.

## 2026-07-02 draft via `gh pr ready --undo`; both draft AND label

**Context:** the guard refuses on draft OR hold-label OR title-marker.
**Decision:** `mark` sets BOTH draft and the `do-not-merge` label (not just one).
**Why:** draft is the GitHub-intrinsic block (GitHub refuses to merge a draft natively); the label
is the belt-and-suspenders the code guard reads. `gh pr ready <pr> --undo` is the convert-to-draft
command. All steps `|| true` for idempotence (re-mark is safe; a re-run over an already-draft PR
does not error the verb).

## 2026-07-02 bash 3.2 empty-array expansion (macos CI caught it)

**Context:** first CI run failed only on macos-latest (bash 3.2.57); the 3 `mark` gh-call pins
failed. `mega-merge.sh` runs under `set -uo pipefail`.
**Decision:** expand the optional `--repo` flag array with `${rf[@]+"${rf[@]}"}`, not bare
`"${rf[@]}"`.
**Why:** bash 3.2 throws "unbound variable" on `"${rf[@]}"` over an EMPTY array under `set -u`
(the same quirk `_merge_exclusion`'s `larr` guard documents). The set-u-safe idiom expands to
nothing when empty.
**Impact:** verified against real bash 3.2 (`/bin/bash` on this Mac) before re-push, not just the
5.x default. Lesson: test new array code in mega-merge on `/bin/bash` (3.2) locally to match the
macos CI runner.

## 2026-07-02 guard unchanged

The SPEC-100 `_merge_exclusion` guard is byte-unchanged; this sub-goal adds only the mark half.
The `mark<->guard meet` pins feed `_merge_exclusion` the exact state `mark` produces and assert
refusal, proving the two halves close the loop.
