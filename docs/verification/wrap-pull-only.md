# `wrap apply --pull-only`, the pull stage alone

Spec: `docs/specs/SPEC-359-wrap-pull-only.md`. No board row filed; the operator named the work directly. Deltas from the spec: `docs/implementation-notes/wrap-pull-only.md`. The branch was ported onto the `lib/wrap/wrap-<module>.sh` split by a merge of `origin/master`; the file names below are the post-merge layout, and the spec's `wrap.sh` line references describe the pre-split monolith.

`bin/wrap apply --apply <repo>` sweeps worktrees, branches, archive-unmerged, origin branches, stray lines, and stray commits in the same call as the pull. An operator who wants only the pull, right after merging one PR while other sessions still own the other open branches in a shared checkout, had no verb for that and hand-rolled `git stash push -- <file> && git pull --ff-only && git stash pop` four times in one session, the exact workaround `commands/wrap.md` already forbids. `--pull-only` runs exactly `fetch --prune`, default-branch resolution, and the existing pull section (union carry, `wrap.pull_past_dirty` stash/pop, unchanged), with every other write-capable step gated off by a global `PULL_ONLY` flag.

## The change

| Piece | Where |
|---|---|
| `--pull-only` case, the four-flag conflict check (before the `--tips-file` existence check) | `lib/wrap/wrap-apply.sh` `cmd_apply` |
| `if [ "$PULL_ONLY" != 1 ]; then ... fi` around `_apply_worktrees`/`_apply_branches`/`_apply_archive_unmerged`/`_apply_origin_branches`/`_carry_stray`/`_carry_stray_commits`; the fetch-failure line varies under the flag | `lib/wrap/wrap-apply.sh` `_apply_repo` |
| Usage strings: the header doc line 6 (plus a new line 7), `_usage()`'s `sed` range widened `2,31p` -> `2,32p` (dispatcher `lib/wrap/wrap.sh`), the inline no-repo usage string (`lib/wrap/wrap-apply.sh`) | `lib/wrap/wrap.sh`, `lib/wrap/wrap-apply.sh` |
| Step 5 bullet: when to reach for `--pull-only`, the ahead-only vs. diverged distinction, the NOTE pointing at plain `apply` | `commands/wrap.md` |
| `bin/wrap` row description | `docs/consumer-contract.md` |
| `[Unreleased]` COMPAT bullet | `docs/CHANGELOG.md` |
| Ahead NOTE in the pull section; exit 2 on a lock-skipped pull (`--apply`) or an unresolved default branch; tip snapshot and `gh auth status` skipped (retroactive think and design-critique gates) | `lib/wrap/wrap-apply.sh` `_apply_repo`, `cmd_apply`; `lib/wrap/wrap-common.sh` `run()` and the `PULL_ONLY=0` global |
| `[--pull-only]` in the stable entrypoint's usage header | `bin/wrap` |
| Real-git fixtures for every row below | `tests/test-wrap-pull.sh` (reached through the `tests/test-wrap.sh` runner) |
| One mutation per `PULL_ONLY` gate, exact-once match guards | `docs/verification/wrap-pull-only-negctl.py` |

## Green run

- Command: `bash tests/test-wrap.sh` (the runner over the thirteen `tests/test-wrap-*.sh` suites), plus `bash tests/test-wrap-pull.sh` alone, which holds every `pull-only` assertion
- At: `92433255` (the merge commit of `origin/master` `0cb3af29` and this branch)
- Exit: `test-wrap-pull.sh` 0, all 202 passed (82 of them `pull-only`/`plain apply` assertions this branch added). `test-wrap.sh` 1678 passed, 2 FAILED of 1680: `step 10 re-sizes the real diff before landing` (test-wrap-deploy) and `commands/wrap.md classifies each candidate's lane` (test-wrap-report-lint). Both fail identically on a clean `origin/master` export and concern `commands/wrap.md` wording, so they are not this branch's
- Per suite: apply 249, carry 135, ci 127, cli 22, deploy 145 of 146, land 128, log 114, merge 214, pull 202, rebase 104, report-lint 134 of 135, scan 43, start 61
- Label check: every one of the 82 assert labels the branch added to the old monolith (`git diff ad1fc35f eec7263c -- tests/test-wrap.sh`) exists verbatim in the new suites (82 of 82, `grep -F`)
- `bin/test-affected` against `origin/master`: 23 selected, 2 fail (the two above), 6 uncovered
- Verdict: PASS, minus the two failures that already exist on `origin/master`

The fixtures reuse the real-git `build_pd_repo`/`advance_pd_repo` helpers (bare origin plus a clone, a `merge=union` `_meta/LAB_LOG.md`, a plain `A.md`/`B.md`). The subject is `git pull --ff-only`'s own exit behavior under ahead-only vs. diverged history, which a stubbed git cannot distinguish.

## Test plan coverage

Maps each row of SPEC-359's `## Test plan` to its acceptance criterion and the assertions that prove it. Every assertion row passed in the green run above. "Negative control" names the mutation that turns it RED.

| # | Case | AC | Proof (assertion prefix) | Negative control |
|---|---|---|---|---|
| 1 | Scope, happy path | AC-1, AC-5 | `pull-only scope:` | N1 |
| 2 | No sweep section, no ahead NOTE | AC-1 | `pull-only scope: no ...` | N1 |
| 3 | Union carry + `pull_past_dirty` on, stray line not carried | AC-2, AC-5 | `pull-only union+stash:` | N1 (stray-branch assertion) |
| 4 | `pull_past_dirty` off, union line survives | AC-2 | `pull-only knob off:` | none: `_pull_default` is unchanged (SPEC-286 owns its controls) |
| 5 | Dry run | AC-1 | `pull-only dry run:` | N1 |
| 6 | Off default branch | AC-1 | `pull-only off-default:` | N1 |
| 7 | Ahead-only, NOTE prints | AC-3, AC-5 | `pull-only ahead-only:` | N1, N2 |
| 8 | Diverged, NOTE prints | AC-4, AC-5 | `pull-only diverged:` | N1, N2 |
| 9 | Fetch failure wording | AC-8 | `pull-only fetch failure:` | N6 |
| 10 | Stale `index.lock` fails the `--apply` call; a dry run and plain apply still exit 0 | AC-6 | `pull-only stale lock:`, `plain apply stale lock:` | N3 |
| 11 | No default branch fails the call, dry run too; plain apply still exits 0 | AC-6 | `pull-only no default branch:`, `plain apply no default branch:` | N4 |
| 12 | Five flag-conflict forms, `--apply` passed, HEAD unmoved | AC-7 | `pull-only conflict`, `pull-only conflicts:` | N5 |
| 13 | Usage line | AC-7 | `pull-only usage:` | none: a string check |
| 14 | Multi-repo | AC-1 | `pull-only multi-repo:` | none: repo-list building is unchanged |
| 15 | Regression | AC-9, AC-10 | full suite, exit 0 | not applicable |
| 16 | Live run on a real remote | AC-1, AC-5 | "Live run" below | not applicable |
| 17 | N1 negative control: sweep gate | AC-1, AC-5 | 21 of 202 red, see "Negative control" | N1 |
| 18 | N2 negative control: ahead NOTE gate | AC-3, AC-4 | 2 of 202 red | N2 |
| 19 | N3 negative control: lock-skip exit | AC-6 | 1 of 202 red | N3 |
| 20 | N4 negative control: unresolved-default exit | AC-6 | 2 of 202 red | N4 |
| 21 | N5 negative control: conflict refusals | AC-7 | 11 of 202 red | N5 |
| 22 | N6 negative control: fetch wording | AC-8 | 2 of 202 red | N6 |
| S4 | Two sessions pulling one checkout at once | none | none | gap: SPEC-286's `_pull_default`, unchanged here |
| - | `--pull-only --under <root>` | AC-1 | none | gap: repo-list building does not read `PULL_ONLY` |

## Negative control

Six controls, one per independent `PULL_ONLY` gate, each run with `lib/gate/negctl.sh` at `92433255` in its own scratch clone (so they ran in parallel without sharing a working tree). The command under test is `bash tests/test-wrap-pull.sh`, the suite that holds the assertions (202 total). The mutation is `python3 docs/verification/wrap-pull-only-negctl.py N<k>`, which edits `lib/wrap/wrap-common.sh` for N3 and `lib/wrap/wrap-apply.sh` for the others. N1's block is below; N2 to N6 printed the same lines with their own argument, each `Verdict: PASS`:

```
## Negative control (negctl)
Command: bash tests/test-wrap-pull.sh
Exit: 0 (green before mutation)
Mutation: python3 docs/verification/wrap-pull-only-negctl.py N1
Changed: lib/wrap/wrap-apply.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap-apply.sh
Exit: 0 (green after restore)
Verdict: PASS
```

The failing assertions under each mutation were captured by a second mutated run in the same clone:

| Control | Gate mutated | RED under mutation | Failing assertions |
|---|---|---|---|
| N1 | sweep gate, `!= 1` to `!= 99` | 21 of 202 | `pull-only scope:` branch survival and the five section-absence checks; `union+stash`: no branches section, stray line not carried; dry run and off-default section checks; ahead-only: HEAD unchanged, NOTE, no local or origin carry branch; diverged: exits 2, FAILED line, HEAD did not move, NOTE, no local or origin carry branch |
| N2 | ahead NOTE gate, `= 1` to `= 99` | 2 of 202 | `pull-only ahead-only: the ahead count is named, not silent`; `pull-only diverged: the ahead count is named` |
| N3 | lock-skip exit in `run()` (`wrap-common.sh`), `= 1` to `= 99` | 1 of 202 | `pull-only stale lock: exits 2` |
| N4 | unresolved-default exit, `= 1` to `= 99` | 2 of 202 | `pull-only no default branch: exits 2`; `pull-only no default branch: a dry run exits 2 too` |
| N5 | every conflict refusal, `if [` to `if false && [` | 11 of 202 | the exit-64 and names-the-flag checks for `--worktrees`, `--archive-unmerged`, `--own`, `--own=<path>`; `--tips-file` names the flag and is refused before the missing-path check; `pull-only conflicts: no refused call pulled, though origin moved` |
| N6 | fetch wording reverted to the plain-apply string | 2 of 202 | `pull-only fetch failure: the wording names the pull`; `pull-only fetch failure: not the plain-apply wording` |

Under N1 the ahead-only and diverged rows go red for a second reason: `_carry_stray_commits` runs again, pushes the local commit to a `wrap/stray-commits-*` branch, and moves the default branch back with `git reset --keep`. That is the exact behavior the flag exists to turn off. The tip-snapshot and `gh auth status` skips change no output or exit code, so they carry no control.

## Live run

Re-run at `92433255` (post-port). A fresh clone of the real `origin` (GitHub), its `master` moved back one commit with `git reset --keep HEAD~1`, plus a local `old-merged` branch that a plain `apply --apply` would delete:

```
before: dad55cfd origin: 0cb3af29
== <scratch clone>
-- pull:
     [APPLY] pull --ff-only (checkout on master)
Updating dad55cfd..0cb3af29
Fast-forward
 docs/retro/RETRO-2026-09-30-kit-follow-through.md | 43 +++++++++++++++++++++++
 1 file changed, 43 insertions(+)
     HEAD: 0cb3af29 docs(retro): kit follow-through, validate-round verb and wrap split (#856)
== APPLY complete. PR merges, deploy dispatch and board rows stay with the command.
exit=0
after: 0cb3af29
  old-merged
```

Only the header, the fetch (silent on success) and `-- pull:` printed. HEAD reached origin's tip, and `old-merged` survived. The run touched only a scratch clone, never a shared checkout.

## Reproduce

```bash
cd <this worktree>
bash tests/test-wrap.sh
for k in 1 2 3 4 5 6; do
  bash lib/gate/negctl.sh "$PWD" "bash tests/test-wrap-pull.sh" "python3 docs/verification/wrap-pull-only-negctl.py N$k"
done
```

## What this does not cover

Two sessions running `--pull-only --apply` on one shared checkout at once, each with a sibling's dirty file under `wrap.pull_past_dirty`. The stash/pop mechanics are `_pull_default`'s, unchanged here, and carry SPEC-286's own negative controls. The live run above used a scratch clone with no other session present.

`--pull-only` combined with `--under <root>` has no fixture; repo-list building does not read `PULL_ONLY`.

The `docs/consumer-contract.md`, `docs/CHANGELOG.md` and `commands/wrap.md` edits are prose, checked by `kit:doc-verifier` (PASS in its second round) rather than by a test.
