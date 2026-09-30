# Proof of done: wrap land recognizes a branch already on the default branch

Spec: `docs/specs/SPEC-376-wrap-land-merged-pr.md`. Notes: `docs/implementation-notes/wrap-land-merged-pr.md`.

Code: `lib/wrap/wrap-land.sh` (`cmd_land`, new `_land_tidy`). Tests: the `SPEC-376` section at the end of `tests/test-wrap-land.sh`, plus `GH_STUB_MERGE_DELETES_BRANCH` in `tests/lib/wrap-stub.sh`.

## Acceptance criteria

| AC | Claim | Rows | Result |
|---|---|---|---|
| AC1 | proven-landed branch with no open PR: no push, no PR, clean tidy incl. the origin delete | TC1 (absorbed), TC2 (gh squash record) | PASS |
| AC2 | adopt path unchanged | existing SPEC-299 adopt rows, unmodified | PASS |
| AC3 | re-pushed past what merged still opens a fresh PR | TC4 | PASS |
| AC4 | a failed open-PR lookup refuses before any push | TC5 | PASS |
| AC5 | an origin ref GitHub already deleted reads as gone on both paths | TB1, TD1 | PASS |
| AC6 | a non-2 `ls-remote` failure in the tidy is never read as gone | TB2 | PASS |
| AC7 | origin differing from the proven tip refuses and touches nothing | TD2 | PASS |
| AC8 | a failed origin read fails closed | TD3 | PASS |
| AC9 | a proof alongside an open PR reports both and refuses | TE1 | PASS |
| AC10 | a zero-commit worktree still refuses at `ahead == 0` | TA1 | PASS |
| AC11 | a live Agent-tool lock does not block the tidy (DEC-9) | TF1 | PASS |
| AC12 | a failed fetch skips the proof check | TD5 | PASS |
| AC13 | no regressions | full suites below | PASS |
| added | `ahead` reads full refs (a tag named `origin/main` cannot fake zero) | TA3 | PASS |
| added | an ancestor-shaped proof is treated as no proof | TA2 | PASS |
| added | tip moved during the tidy's pull: removal refused | TG1 | PASS |
| added | tree dirtied while the proof was read: refused before any move | TG2 | PASS |

## Green run

| Command | Exit | Counts | Verdict |
|---|---|---|---|
| `bash tests/test-wrap-land.sh` on the merge base before the change | 0 | 314 passed | baseline |
| the SPEC-376 section against the unchanged `wrap-land.sh` | 1 | 34 passed, 37 FAILED of 71 | RED as expected (the 34 are regression and negative-control rows that hold on old code too) |
| `bash tests/test-wrap-land.sh` after the build | 0 | 385 passed (314 + 71) | PASS |
| `bash tests/test-wrap.sh` (all 13 wrap suites) after merging the current `origin/master` | 0 | 1969 passed | PASS |
| `bash tests/test-meta.sh` | 0 | 896 / 896 passed | PASS |

## Negative control

Each row breaks one line of `lib/wrap/wrap-land.sh`, runs the SPEC-376 section (71 rows) alone, lists the rows that went RED, and restores by copying a saved file back. After the last row the file was byte-identical to the saved copy (`cmp`).

| # | Mutation | Group | RED rows | Verdict |
|---|---|---|---|---|
| N1 | `ahead` back to short names `origin/<def>..<branch>` | TA3 | 2 | RED |
| N2 | drop the `ancestor*` proof guard | TA2 | 2 | RED |
| N3 | delete the `ahead > 0` refusal | TA1 | 3 | RED |
| N4 | tidy no longer reads exit 2 as gone | TB1 | 2 | RED |
| N5 | tidy reads any `ls-remote` failure as gone | TB2 | 2 | RED |
| N6 | proof check removed (`proof=""`) | TC1, TC2, TD1, TD2, TD3, TE1, TF1, TG2 | 28 | RED |
| N7 | any merged PR into the default branch counts as proof | TC4 | 3 | RED |
| N8 | push before the open-PR lookup | TC5, TD1 | 2 | RED |
| N9 | origin exit 2 read as `present` | TD1 | 2 | RED |
| N10 | origin sha compare always passes | TD2 | 4 | RED |
| N11 | a failed origin read proceeds (fail open) | TD3 | 4 | RED |
| N12 | proof check runs after a failed fetch | TD5 | 3 | RED |
| N13 | coexisting open PR ignored | TE1 | 4 | RED |
| N14 | a live-pid lock guard added to the short-circuit | TF1 | 2 | RED |
| N15 | the tidy's removal recheck deleted | TG1 | 4 | RED |
| N16 | the post-proof recheck deleted | TG2 | 5 | RED |

Full-suite control for the headline mutation (N6, proof check removed), run with `lib/gate/negctl.sh` over the whole 385-row suite. The suite runs under a perl wrapper that resets INT, TERM and HUP to default: launched as a background job without it, the eight signal rows in the land-merge section failed on the post-restore run in two separate attempts, while the same rows passed in every direct run.

```
## Negative control (negctl)
Command: perl -e '$SIG{$_}="DEFAULT" for qw(INT TERM HUP); exec @ARGV' bash tests/test-wrap-land.sh
Exit: 0 (green before mutation)
Mutation: the landed-branch proof call replaced by proof=""
Changed: lib/wrap/wrap-land.sh
Exit: 1 (under mutation, RED expected)   [353 passed, 32 FAILED of 385]
Restore: git checkout HEAD -- lib/wrap/wrap-land.sh
Exit: 0 (green after restore)
Verdict: PASS
```

## Not proven

- No live GitHub run: `gh` is stubbed throughout, so the real `gh pr list --state merged` shape, GitHub's delete-branch-on-merge, and a real ship-gate push refusal are unexercised.
- The dropped lock guard (DEC-9) leaves a window: a live agent idle between writes, with a clean tree and an unmoved tip, has its worktree removed. Its committed work is proven landed, so only ignored scratch is at risk. TF1 locks that behavior in; it does not remove the window.
- The tidy's recheck sits textually right before `worktree remove -f -f`, but no fixture can write into the few microseconds between the recheck and the removal. TG1 proves the recheck fires after the pull; the final gap is by inspection.
- A local tip stale and behind its own merged PR's recorded head (a GitHub "Update branch" click) is not detected and still opens a new PR (spec Edge case 6).
- The per-mutation rows above ran the SPEC-376 section alone (harness header, the two helpers it needs, then that section), not the full 385-row suite; the full suite is covered by the official block above for one mutation.

## Reproduce

```
bash tests/test-wrap-land.sh
bash tests/test-wrap.sh
bash tests/test-meta.sh
```

## Review round: recheck baseline, exact ref match, signal test

Three review findings fixed test-first. The new rows went RED against the unchanged `wrap-land.sh` (387 passed, 21 FAILED of 408), then green after the fix.

| Finding | Rows | Result |
|---|---|---|
| a file written after the proof, before the tidy, refuses the removal (already-landed path) | TG3 | PASS |
| a file written during the merge refuses the removal (merge path) | TG4 | PASS |
| `ls-remote` matches `refs/heads/<branch>` exactly; a tag named `refs/tags/refs/heads/<branch>` is ignored; duplicate exact lines refuse | TH1, TH2, TH3, TH4 | PASS |
| pre-merge signal test keyed on argv, with a fired marker row | `land-merge: the signal fired on the already-contains check` | PASS |

| Command | Exit | Counts | Verdict |
|---|---|---|---|
| `bash tests/test-wrap-land.sh` | 0 | 408 passed | PASS |
| `bash tests/test-wrap.sh` | 0 | 1992 passed | PASS |
| `bash tests/test-meta.sh` | 0 | 896 / 896 passed | PASS |

### Negative control (test-wrap-land.sh only)

Each row breaks one line in a scratch copy of the worktree and runs the whole `tests/test-wrap-land.sh` there under the perl signal wrapper. The real worktree is never mutated, so there is nothing to restore; it stayed byte-identical to the commit.

| # | Mutation | Counts | RED rows | Verdict |
|---|---|---|---|---|
| N17 | status half of the pre-removal recheck deleted (tip compare kept) | 396 passed, 12 FAILED | TG3, TG4 | RED |
| N18 | merge path passes the tidy-entry status as the expected state (old baseline) | 402 passed, 6 FAILED | TG4 | RED |
| N19 | already-landed path passes the tidy-entry status as the expected state | 402 passed, 6 FAILED | TG3 | RED |
| N20 | origin read takes the first line, no exact match | 399 passed, 9 FAILED | TH1, TH2, TH3, TH4 | RED |
| N21 | duplicate exact lines no longer refuse | 407 passed, 1 FAILED | TH4 | RED |
| N22 | the `_merge_default` already-contains check deleted, so the signal's call never happens | 403 passed, 5 FAILED | signal rows incl. the fired marker | RED |

The un-ignored operator file rows (`ignx`, `ignr`) stay green: the merge path's expected state carries the pre-merge ignored set.

Not proven: a write between the recheck and `worktree remove -f -f`, and ignored files (still discarded by the removal; the spec accepts it).
