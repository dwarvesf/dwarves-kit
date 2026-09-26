# Implementation notes -- negctl-side-writes

Delta from `docs/specs/SPEC-327-negctl-side-writes.md` only.

- No deviation from the contract as validated. `lib/gate/negctl.sh` gained: a `baseline_diff`
  capture right after the step-2 green run; `mutate_only` (MUTATE_SET minus `baseline_diff`)
  driving the `Changed: ...` line and its fail check; a `_path_in` / `_beyond_mutate_set` helper
  pair reused by both the retry-loop guard and `restore()`; `restore()` recomputing
  `SIDE_EFFECT_SET` on every call (including via the `EXIT` trap) and partitioning it by
  `git cat-file -e HEAD:<path>` into a second batched checkout (`side_effect_head`) versus a
  named, never-deleted failure (`side_effect_new`); and `--no-renames` on every tracked-diff
  capture.
- `restore()`'s old early return (`[ "${#restore_files[@]}" -gt 0 ] || return 0`) is gone
  entirely, not narrowed: the function now always runs the recompute, guarding only the
  MUTATE_SET checkout call itself behind its own length check. This also closes the interrupt
  window between `mutate_cmd` running and `restore_files`'s own capture, per the spec's point 3.
- Every new array is length-checked before a bare `"${arr[@]}"` expansion (bash 3.2's `set -u`
  treats a zero-element array expansion as unbound). Verified by running the whole suite under
  `/bin/bash` (macOS's stock bash 3.2.57), not just whatever `bash` resolves to on `$PATH`.
- Discovered while writing the test plan (T4c): the retry-safety fixture had to separate the
  "is this the baseline call" question from "does the mutation matter" -- an early draft made
  the script's redness depend on `lib.sh`'s own `add()` output, which meant a genuinely vacuous
  mutation (needed to prove Critical 2) was unreachable, since a REAL mutation's retry sequence
  is legitimate flaky-test coverage (case [12]'s pre-existing behavior), not a regression. The
  final fixture (`test-retrywriter.sh`) uses an external call-counter plus a fixture-content
  check, entirely independent of `lib.sh`, so the mutation itself (a no-op comment append) can
  be provably inert while the retry sequence's redness is still 100% attributable to the
  leftover write.
- `tests/test-proof-negctl.sh`'s `mkrepo()` gained four tracked fixtures (`fixture.md` and three
  scripts) shared by every repo it builds ($REPO, $FREPO, and the proof-ledger `$PR`); none of
  the pre-existing 18 cases reference them, so nothing regressed. A `mk_naive_negctl()` helper
  reconstructs the pre-fix single-call `restore()` for T4b's negative control by anchoring on
  the stable `restore() {` / `trap restore EXIT` lines, not on interior formatting -- it survives
  a future reflow of the function body.
- Per-mechanism negative controls (T4a/T4b/T4c/T4d) mutate a scratch copy of the real
  `lib/gate/negctl.sh` via line-number-targeted `sed` (found through `grep -Fn` on a fixed
  string, never a hand-counted literal number), so they track the real file instead of drifting
  from it. The spec's own negative control (mutating `lib/gate/negctl.sh` itself and proving
  `tests/test-proof-negctl.sh` goes red) targeted the retry-loop guard specifically; see
  `docs/verification/negctl-side-writes.md` for the captured run.
- A pre-existing, out-of-scope gap surfaced while writing the `--no-renames` proof: a brand-new
  tracked path landing inside MUTATE_SET itself (a `git mv` as the mutation, or a baseline-run
  write that stages a new file) still hits the same whole-call-abort class on MUTATE_SET's own
  (deliberately unfiltered) restore call. Confirmed against the pre-fix script too, so it is not
  a regression this change introduced; widened the spec's Not covered bullet to name it
  accurately rather than narrow it to only the baseline-run case.
- `docs/FEATURES.md` needed a regen (`bash lib/registry/feature-registry.sh generate`) purely
  from adding a new spec file -- no `negctl` entry exists in the registry today, confirmed by
  grep, so the diff is unrelated total-count churn across existing rows, not a negctl-specific
  addition.
