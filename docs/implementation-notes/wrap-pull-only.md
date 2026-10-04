# Implementation notes -- wrap-pull-only

Deltas from `docs/specs/SPEC-359-wrap-pull-only.md`. Nothing here repeats what the spec already states.

## 2026-09-29 `_usage()`'s sed range needed widening, not rewrapping

- Context: `_usage()` prints `sed -n '2,31p' "${BASH_SOURCE[0]}"`, a fixed line range over the file's own header comment. Adding the `--pull-only` line to the header (spec's line-6 edit) shifts every later header line down by one, so the fixed range would have cut off the last line it used to cover (`internal, a test seam: apply --tips-file <path> replaces the run's own tip snapshot`) without any change to the range itself.
- Decision/Change: widened the range from `2,31p` to `2,32p` instead of rewrapping the paragraph to hold the line count fixed.
- Why: SPEC-286's implementation notes hit the identical seam and chose to rewrap the paragraph so the line count stayed put. Widening the range here is equivalent and cheaper: one line changes rather than a full paragraph's wrap points, and the two new header lines (the flag added to the existing usage line, plus a new one-line summary of `--pull-only` on its own) are exactly one line longer than before, an exact match for a one-line range bump. Verified by re-running `_usage()`'s own `sed` pipeline and diffing against the pre-change output: identical except for the two new/changed lines.
- Impact: a future header edit that changes the line count again needs the same check; there is no test pinning `_usage()`'s exact output, only `tests/test-wrap.sh`'s no-repo usage-line assertion, which greps for `--pull-only` rather than asserting the full block.

## 2026-09-29 The `pull_only` gate wraps one `if` around all six swept steps, not six separate flags

- Context: the spec's Task Breakdown (TASK-C) describes the gate as "wrap the `_apply_worktrees`, `_apply_branches`, `_apply_archive_unmerged`, `_apply_origin_branches`, `_carry_stray`, and `_carry_stray_commits` calls ... in `if [ "$PULL_ONLY" != 1 ]; then ... fi`", which reads as one block, but the negative control's mutate command (per the spec's own Test plan row, "remove the `pull_only` gate around one swept step") implied a narrower per-step mutation was expected.
- Decision/Change: implemented as written, one `if` block around all six calls. The negative control mutates the single shared condition (`!= 1` to `!= 99`), which disables the gate for every one of the six steps at once, not one.
- Why: the six steps were already sequential, ungated-individually code in `_apply_repo` before this change (no per-step flag existed for any of them except `ARCHIVE_UNMERGED`, which has its own separate `[ "$ARCHIVE_UNMERGED" = 1 ] && ...` line inside the block). Six separate `if [ "$PULL_ONLY" != 1 ]` guards would be six copies of the identical condition for no behavioral difference, the kind of repetition the spec's own "obvious: a flag over a verb" design call argues against one level up.
- Impact: the negative control is stronger than the spec's example (it proves the whole gate, not one step), and the RED run's 18 failures span every affected assertion, not just the branch-deletion ones the spec's example named. Confirmed the restore recovers to a byte-identical `lib/wrap/wrap.sh` (`git status --short` clean) before writing the verification doc.

## 2026-09-29 The fetch-failure wording branches on `PULL_ONLY`, not on whether any swept step would have run

- Context: the spec's "Report shape" and TASK-C both name the exact replacement string, `(fetch failed; the pull below will likely fail too)`, conditioned on `PULL_ONLY=1`.
- Decision/Change: implemented as a plain `if [ "$PULL_ONLY" = 1 ]` inside the existing `fetch --prune` failure branch, alongside `fetch_ok=0`, rather than deriving the message from which sections actually ran.
- Why: the two are equivalent today (the message only ever needs to distinguish "plain apply, deletes happen" from "pull-only, only the pull happens"), and branching on the flag directly is the simpler of two correct implementations, per the flag-over-verb design bias the spec already commits to.
- Impact: none beyond the spec's own stated behavior; recorded here only because the spec describes the OUTCOME, not this specific implementation shape, and a future reader diffing the two should not expect a derived condition.

## 2026-09-30 Ported onto the wrap modules (the monolith split)

- Context: origin/master split `lib/wrap/wrap.sh` into a 146-line dispatcher plus twelve `lib/wrap/wrap-<module>.sh` files and `tests/test-wrap.sh` into a thin runner plus thirteen suites. Function bodies moved verbatim, so every hunk of this branch had exactly one owner. Merged with `git merge --no-ff` (no rebase), taking master's version of both files and re-applying the branch's hunks by hand.
- Decision/Change: where each piece landed.

| Piece | Module |
|---|---|
| `PULL_ONLY=0` global, the lock-skip `FAILURES=1` in `run()` | `lib/wrap/wrap-common.sh` |
| `--pull-only` case, the four-flag conflict check, usage string, `_gh_state` skip in `cmd_apply`; the sweep gate, fetch wording, unresolved-default exit, tip-snapshot skip, ahead NOTE in `_apply_repo` | `lib/wrap/wrap-apply.sh` |
| Header usage lines and `_usage()`'s `sed` range (`2,31p` to `2,32p`) | `lib/wrap/wrap.sh` (dispatcher) |
| The whole `--pull-only` test block (82 assertions) | `tests/test-wrap-pull.sh` |
| The negative-control script now edits `wrap-common.sh` for N3 and `wrap-apply.sh` for the rest, and runs `tests/test-wrap-pull.sh` | `docs/verification/wrap-pull-only-negctl.py` |

- Why: `_apply_repo`, `cmd_apply` and the apply globals' consumers live in wrap-apply.sh. The `APPLY`/`WORKTREES`/`ARCHIVE_UNMERGED` globals and `run()` live in wrap-common.sh, so `PULL_ONLY` and the lock-skip belong beside them. The test block reuses `build_pd_repo` and `advance_pd_repo`, which live in test-wrap-pull.sh, so the block goes there and not in test-wrap-apply.sh (the heaviest suite, already serial).
- Impact: spec text that cites `lib/wrap/wrap.sh` line numbers or `tests/test-wrap.sh` describes the pre-split layout; the behavior contract is unchanged. `docs/FEATURES.md` was regenerated, not merged.

No other deviations. The conflict-check ordering (before the `--tips-file` existence check), the four rejected flags, the ahead-only/diverged split, and the Picture's `gh_state`-before-the-loop placement all match the spec's Decision/Picture sections exactly.
