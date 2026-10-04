# Implementation notes -- wrap-land-union-carry

Deltas from SPEC-321. Nothing here repeats what the spec already states.

## 2026-09-26 `_land_ff_pull` skips the `run` wrapper `_pull_default` uses
- Context: `_pull_default` calls the pull through `run "$repo" "$verdict" git -C "$repo" pull --ff-only`, which records the call for `apply`'s dry-run/apply reporting.
- Decision/Change: `_land_ff_pull` calls `git -C "$repo" pull --ff-only` directly, same as `land`'s pre-existing bare call.
- Why: `land` has no dry-run half at this point (the merge already happened); `run`'s bookkeeping exists for `apply`'s WOULD/`--apply` distinction, which does not apply here. Keeping the direct call means the two existing output lines (`pulled ...` / `PULL BLOCKED ...`) stay byte-identical, the compatibility constraint the task named explicitly.
- Impact: zero output-shape change to the pull's own two lines; only new lines are additive (`saved N union-marked file(s) aside`, `carried N local line(s) back into <path>`).

## 2026-09-26 No `nonunion` reporting branch in `_land_ff_pull`
- Context: `_pull_default` prints a `NOTE: uncommitted and not declared merge=union, ...` line naming the blocking non-union files, gated on `$APPLY` and `wrap.pull_past_dirty`.
- Decision/Change: `_land_ff_pull` computes nothing about non-union files at all; it only ever acts on the ones `_union_marked` says yes to. A non-union dirty file that blocks the pull is invisible to this helper -- the pull itself still refuses, and `land`'s existing `PULL BLOCKED: pull --ff-only refused in <repo>, nothing was stashed or reset` line still fires.
- Why: the design decision (SPEC-321, union-carry only) means `land` never has an autonomy knob to consult for that file, so a NOTE naming a knob-gated action that will never happen would mislead rather than help.
- Impact: the existing non-union `PULL BLOCKED` test (`build_land blocked --modify-base`) needed no change; its assertions still hold unmodified.
