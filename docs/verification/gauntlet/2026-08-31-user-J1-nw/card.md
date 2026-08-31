# Seed card (persona A: kit user)

**Card:** Adopt dwarves-kit into the fixture repo and ship one tiny-lane change
through the kit's loop.

**Context:** You are a developer who has never used dwarves-kit. A tarball of
the kit is at `/work/kit.tar.gz`. A small git repo (a Node CLI with one failing
edge case in its README example) is at `/work/fixture-repo`. The kit's own docs
are your only instructions; start from its README.

**Acceptance criteria:**

1. The kit is installed and the fixture repo is adopted (the kit's own check
   reports adopted).
2. One tiny-lane change ships through the kit's loop: fix the README example in
   `/work/fixture-repo` (the documented command does not match the actual CLI
   flag).
3. The change lands on a branch with a PR-shaped description (title + body
   written to `PR.md`; no network push is expected in the room).
4. The loop's leave-behinds exist: the adoption contract file, and whatever
   run/gate records the kit's docs say a change produces.

**Verification command:** `bash /work/checks/check-submission-user.sh /work/fixture-repo`

**Size cap:** one agent-day. **Termination:** if blocked with no path forward in
the kit's docs, STOP and write `BLOCKED.md` stating exactly what you needed and
where you looked; that is a valid submission.
