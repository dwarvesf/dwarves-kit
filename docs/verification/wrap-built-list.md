# Proof of done: Built list form for step 7b's report line

Date: 2026-09-10. Branch: feat/wrap-built-list.

## Green run

| Check | Result | Verdict |
|---|---|---|
| `bash tests/test-wrap.sh` (full suite, run from the worktree) | 269 passed, 0 failed | PASS |
| Manual replay: three-item real-session Built list through `lib/wrap/report-lint.sh` | `report-lint: clean (0 warn(s))`, exit 0 | PASS |

## Negative control

Defeated the LIST-form per-bullet check in `lib/wrap/report-lint.sh` (swapped the
`*enhance*|*new\ \(*` case pattern for an always-match `*`), leaving everything else
untouched. Re-ran the suite: `266 passed, 3 FAILED of 269`, the three failures were exactly
the new bullet-enforcement cases (`a list with one bare path-and-commit bullet fails`, its
two follow-on assertions), every pre-existing case still green. Restored with
`git checkout HEAD -- lib/wrap/report-lint.sh`, re-ran: `all 269 passed`.

## Reproduce

```
bash tests/test-wrap.sh
```
