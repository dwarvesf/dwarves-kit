# pr-gate-codes: delta from the brief

`_pr_gate` now prints `<CODE> <reason>`. Codes: `OK`, `CONFLICT`, `WAIT`, `SKIP`. `OK` has no reason. An empty verdict still means unreadable PR JSON.

- CONFLICT is `mergeable == CONFLICTING`. Any other non-MERGEABLE value (UNKNOWN, null) stays `SKIP`, as before.
- WAIT covers both pending-or-failing branches: the empty rollup on a non-CLEAN state, and a non-green check.
- Callers branch on `${verdict%% *}` and print `${verdict#* }`. The printed lines are byte-identical: the `SKIP #n ...:` prefix is literal and only the reason comes from the verdict.
- Hand-built verdicts (`SKIP dependents open`, `SKIP head is ...`) keep the `SKIP` code.
- Callers checked: `_merge_pr_prepare` (stacked conflict, WAIT continues to the ci label sync), the candidate loop and its conflict counter, the post-re-merge re-gate and its squash fallback, `_squash_fallback`, the ci-label re-gate, and the one-squash-away check in the re-merge. `wrap-land.sh` and `wrap-carry.sh` only mention `_pr_gate` in comments.

## Test

`reword_wrap` in `tests/lib/wrap-stub.sh` copies the kit and rewords the two reason sentences inside `_pr_gate` only. The cases in `tests/test-wrap-ci.sh` (conflict recovery, WAIT to ci label sync) and `tests/test-wrap-merge-stacked.sh` (stacked recovery) run through that copy. Against the old string-compare code the reworded cases fail; they pass on codes.

## Open question

Reason sentences are still the only human text. A future caller that wants the reason for a code needs no table; the reason is whatever follows the first space.
