# Seed card J4 (persona A: bug lane / debug loop)

**Card:** CI is red on `shout`, but the README says `npm test` passes. Find out
why and fix it the way this repo's process handles a bug, not a guess-fix.

**Context:** You have adopted dwarves-kit into `/work/fixture-repo` (if not yet
adopted, that is your first step; the kit tarball is at `/work/kit.tar.gz` and
its README is your instruction set). The repo has a test suite (`npm test`)
and the README claims it is green. It is not: one test fails.

**Acceptance criteria:**

1. The root cause is recorded BEFORE any fix commit: an evidence ledger exists
   (the kit's debug loop writes `.claude/debug/<slug>.md`) with its
   `## Root cause` section filled in, not left blank.
2. The regression is fixed: `npm test` passes, including the previously
   failing test.
3. The fix commit (or the evidence ledger) references the recorded root
   cause , the fix is traceable back to the diagnosis, not a parallel guess.
4. The change rides a branch with a PR-shaped description (title + body
   written to `PR.md`; no network push is expected in the room).

**Verification command:** `bash /work/checks/check-submission-user-J4.sh /work/fixture-repo`

**Size cap:** one agent-day. **Termination:** if blocked with no path forward in
the kit's docs, STOP and write `BLOCKED.md` stating exactly what you needed and
where you looked; that is a valid submission.
