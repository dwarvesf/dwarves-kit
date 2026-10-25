# Seed card (persona B: kit contributor)

**Card:** Make one small fix to the kit itself and take it through the kit's own
gates.

**Context:** You are a developer contributing to dwarves-kit for the first time.
A clone of the kit is at `/work/kit`. Its own docs (README, PHILOSOPHY,
WORKFLOW, AGENTS.md) are your only instructions.

**The fix:** `docs/guides/README.md` states one page shape that every guide
follows (the section names, in order, with `Use this when` as the opening
line). Check every guide in `docs/guides/` against that shape. Correct
EITHER each guide that deviates OR the README's claim, whichever the
evidence supports. If no guide deviates, say so in `PR.md` and correct the
one index row, link, or sentence in the README that the evidence shows is
wrong. (Small on purpose: the work is trivial; the gauntlet measures whether
the kit's docs get you through its process.)

**Acceptance criteria:**

1. The fix is correct (evidence cited in the commit body: name the guides you
   checked against the page shape).
2. It rides a branch with a conventional-commit subject per the kit's rules.
3. The kit's own gate expectations for a docs change are met the way its docs
   describe them (including whatever the ship gate wants, or the documented
   override path with a reason).
4. A PR-shaped description exists (`PR.md`; no network push expected).

**Verification command:** `bash /work/checks/check-submission-contributor.sh /work/kit`

**Size cap:** one agent-day. **Termination:** if blocked with no path forward in
the kit's docs, STOP and write `BLOCKED.md` stating exactly what you needed and
where you looked; that is a valid submission.
