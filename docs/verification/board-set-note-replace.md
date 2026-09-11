# Verification: a terminal state's note supersedes the in-flight ones

`lib/board/backlog.sh` `set_state` built the status cell as `rest = " [" note "]" rest`, prepending every note. A row flipped twice carried both. A shipped row could therefore keep an older note that still described the work as open, and a reader cannot tell which note is current.

ID-834 is the row that produced this. It shipped carrying its own earlier `[PARTIAL: ... Next: ... decide barrier vs wire]` bracket, which described the exact work the shipping PR had just completed. A human deleted it by hand in PR #597.

## Change

`shipped` and `dropped` replace the note. Every other state keeps stacking.

Two deliberate carve-outs, both covered by a case below:

- **A terminal flip with NO note preserves what is there.** Erasing without a replacement would destroy the only record the row has.
- **`parked` keeps stacking.** A parked row is resumable and needs the context it was parked with. Only `shipped` and `dropped` end a row.

## Green run

```
Command: bash tests/test-board-set-note.sh
PASS in-flight keeps stacking, newest first: executing [second] [first]
PASS shipped supersedes the in-flight note: shipped [done, PR #1]
PASS dropped supersedes the in-flight note: dropped [superseded by ID-002]
PASS terminal with no note preserves the existing note: shipped [the only record]
PASS parked keeps stacking: parked [waiting on review] [context to resume from]
PASS the ID-834 shape lands a single current note: shipped [proven under matched load]
PASS row still has its original field count (6)
ALL PASS
Exit: 0
Verdict: PASS
```

Case 6 replays the real ID-834 shape: flip to `executing` with a PARTIAL note, then to `shipped`, and assert the word `PARTIAL` is gone from the cell.

## Negative control

Restore the pre-fix line and re-run. `HEAD~1` is the merge-base commit, so this is the shipped behaviour, not a hand-written approximation.

```
Command: git checkout HEAD~1 -- lib/board/backlog.sh && bash tests/test-board-set-note.sh; git checkout HEAD -- lib/board/backlog.sh
78:      if (note != "") rest = " [" note "]" rest
PASS in-flight keeps stacking, newest first: executing [second] [first]
FAIL shipped should carry only its own note, got: shipped [done, PR #1] [half done, next: decide]
FAIL dropped should carry only its own note, got: dropped [superseded by ID-002] [in progress]
PASS terminal with no note preserves the existing note: shipped [the only record]
PASS parked keeps stacking: parked [waiting on review] [context to resume from]
FAIL the shipped row still carries the superseded PARTIAL note: shipped [proven under matched load] [PARTIAL: still failed under load. Next: decide barrier vs wire]
PASS row still has its original field count (6)
3 FAILED
Verdict: RED as expected, then restored clean
```

The control bites on exactly the three terminal-replacement cases. The four cases that assert UNCHANGED behaviour (in-flight stacking, terminal-with-no-note, `parked`, row shape) still pass against the old code, which is what shows the change is surgical and the suite is not over-asserting.

The suite prints its verdict and exits 1 on any failure (last line of the file).

## Reproduce

```bash
bash tests/test-board-set-note.sh
```

`tests/run-all.sh` globs `tests/test-*.sh`, so this suite is picked up by the full run.

## Scope

`set_state` is the only writer of the status cell. `lib/board/board.sh`, `bin/board`, and the `commands/*.md` call sites all route through it, so no caller needed a change.
