# Verification -- wrap-handoff-archive

`handoffs.sh archive` moves one finished handoff into `archive/` (git mv when tracked, mv -n when untracked, never a delete), `commands/wrap.md` gains step 1b that closes handoffs against git and gh, and the DEAD text in `handoffs.sh` and `commands/start.md` now says archive instead of delete.

## Green run
```
Command: bash lib/session/tests/test-handoffs.sh
Exit: 0
Output:
  ok: outcome line: archived (git mv): _meta/handoffs/tracked.md -> _meta/handoffs/archive/tracked.md
  ok: file moved and the index records a rename
[22] archive: untracked file moves with plain mv
  ok: untracked moved: archived (mv): .claude/handoffs/loose.md -> .claude/handoffs/archive/loose.md
[23] archive: an existing target refuses and touches nothing
  ok: refused, both files intact: REFUSED: _meta/handoffs/archive/clash.md already exists
[24] archive: a nested file refuses
  ok: nested files refused and left in place
[25] archive: a tracked file refuses while the checkout is on the default branch
  ok: default-branch move refused: REFUSED: _meta/handoffs/onmain.md is tracked and /private/var/folders/dr/n3x74rr93kvfjf1873pyjvp80000gn/T/tmp.fwpPsSEdRU/repo is on 'main'; move it on a branch in a worktree
[26] archive: a missing <file> is a usage error, exit 64
  ok: exit 64 without a file

smoke: all 32 passed
Verdict: PASS (cases [21]-[26] are new, [10] updated for the DEAD text)
```

The report-lint accepts the new `STATE` row without a lint change:

```
Command: bash lib/wrap/report-lint.sh <report with "| STATE | handoffs: archived a.md, kept b.md (2 items open) | ... |">
Exit: 0
Output:
report-lint: clean (0 warn(s))
Verdict: PASS
```

## Negative control
```
Command: bash lib/gate/negctl.sh "$PWD" "bash lib/session/tests/test-handoffs.sh" "<remove the default-branch guard in cmd_archive>"
Changed: lib/session/handoffs.sh
Exit: 1 (under mutation, RED expected)
Output:
  [23] archive: an existing target refuses and touches nothing
  [24] archive: a nested file refuses
  [25] archive: a tracked file refuses while the checkout is on the default branch
    FAIL: tracked file on the default branch not refused (rc=0): archived (git mv): _meta/handoffs/onmain.md -> _meta/handoffs/archive/onmain.md
  [26] archive: a missing <file> is a usage error, exit 64
  
  smoke: 1 FAILED, 31 passed

Restore: git checkout HEAD -- lib/session/handoffs.sh
Exit: 0 (green after restore)
Verdict: PASS
```
Three more single-guard mutations each went RED on exactly one case and were restored the same way: the existing-target refusal removed (case [23]), the top-level directory check removed (case [24]), `git mv` swapped for `mv -n` (case [21], rename not staged).

Rollback: `git revert` of the feature commit. A handoff the verb already moved is restored with `git mv <dir>/archive/<file> <dir>/<file>` (tracked) or `mv -n` (untracked).

## Not proven
- The wrap step 1b prose is not executed by any test; it is a command-layer instruction like its neighbours.
- The handoff skill lives in another repo and still says only that wrap "may" archive; its wording is unchanged here.
