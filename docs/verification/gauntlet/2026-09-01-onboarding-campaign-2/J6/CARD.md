# Seed card J6 (persona A: mid-flight drift)

**Card:** Add a `--repeat N` flag to the fixture CLI, taken through the kit's
full lane , same ask as J3. Partway through the build, the ask changes once;
amend, do not silently widen or restart.

**Context:** You have adopted dwarves-kit into `/work/fixture-repo` (if not yet
adopted, that is your first step; the kit tarball is at `/work/kit.tar.gz` and
its README is your instruction set). Once your spec has hardened (validated,
implementation under way), a file `/work/UPDATE-J6.md` may appear , if it
does, its contents are a real change to the ask from the team, not a test
artifact. Treat it exactly the way the kit's mid-flight amend rule says to.

**Acceptance criteria:**

1. The feature is specced before it is built, same as J3: a spec file exists
   with acceptance criteria and a verification command before implementation
   commits begin.
2. If `/work/UPDATE-J6.md` appears mid-build, the spec is amended , not
   silently edited, not restarted: the amendment happens at a task checkpoint,
   is add-only (new tasks appended, prior `- [x]` tasks untouched), and is
   recorded in an `## Amendments` entry in the spec.
3. The amendment's own ask is satisfied: the empty-string case for `--repeat`
   is tested and behaves in a documented way (your spec decides and states
   the behavior).
4. The change rides a branch with `PR.md` (title + body; no network push is
   expected in the room).

**Verification command:** `bash /work/checks/check-submission-user-J6.sh /work/fixture-repo`

**Size cap:** one agent-day. **Termination:** if blocked with no path forward in
the kit's docs, STOP and write `BLOCKED.md` stating exactly what you needed and
where you looked; that is a valid submission.
