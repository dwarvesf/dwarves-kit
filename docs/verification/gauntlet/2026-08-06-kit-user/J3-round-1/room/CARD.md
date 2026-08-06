# Seed card J3 (persona A: full lane, end to end)

**Card:** Add a `--repeat N` flag to the fixture CLI, taken through the kit's
FULL lane.

**Context:** You are a developer who has adopted dwarves-kit into
`/work/fixture-repo` (if not yet adopted, that is your first step; the kit
tarball is at `/work/kit.tar.gz` and its README is your instruction set). The
team asks: "`shout --upper hello` works; we want `--repeat N` so
`shout --upper --repeat 3 hello` prints the result three times. Ship it the way
this repo's process says features ship."

**Acceptance criteria:**

1. The feature is specced before it is built: a spec file exists with acceptance
   criteria and a verification command, and shows the kit's validated state
   before implementation commits begin.
2. `--repeat N` works: correct output for N=1, N=3; a sensible error for N=0,
   negative, and non-numeric input (your spec decides and documents which).
3. Tests exist for the above and pass; the spec's verification command is the
   one that proves it.
4. The change rides a branch; review happened the way the kit's docs describe
   (its verdict recorded); `PR.md` carries the PR-shaped description.
5. The gate leave-behinds the kit's docs promise for a behavioral change exist
   (proof-of-done with a negative control, or the documented override with a
   reason).

**Verification command:** `bash /work/checks/check-submission-user-J3.sh /work/fixture-repo`

**Size cap:** one agent-day. **Termination:** if blocked with no path forward in
the kit's docs, STOP and write `BLOCKED.md` stating exactly what you needed and
where you looked; that is a valid submission.
