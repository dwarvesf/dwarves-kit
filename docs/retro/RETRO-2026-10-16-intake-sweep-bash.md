# Retro: intake-sweep runs as bash plus jq (SPEC-407)
Date: 2026-10-16
Sprint: one session, second of the four remaining Python hook ports

Answers below were drafted by the lead from the session record, not collected one question at a time.

## Metrics
- Goldens: 160 hook cases and 5 grammar-twin checks, generated from the Python and the stdlib before the port was written
- Real data: the real digest ledger, board, and staging file, three scenarios, byte-identical
- Fresh review rounds: 1 (NEEDS REVISION, 2 critical, 12 warnings), all folded
- Negative controls: 7, all red under their mutation

## What worked
- The real digest ledger and board gave a byte-exact check (SHA-256 of the staging file) that the corpus could not give: the harness reads files back through `$(cat)`, which strips trailing newlines.
- A reviewer who ran the port on a Linux-style `stat` found a bug no macOS run could: after the first stamp, the throttle died with an unbound variable. The fix is one helper (`hu_mtime`, GNU first), now pinned by a test that puts a GNU-answering `stat` on the PATH.
- Putting the shared helpers in `lib/reflect/hook-util.sh` while the first hook was still in review meant the review's fixes land once for the two hooks that follow.

## What hurt
- The corpus was written from the author's reading of the Python, so every class the reviewer found (an `include` typo on an empty file, a list-valued `kind`, a BOM) was a class the author had not thought of. The goldens catch a divergence only for a shape someone wrote down.
- `git stash pop` brought staged changes back into the index, and the next `git commit` swept them into the wrong commit. The branch was reset to master with `git reset --mixed` and recommitted by hand.
- A hook that blocks any Bash command containing `git ... push` fired on `git stash push`; `git stash -u` does the same job.

## Action items
- None for the operator. The next two ports reuse `hook-util.sh` and the grammar twin, and carry the same Linux and temp-file checks.
