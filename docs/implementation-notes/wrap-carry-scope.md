# Implementation notes -- wrap-carry-scope

Delta from the request.

- A failed `git stash push` exits 2, the code `_start_carry` already uses for a carry that could not complete. The three push variants collapsed into one call through a pathspec array, so one exit check covers them.
- Scope fix is a post-apply restore, not a per-path apply. The stash commit's tree holds the whole index, so every path `diff HEAD` lists outside the named paths is reset to HEAD (staged-new files are removed). Git decides what is "outside" through `:(exclude)` pathspecs, so globs and directories match as they do in `stash push`.
- With paths, the `carried:` line now prints after the restore and reads the worktree. With no paths it still prints before the apply from the stash, unchanged.
- The restore runs on a conflicted apply too, so a conflict leaves no outside strays either. The stash entry is still kept.
- Test cases live in `tests/test-wrap-start.sh`, which holds the other `start --carry` cases.
