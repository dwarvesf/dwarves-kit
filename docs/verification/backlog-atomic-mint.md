# Verification -- backlog-atomic-mint

`board capture`'s mint+append ran with no lock: two live sessions each read
`_meta/BACKLOG.md`, computed the same next id, appended, and pushed, and the
`merge=union` attribute landed both rows on main (the ops-toolkit 960-967
collision, renumbered by hand). `board promote` (add-backlog) already flocked a
per-board tmpfile, and `backlog_sync.py` flocked its own state dir, but neither
covered the capture path, and capture/promote/sync did not exclude each other.

Fix: one shared lock address, `tmpdir/board-<md5(realpath)>.lock`, extracted
into `sync_core.board_lock()` (the add-backlog convention, now the single
helper) and held by every minter over exactly its read -> mint -> append ->
write window:

- `board.sh cmd_capture`: the heredoc now reads the file INSIDE
  `board_lock(path)`, mints from that fresh text (a taken id can never be
  handed out -- `next_id` derives max+1 from the file under the lock, so the
  collision guard is structural, not a check that can be skipped), and writes
  via mkstemp + os.replace instead of a bare `write_text`.
- `add-backlog`: same inline flock, rewired onto the shared helper; behavior
  unchanged (the lock address is byte-identical).
- `backlog_sync.py` `sync_source`/`sync_pull_only`: board read -> plan ->
  apply -> write under `board_lock(backlog)`; the spoke network read stays
  outside the hold so a slow source never stalls an interactive mint. The
  existing `state_dir/.lock` still serializes sync-vs-sync; the new lock is
  what capture/promote share.

Not covered, by design: a session that hand-edits BACKLOG.md with no tool
holds no lock; the publish-side duplicate scan (`cmd_publish` WARN, exit 3)
remains the backstop for anything that bypasses the writers.

## Green run

```
Command: bash tests/test-board-atomic-mint.sh
Exit: 0
Verdict: PASS -- 11/11 (AC1 six concurrent captures mint six unique ids and
  all 9 rows land; AC2 a capture queued behind a held lock re-reads the file
  and mints ID-5 past the holder's appended ID-4, waiting >=1s; AC3 a
  `board promote` racing three captures mints uniquely through the same lock)
```

```
Command: bash tests/test-board-promote.sh && bash tests/test-board-publish.sh
Exit: 0
Verdict: PASS -- promote 34/34, publish 26/26 (the add-backlog rewire and the
  post-rebase dup guard both unchanged in behavior)
```

```
Command: uv run --no-project --with pytest -- pytest lib/sync/tests -q
Exit: 0
Verdict: PASS -- 290 passed (the sync_source/sync_pull_only lock restructure
  keeps the whole engine suite green)
```

```
Command: bash tests/run-all.sh --changed
Exit: 0
Verdict: PASS -- all 40 changed-scope suites. Note: docs/FEATURES.md had
  drifted on master before this branch (verified on a clean master checkout);
  regenerated with `feature-registry.sh check --fix`, which the
  SPEC-219 freshness pin then passed.
```

## Negative control

```
Command: git stash push -- lib/board/board.sh (drops the capture lock only),
  then bash tests/test-board-atomic-mint.sh, then git stash pop
Exit: 1
Verdict: NEGATIVE CONTROL RED -- 4/11 passed, 7 failed. AC1 lost uniqueness
  (`all six minted ids are unique` FAIL; `board holds all 9 rows` FAIL --
  a clobbered write lost a row, the worse half of the incident) and AC2 lost
  the wait (`capture waited for the holder` FAIL; it minted the taken ID-4).
  Restored via `git stash pop`; re-ran, 11/11.
```

## Rollback

`git revert` the commit. The lock file is a tmpdir artifact with no repo
state; removing the lock restores the pre-change race window but breaks
nothing else. No migration, no flag, no persistent format change.

## Reproduce

```bash
bash tests/test-board-atomic-mint.sh
bash tests/test-board-promote.sh
uv run --no-project --with pytest -- pytest lib/sync/tests -q
```
