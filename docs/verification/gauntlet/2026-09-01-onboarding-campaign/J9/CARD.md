# Seed card J9 (persona A: concurrent second contributor)

**Card:** Fix the README example, same tiny-lane ask as the doorway card , but
you are not the only one in this repo right now.

**Context:** You have adopted dwarves-kit into `/work/fixture-repo` (if not yet
adopted, that is your first step; the kit tarball is at `/work/kit.tar.gz` and
its README is your instruction set). A branch `other/logging-tweak` already
exists in this repo: another contributor is mid-change on `cli.js`'s usage
text. It is real, in-flight work, not a decoy , do not silently clobber it.

**Acceptance criteria:**

1. `git branch -a` (or the kit's multi-session discipline) is checked BEFORE
   you start editing `cli.js`, and the other branch's existence is recorded in
   `PR.md` , you noticed it, you did not stumble into it.
2. `other/logging-tweak` is left untouched: same tip commit, same content, no
   force-push, no rewrite.
3. Your own branch merges cleanly against `other/logging-tweak` (no
   collision on the lines you touched).
4. The tiny-lane fix itself still lands: the README example matches the
   actual CLI flag, on a branch with `PR.md` (title + body; no network push is
   expected in the room).

**Verification command:** `bash /work/checks/check-submission-user-J9.sh /work/fixture-repo`

**Size cap:** one agent-day. **Termination:** if blocked with no path forward in
the kit's docs, STOP and write `BLOCKED.md` stating exactly what you needed and
where you looked; that is a valid submission.
