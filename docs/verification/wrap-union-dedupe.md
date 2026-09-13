# Proof of done: `wrap merge`'s union re-merge dedupes the rows it just duplicated

2026-09-13. Acceptance: when `_union_remerge`'s `git merge --no-edit` succeeds, `_union_dedupe_rows`
sweeps every file the merge touched that is `merge=union`-marked and parses as a kanban table
(`backlog.sh`'s own row grammar), and for each id with more than one row keeps whichever copy is NOT
`queued` (file order breaks a tie), dropping the rest. A drop lands as its own follow-up commit
(`fix(board): dedupe union-merged rows`), never folded into the merge commit; a clean board makes no
commit. Lane: normal. Files: `lib/board/backlog.sh`, `lib/wrap/wrap.sh`, `tests/test-wrap.sh`,
`tests/test-board-dedupe-all.sh`.

## Why this is needed

`_union_remerge` (PR #608) already runs the one bounded re-merge that recovers from a GitHub-invented
conflict on a `merge=union` file. GitHub squash-merges without reading `.gitattributes`, so a log both
branches appended to conflicts on the PR while a local `git merge` resolves it by keeping every line
from both sides. That resolution is correct for an append-only log, but wrong for a table row: when a
feature branch flips one row's status and `main` flips an adjacent row (close enough that git treats
both edits as one overlapping hunk, a real git quirk on a short file, not overlapping content), the
union driver keeps ours-then-theirs whole and BOTH rows come out duplicated, one queued and one
flipped. The lead deduped this by hand 12 times on one day, always with the same rule: keep the copy
whose status is not `queued`, and on a tie keep the first. This change scripts that rule so `wrap
merge --apply` applies it itself, right after the re-merge and before the push.

## Where the rule lives

`backlog.sh dedupe-all [file]` is a new function/subcommand beside the existing `dedupe <id>` (which
names one id and keeps shipped/dropped/parked in that priority order, else the last occurrence).
`dedupe-all` instead sweeps every duplicated id in one pass and applies the rule PR #608's recovery
actually needs: prefer the row a branch flipped over the one still `queued`, file order breaks a tie.
The board owns the row grammar (`^\| *[A-Z]+-[0-9]+ *\|`, status = the last cell's leading keyword),
so the new pass lives there, not in `wrap.sh`.

`_union_dedupe_rows` (`lib/wrap/wrap.sh`) is the caller: it reads `git diff --name-only <pre-merge-tip>
HEAD` for the files the merge just touched, keeps only the ones `_union_marked` (declared
`merge=union`) and that still contain at least one kanban row, and for each such file calls `backlog.sh
dedupe-all`. Any drop is staged and committed as `fix(board): dedupe union-merged rows`; a commit
failure is reported plainly (not silently swallowed) and the staged fix is left for a human.

## Green run

Command: `bash tests/test-board-dedupe-all.sh`
Exit: 0
Output: `ALL PASS` (4/4: queued+shipped keeps shipped, a tied status keeps the first occurrence, a
clean board is a no-op, several duplicated ids in one file are all swept together)
Verdict: PASS.

Command: `bash tests/test-wrap.sh`
Exit: 0
Output: `test-wrap: all 491 passed`
Verdict: PASS. The suite grew by 7 assertions across two spots: a new `=== merge: the re-merge
dedupes a union-merged kanban row before pushing ===` block (6 assertions, a real two-row conflict
built the same way PR #608's own fixtures are, with NOTHING stubbed about git merge behavior) plus
one added assertion on the existing LAB_LOG re-merge case proving a non-kanban union file is left
alone.

Command: `bash tests/test-meta.sh`
Exit: 0
Output: `Passed: 852 / 852`
Verdict: PASS.

Command: `bash bin/lint --all`
Exit: 0
Verdict: PASS. No hit anywhere in `lib/board/backlog.sh`, `lib/wrap/wrap.sh`,
`tests/test-wrap.sh`, or `tests/test-board-dedupe-all.sh`; every existing hit the lint reports is a
pre-existing citation in an unrelated `docs/specs/*.md` file, none of them touched by this change.

## The real defect, reproduced with no stubs

The new `test-wrap.sh` case builds two real bare/clone repos exactly like PR #608's own fixtures: a
base commit with two adjacent kanban rows (`ID-401`, `ID-402`, both `queued`), a branch commit that
flips `ID-401` to `shipped`, and a `main` commit that flips `ID-402` to `executing`. Nothing about
`git merge` is stubbed; only `gh` is (the PR detail/merge calls). Running the real merge on this
fixture (verified by hand outside the suite too) reliably produces:

```
| ID-401 | row a | src | shipped |
| ID-402 | row b | src | queued |
| ID-401 | row a | src | queued |
| ID-402 | row b | src | executing |
```

both ids duplicated, one queued copy and one flipped copy each, in the exact shape the lead deduped by
hand. `wrap merge --apply` on this fixture: re-merges, dedupes to one row per id (the flipped one for
each), lands the dedupe as its own commit (`git log --format=%s -3` on the recovered branch: `fix(board):
dedupe union-merged rows`, then the merge commit, then `branch flips 401`), and still pushes and merges
the PR.

## A pipefail/SIGPIPE trap the test itself had to route around

The first version of the new commit-identity assertion piped a LIVE `git log --format=%s -3` straight
into `grep -qx`. Under `pipefail` (this suite's own `set -uo pipefail`), an external process (unlike a
bash builtin) that is still writing when `grep -qx` finds its match on line 1 and closes its read end
can receive a real `SIGPIPE` and exit 141; `pipefail` then reports the PIPELINE'S exit as 141, not
grep's actual match. `trap '' PIPE` around the group did NOT protect it, empirically (confirmed with a
five-line repro using `git --version | head -n1`): ignoring SIGPIPE in the parent shell does not survive
`exec` into an external binary in this environment, unlike a builtin (`printf`), where the existing
`chk_has`/`chk_no` helpers' identical `trap '' PIPE` guard does work because no `exec` is involved. The
fix: capture `git log`'s output into a variable first, then `grep` the captured string (a builtin write,
never at risk), matching the pattern the rest of the file already uses for every other exact-match
check. This is a test-authoring fix, not a `wrap.sh` behavior change; the underlying dedupe/commit/push
sequence was correct in every run once the assertion itself stopped racing.

## Negative control

Command: `bash lib/gate/negctl.sh . 'bash tests/test-board-dedupe-all.sh' '<mutation>'`
Mutation: flip the status preference so the `queued` copy survives instead of the flipped one.

```
## Negative control (negctl)
Command: bash tests/test-board-dedupe-all.sh
Exit: 0 (green before mutation)
Mutation: perl -i -pe 's/\$2 != "queued"/\$2 == "queued"/' lib/board/backlog.sh
Changed: lib/board/backlog.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/board/backlog.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Two of the four assertions go RED under that mutation, `2 FAILED`:

```
FAIL queued+shipped dedupe wrong: n=1 status=queued out=ID-401
FAIL multi-id sweep wrong: out=[ID-401 ID-402], ID-401=queued, ID-402=queued
```

The other two (a tied-status pair keeps the first occurrence; a clean board is a no-op) stay green
under the mutation, and they should: neither depends on which side of the `queued` comparison wins.
The two that flip are exactly the ones asserting the actual keep-rule, which is what this control
proves.

## Not covered

A duplicate spanning three or more copies of one id is not exercised (PR #608's own union-merge
mechanics only ever produce two copies per id, one per side of the merge); `dedupe_all`'s loop still
handles it correctly (first non-`queued` row wins, or the first row on an all-`queued` tie) but no
fixture forces that shape. A commit that fails at the `_union_dedupe_rows` step (lock contention, a
rejected commit) is handled (reported, not silently swallowed) but not exercised by a fixture, since
forcing a real git commit failure deterministically was out of scope for this proof.

## Reproduce

```
git -C <repo> switch feat/wrap-union-dedupe
bash tests/test-board-dedupe-all.sh   # the keep-rule, 4 assertions
bash tests/test-wrap.sh               # the wiring, 491 assertions total
bash tests/test-meta.sh               # structural integrity, 852 assertions
bash bin/lint --all                   # no new scattered-id hits
bash lib/gate/negctl.sh . 'bash tests/test-board-dedupe-all.sh' \
  'perl -i -pe '\''s/\$2 != "queued"/\$2 == "queued"/'\'' lib/board/backlog.sh'
```
