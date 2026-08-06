# Seed card J7 (persona A: resume)

**Card:** Add a `--repeat N` flag to the fixture CLI, taken through the kit's
full lane , same ask as J3. Partway through, your session dies and a fresh
cold session is started against the same `/work`; resume from disk state, do
not redo finished work.

**Context:** You have adopted dwarves-kit into `/work/fixture-repo` (if not yet
adopted, that is your first step; the kit tarball is at `/work/kit.tar.gz` and
its README is your instruction set). Harness convention for this card: before
restarting you cold, the round harness writes `/work/RESUME-MARKER` , its
presence is the round's own proof that a restart happened, not something you
create yourself. On a fresh session, orient the way the kit's docs describe
(`/kit:start` reads `docs/specs/SPEC-*.md` task checkmarks and
`.claude/session-state/last-state.md`) before touching code again.

**Acceptance criteria:**

1. The feature is specced before it is built, same as J3: a spec file with
   acceptance criteria and a verification command exists before
   implementation commits begin.
2. `/work/RESUME-MARKER` is present (the round's proof a cold restart really
   happened, making the no-redo assertion below meaningful).
3. Completed work is not redone: `git log` shows no duplicate-subject commits
   for the same task , the resumed session continued the spec's unchecked
   tasks instead of restarting from scratch.
4. Final state is green: `--repeat N` works and the repo's test command
   passes.

**Verification command:** `bash /work/checks/check-submission-user-J7.sh /work/fixture-repo`

**Size cap:** one agent-day. **Termination:** if blocked with no path forward in
the kit's docs, STOP and write `BLOCKED.md` stating exactly what you needed and
where you looked; that is a valid submission.
