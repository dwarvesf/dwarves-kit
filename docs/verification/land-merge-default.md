# Proof of done: `wrap land` merges the default branch into a conflicting own PR

2026-09-30. Spec: `docs/specs/SPEC-374-land-merge-default.md` (VALIDATED). Lane: full. Files: `lib/wrap/wrap.sh`, `bin/wrap`, `tests/test-wrap.sh`, `commands/wrap.md`, `docs/consumer-contract.md`, `docs/CHANGELOG.md`, `docs/FEATURES.md` (regenerated), `docs/implementation-notes/land-merge-default.md`, this file.

## What changed

When GitHub refuses `wrap land`'s squash merge and the PR reads `CONFLICTING`, `land` now runs one merge cycle in the worktree: `git merge --no-ff --no-commit origin/<default>`, the rebase's resolver rules (regenerate `docs/FEATURES.md` with the repo's own generator, keep both sides of a pure-addition `docs/CHANGELOG.md`, refuse every other conflict by name), a marker scan, one merge commit, an optional caller `--verify <cmd>`, and a plain fast-forward push. It then re-reads the PR pinned to the pushed head, waits for its checks, and merges that head. It never rebases and never forces. `wrap merge --apply`'s re-merge runs the same cycle, so a FEATURES conflict no longer aborts it. Every refusal restores the branch to its pushed tip with a clean worktree, or names the command a human runs.

## Why it needs design review

It adds a write path (a merge commit and a push) to `land` and changes `wrap merge`'s unattended re-merge from abort-on-conflict to resolve-or-refuse, with new exit semantics (2 skips the squash fallback, 130 on interrupt).

## Green run

On `cbe2d2f0` (the branch with origin/master merged in):

| Command | Exit | Output |
|---|---|---|
| `bash tests/test-wrap.sh` | 0 | `test-wrap: all 1816 passed` |
| `bash tests/test-meta.sh` | 0 | `Passed: 887 / 887`, `All meta tests passed.` |

The first full run on the merge commit `58d439f2` went `1814 passed, 2 FAILED`: two assertions on master itself (`step 10 re-sizes the real diff before landing`, `commands/wrap.md classifies each candidate's lane`) still expected `lane-classify.sh classify` after master renamed the call in `commands/wrap.md` to `risk`. `cbe2d2f0` updates both assertions; master's own `test-wrap.sh` carries the same red.

Fresh-context verifier (Sonnet, read-only) on `765be7c0`: PASS on nine contract checks (no force or `+` refspec; first merge before any new read; one cycle per call; restore before `merge --abort`; `reset --keep` then a status check; `ls-remote` judges a failed push; `merge` skips the squash fallback on 2; pre-merge ignored files kept out; the `merge` generator decided before the sequence), `test-wrap: all 1799 passed`, `887 / 887`.

## Live run

A scratch repo, real git, `gh` stubbed: a bare origin, a clone, a worktree on `feat/x`; the branch and origin's main both change `docs/FEATURES.md`; a stub generator rebuilds it. The first `gh pr merge` refuses; `gh pr view` answers `CONFLICTING` at the old tip, then `MERGEABLE` at the new head.

```
$ wrap land <wt> --verify 'test -f docs/FEATURES.md'
     pushed feat/x (6513fb8)
     opened PR #42
Pull request is not mergeable: the merge commit cannot be cleanly created
     #42 is CONFLICTING: merging origin/main into feat/x
     merged origin/main into feat/x: 1 conflict(s) resolved, head 7d9c981 (was 6513fb8)
     verified in $S/repo/wt: test -f docs/FEATURES.md
   6513fb8..7d9c981  HEAD -> feat/x
     merged #42 (7d9c981...): tree verified
exit 0

origin main:
*   7d9c981 chore(merge): merge origin/main
|\
| * 948dd57 feat: main side
* | 6513fb8 feat: branch side
|/
* 4a47a0d base
```

The push is a fast-forward (`6513fb8..7d9c981`), the old tip is an ancestor of the landed head, and origin's `docs/FEATURES.md` lists both sides. Before this change the same fixture ended `MERGE FAILED #42: exit 1`, exit 2 (the spec's Grounding).

## Negative control

```
## Negative control (negctl)
Command: perl -e '$SIG{$_}="DEFAULT" for qw(INT TERM HUP); exec @ARGV' bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: bash negctl-mutate.sh
Changed: lib/wrap/wrap.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/wrap.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Run on a clean clone at `cbe2d2f0`. The three suite runs: `test-wrap: all 1816 passed`, `test-wrap: 1745 passed, 71 FAILED of 1816`, `test-wrap: all 1816 passed`.

The mutation (`negctl-mutate.sh`, kept outside the repo) changes `land`'s trigger `if [ "$m" != "CONFLICTING" ]; then` to compare against `CONFLICTING-NEVER`, so a refused first merge always takes today's `MERGE FAILED` exit and no merge cycle runs. Under it 71 assertions go red, among them the two the spec's Grounding named: `land-merge: FEATURES conflict exits 0` and `land-merge: HEAD is a merge of origin/main`.

The `perl` wrapper resets INT, TERM and HUP to their default action for the suite. Without it, the restore leg fails on the ten signal cases (`an interrupted cycle exits 130` and its siblings): `lib/gate/negctl.sh`'s `restore()` runs `trap '' INT TERM HUP` for the rest of its process, and bash cannot trap a signal that was ignored when it started, so every signal test in step 5 inherits the ignore. Two plain controls (on `765be7c0` and `cbe2d2f0`) went red under the mutation and then failed their restore leg on exactly those cases; standalone runs of the same restored trees passed.

## Review

A fresh Opus review of the first build returned FIX THEN SHIP: three CRITICAL findings on ignored files (an operator file un-ignored by origin's merge was committed and pushed, or deleted on a refusal, or overwritten), one HIGH (a signal during the preconditions left a merge in progress), one MEDIUM (fail-open on an unreadable or still-pending rollup), two LOW. All seven were reproduced by the reviewer and fixed tests-first in `e76877e4`, `88617cb3`, `5109e81d`, `d651b81c`; the implementation notes record that git 2.55's merge-ort ignores `--no-overwrite-ignore`, so a pre-merge check guards that case.

## Test plan coverage

| Row | Run / skip reason |
|---|---|
| 1 | green run: `land-merge: FEATURES conflict exits 0`, `HEAD is a merge of origin/main`, `FEATURES equals a fresh generate`, `no rebase entry in the reflog`; live run; negative control |
| 2 | green run: `land-merge: union merge exits 0`, `union kept the branch line once`, `union kept the origin line once` |
| 3 | green run: `land-merge: CHANGELOG conflict exits 0`, `both changelog bullets kept once`, `the base changelog line is kept` |
| 4 | green run: `land-merge: clean merge exits 0`, `FEATURES in the merge commit equals a fresh generate` |
| 5 | green run: `land-merge: a real conflict exits 2`, `REFUSED names the path`, `HEAD is back at the old tip`, `origin still holds the old tip`, `exactly one pr merge call ran` |
| 6 | green run: `land-merge: a mixed conflict exits 2` |
| 7 | green run: `land-merge: markers left exits 2`, `MARKERS names FEATURES`, `no marker ever reached the branch or origin` |
| 8 | green run: `land-merge: marker size $LMS exits 2`, `MARKERS names FEATURES at size $LMS` (sizes 9 and 5), `_rb_markers reads conflict-marker-size` |
| 9 | green run: `land-merge: the nested blockquote case exits 0`, `no MARKERS refusal for an over-long marker run` |
| 10 | green run: `land-merge: the generator side-effect case exits 2`, `generator failure left a clean worktree` |
| 11 | green run: `land-merge: GENERATOR FAILED on a conflict`, `generator failure restored the tip` |
| 12 | green run: `land-merge: untracked-output case exits 0`, `the generator output is in the merge commit` |
| 13 | green run: `land-merge: refused-with-output exits 2`, `the untracked output is gone`, `the gitignored file is untouched` |
| 14 | green run: `land-merge: hidden-untracked exits 2`, `the hidden file is untouched`, `the hidden file was never committed` |
| 15 | green run: `land-merge: refused commit exits 2`, `commit refusal restored the tip`, `commit refusal left a clean worktree` |
| 16 | green run: `land-merge: dedupe failure exits 2`, `dedupe failure restored the tip`, `dedupe failure left a clean worktree` |
| 17 | green run: `land-merge: verify green exits 0`, `the verified line precedes the post-push wait`; live run |
| 18 | green run: `land-merge: verify red exits 2`, `VERIFY FAILED names the worktree`, `verify red pushed nothing to origin`, `verify red restored the tip` |
| 19 | green run: `land-merge: dirtying verify exits 2`, `the changed-tracked-files verdict is named`, `dirtying verify pushed nothing` |
| 20 | green run: `land-merge: committing verify exits 2`, `committing verify pushed nothing` |
| 21 | green run: `land-merge: the raced push exits 2`, `PUSH REFUSED names the moved head`, `origin keeps the other writer's commit`, `no push in the run carried a force or a plus refspec` |
| 22 | green run: `land-merge: PUSH FAILED names the uncertainty`, `the merge commit stays when origin cannot be read` |
| 23 | green run: `land-merge: landed-despite-failure exits 0`, `the landed merge commit is origin's main`; `landed-under-foreign exits 2` |
| 24 | green run: `land-merge: an interrupted cycle exits 130`, `interrupt restored the tip`, `interrupt left no merge in progress`; `a pre-merge signal exits 130`; `an interrupted resolver exits 130` |
| 25 | green run: `land-merge: fetch failure exits 2`, `fetch failure made no merge commit` |
| 26 | green run: `land-merge: already-contains exits 2`, `already-contains routes to merge --apply` |
| 27 | green run: `land-merge: still-CONFLICTING exits 2`, `still-CONFLICTING made exactly one pr merge call` |
| 28 | green run: `land-merge: not-caught-up exits 2`, `the lag is named` |
| 29 | green run: `land-merge: foreign head exits 2`, `the other writer is named` |
| 30 | green run: `land-merge: unreadable-after-push exits 2` |
| 31 | green run: `land-merge: unreadable-after-refusal exits 2`, `unreadable made no merge commit` |
| 32 | green run: `land-merge: stale head exits 2`, `stale head made no merge commit` |
| 33 | green run: `land-merge: non-conflicting refusal keeps MERGE FAILED`, `non-conflicting refusal made no merge commit` |
| 34 | green run: `land-merge: failed check exits 2`, `failed check made exactly one pr merge call`; `the unreadable rollup exits 2`; `still-pending exits 2` |
| 35 | green run: `land-merge: no-checks exits 0`, `the empty rollup never slept` |
| 36 | green run: `land-merge: second refusal exits 2`, `a refused second merge makes no third call` |
| 37 | green run: `land-merge: happy path makes no pr view call before the merge` |
| 38 | green run: `land-merge: adopted-conflict exits 0`, `the PR is adopted, not created` |
| 39 | green run: `land-merge: with-ci conflict exits 0`, `the label sync ran twice (before the merge and on the merged head)` |
| 40 | green run: `merge-cycle: FEATURES re-merge exits 0`, `FEATURES re-merge merges the recovered PR`, `the merge commit has both parents` |
| 41 | green run: the existing re-merge case asserting `conflicts beyond the union-marked files, aborted` (tests/test-wrap.sh line 2290) |
| 42 | green run: `merge-cycle: FEATURES is refused by name`, `the generator never ran (marker absent)` |
| 43 | green run: `merge-cycle: an unrestored re-merge exits 2`, `ABORT FAILED is named`, `no squash-fallback PR was created` |
| 44 | green run: `merge-cycle: verify red pushed nothing`, `verify red called no pr merge` |
| 45 | green run: `merge-cycle: an interrupted scratch cycle exits 130`, `the scratch worktree and its temp dir are gone` |
| 46 | green run: `land-merge: bare --verify exits 64`, `trailing --verify exits 64`; `merge-cycle: bare --verify exits 64` |
| 47 | green run: `merge-cycle: wrap --help names --verify`, `bin/wrap usage names --verify on both verbs` |
| 48 | green run: the whole `tests/test-wrap.sh` (every pre-existing land, merge and rebase case) |

## Not proven

- GitHub's real `mergeable` after a pushed merge commit that already contains the base (the union-blind case): routed to `wrap merge --apply --pr <n>`, not sampled.
- A live GitHub PR end to end: every run stubs `gh`; the git side is real.
