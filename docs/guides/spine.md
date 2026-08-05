# The spine (user guide)

Every piece of full-lane work rides the same backbone from "what should I do"
to "shipped and learned from". You rarely type these commands, you say what you
want and the kit routes, but knowing the spine tells you where you ARE and what
comes next.

```
 /kit:start ....... "where am I?" renders the board + drafts (read-only)
      │
 /kit:assign ...... turns a board row into a scoped goal + lane pick
      │                (the ONLY step that mutates the board)
 /kit:spec ........ the contract: tasks, acceptance criteria, verification
      │
 /kit:spec-validate  adversarial review; Status: VALIDATED
      │
 /kit:execute ..... build: worker per task -> verifier -> bounded retries
      │
 /kit:review ...... verdict on the diff (SHIP / FIX THEN SHIP / DO NOT SHIP)
      │
 /kit:docs ........ README/CHANGELOG brought back in line with the code
      │
 /kit:ship ........ tests, version, changelog, PR; the ship gate lives here
      │
 /kit:retro ....... what worked, what did not, filed for next time
```

State lives on disk between every step (the BACKLOG row, the SPEC file, goal
drafts), never only in a session: you can stop anywhere and a fresh session
resumes from `/kit:start`.

## What you do

- **Enter anywhere, but let `/kit:start` orient you.** It reads the repo state
  and suggests the next step; it never runs it. You decide.
- **Front-load your opinions at assign/spec time.** The spec is the cheapest
  place to change your mind; execute is the most expensive. Everything after
  VALIDATED assumes the contract holds.
- **Do not skip forward.** Asking to ship what was never specced or reviewed
  does not remove the gates; it just makes you meet them all at once at the
  ship step, where fixes are dearest.
- **Small work takes a short spine.** The lanes (guide: `lanes.md`) scale how
  much of this ceremony a change deserves; a tiny edit runs almost none of it.

## Common questions

- **"Where did my task go?"** Shipped rows drop off the board; the CHANGELOG is
  the shipped record. `/kit:start --full` shows the trail.
- **"Can I just talk instead of typing commands?"** Yes, that is the intended
  interface. "fix this bug", "spec this idea", "ship it" route to the right
  spine step (MANUAL.md, "Drive it by intent").
