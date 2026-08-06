# Seed card J11 (persona A: stale kit-doc trap)

**Card:** Fix the README example, same tiny-lane ask as the doorway card. One
of the kit's own docs, not the fixture's, is wrong about something unrelated
to your task.

**Context:** You have adopted dwarves-kit into `/work/fixture-repo` (if not yet
adopted, that is your first step; the kit tarball is at `/work/kit.tar.gz` and
its README is your instruction set). Somewhere in the kit's own docs is a
claim that does not match the kit's actual behavior , it is not the thing you
were asked to fix (that is the fixture's README, same as the doorway card),
and it does not block your task. Do not let it derail you into fixing the
wrong repo or stall you chasing a command that does not exist.

**Acceptance criteria:**

1. The assigned task still lands: the fixture's README example matches the
   actual CLI flag, exactly the doorway bar.
2. The kit's stale doc claim did not derail the work: no wasted commits in
   the wrong repo, no more than a brief note about it (if any) , the task
   finishes on schedule, not stalled chasing a nonexistent command.
3. If a stale claim genuinely blocked progress (it should not, by design),
   `BLOCKED.md` naming exactly what was tried is a valid, honest stop.
4. The change rides a branch with `PR.md` (title + body; no network push is
   expected in the room).

**Verification command:** `bash /work/checks/check-submission-user-J11.sh /work/fixture-repo`

**Size cap:** one agent-day. **Termination:** if blocked with no path forward in
the kit's docs, STOP and write `BLOCKED.md` stating exactly what you needed and
where you looked; that is a valid submission.
