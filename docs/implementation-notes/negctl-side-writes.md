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
- A pre-existing gap surfaced while writing the `--no-renames` proof (a brand-new tracked path
  landing inside MUTATE_SET itself, e.g. a `git mv` as the mutation, hitting the same
  whole-call-abort class on MUTATE_SET's own restore call) was scoped out in this round as
  out-of-scope, then closed in round 3 below rather than left that way a second time.
- `docs/FEATURES.md` needed a regen (`bash lib/registry/feature-registry.sh generate`) purely
  from adding a new spec file -- no `negctl` entry exists in the registry today, confirmed by
  grep, so the diff is unrelated total-count churn across existing rows, not a negctl-specific
  addition.

## Round 3 (post-ship critique+review)

- `restore()` is restructured around one partition loop over MUTATE_SET (`restore_files`) union
  the beyond-set (`beyond`), each path checked once via `git cat-file -e HEAD:<path>`, feeding
  three arrays: `to_restore` (one checkout call, everything that resolves at `HEAD`),
  `side_effect` (the `beyond`-derived subset of `to_restore`, for the `Side effect:` line only),
  and `unrestorable` (named in the failure, never checked out, never `git rm`/`git clean`d). The
  old two-call shape (MUTATE_SET restored separately, first) is gone; `side_effect_head`/
  `side_effect_new` are renamed to `side_effect`/`unrestorable` to match.
- The unrestorable-file failure message dropped "test-cmd added ... beyond the mutation" (no
  longer accurate once a HEAD-absent path can originate from MUTATE_SET itself) for a neutral
  "new tracked file(s) with no HEAD blob cannot be restored: ...". `tests/test-proof-negctl.sh`
  case [21]'s assertion was loosened from the literal old phrase to `cannot be restored`.
- `restore()` gained `trap '' INT TERM HUP` as its first line, INT/TERM/HUP with no other
  disposition, before the `restore_done` guard. This is a process-wide, permanent change (bash
  traps are not function-scoped), deliberately never undone, since `restore()` runs at or near
  the very end of the script's life either way.
- After step 6's confirmatory `run_test`, the script now does `restore_done=0; restore
  >/dev/null` unconditionally. `>/dev/null` swallows the `Side effect:`/`Side effect
  (unrestorable):` lines on this second call specifically so a clean second pass adds no noise
  to the proof block; a genuine failure on this pass still surfaces through `fail()`, which
  `>/dev/null` cannot suppress.
- The delta filter (`sed -n '/^[<>] $/!s/^[<>] /Delta: /p'`) needed the address-negation form,
  not a brace-grouped `!{...}` block: BSD/macOS `sed` rejected `!{s/.../.../p}` with "bad flag in
  substitute command: '}'" even though the exact same script parses under GNU sed. Verified both
  forms by hand against real diff output before picking the portable one.
- `tests/test-proof-negctl.sh`'s four new negative-control line targets (T4a's, restructured
  around `beyond` instead of the now-gone `side_effect_head`) needed re-deriving after the
  restore() rewrite; T4b/T4c/T4d's targets were untouched by the rewrite and needed no change
  (confirmed by re-running the full suite, which caught the two that did break).
- The SIGINT case ([31]/[32]) is the one genuinely timing-dependent test in the suite. Margined
  generously (a 2s shim delay against a 1.0s signal delay) and run repeatedly (3x default bash,
  2x real `/bin/bash`) before being kept permanently; `set -m` inside a subshell scopes job
  control to that block only, and `kill -INT -$PID` targets the whole process group so the
  signal reaches the shimmed `git` child the same way a real terminal Ctrl-C would.
- Discovered by dogfooding this exact fix (running `lib/gate/negctl.sh` against
  `tests/test-proof-negctl.sh` as its own test-cmd, mutating the retry guard): [31]/[32]
  reliably FAILED when nested this way, twice in a row, not a one-off flake. Root cause: SIGINT/
  TERM/HUP ignored dispositions are inherited across `fork`/`exec`, and POSIX shells can never
  un-ignore a signal inherited as already ignored. The OUTER negctl's own step-5 `restore()`
  ignores those three signals in its own process before step 6 ever spawns the inner suite, so
  by the time [32]'s mutated copy runs (three process-generations down), the signal was already
  neutralized -- `[ -n "$DIRTY" ]` came back false regardless of whether the copy's own `trap ''`
  line was present. Confirmed the mechanism in isolation (`bash -c 'trap "" INT; bash -c
  "trap ...; kill -INT $$"'`: the inner trap never fires) before writing the fix. `trap -p INT`
  cannot detect an inherited ignore (it only shows a trap the CURRENT shell itself set), so
  [31]/[32] now open with an empirical self-check: a disposable `bash -c` child sets its own
  trap, signals itself, and the marker file's presence answers "can this process tree actually
  catch SIGINT right now" directly, skipping [31]/[32] with a named reason when it cannot. This
  is a load-bearing fix, not cosmetic: `lib/gate/negctl.sh` proving a future change to ITSELF
  this exact way (as this spec did) is the documented, encouraged proof pattern for this file,
  so the nesting case is not an edge case -- it is how this test will actually be exercised the
  next time someone touches `restore()`.
- The `git mv`/`--no-renames` negative control ([28]) leaves `lib.sh` genuinely deleted from the
  scratch repo's working tree (not merely "dirty") when run against the un-fixed capture, since
  the un-fixed script never even captures `lib.sh` as changed; the cleanup renames `lib2.sh` back
  rather than checking out a path negctl itself never restored.
