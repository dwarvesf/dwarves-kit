# Seed card J8 (persona A: review response)

**Card:** The `--upper` flag has never formally gone through this repo's
review step. Take it through review and ship it: `/kit:review` (or the team
lens), fix what review finds, then ship , do not verdict-shop past a finding
you'd rather ignore.

**Context:** You have adopted dwarves-kit into `/work/fixture-repo` (if not yet
adopted, that is your first step; the kit tarball is at `/work/kit.tar.gz` and
its README is your instruction set). The README documents `--upper`'s usage
including its error behavior on empty input. The current code does not match
that documentation , this is exactly the shape of hole review exists to
catch before ship, not after.

**Acceptance criteria:**

1. Tests exist for `--upper`, including its documented empty-input behavior.
2. A review verdict is recorded (`/kit:review`'s SHIP / FIX-REQUIRED / DO NOT
   SHIP, or the team lenses' equivalent) and the edge-case hole is named in
   it , the review actually looked, it did not rubber-stamp.
3. The hole is fixed to match the documented behavior: `node cli.js --upper`
   with no text argument exits non-zero with a usage message, not a silent
   blank line.
4. The change rides a branch with `PR.md` (title + body; no network push is
   expected in the room).

**Verification command:** `bash /work/checks/check-submission-user-J8.sh /work/fixture-repo`

**Size cap:** one agent-day. **Termination:** if blocked with no path forward in
the kit's docs, STOP and write `BLOCKED.md` stating exactly what you needed and
where you looked; that is a valid submission.
