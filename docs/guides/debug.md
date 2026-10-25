# The debug loop (user guide)

"Fix this bug" does not go straight to a fix. It enters a loop whose one iron
law is: **no fix without a recorded root cause.** A fix that works for reasons
nobody can state is a second bug with better manners.

```
 symptom reported
      │
 Phase 0  reproduce it (no reproduction -> that IS the first task)
      │
 Phase 1  gather evidence into a LEDGER: what was observed, what
      │   was ruled out, with commands and output, not vibes
 Phase 2  form hypotheses; test the cheapest discriminating probe
      │
 Phase 3  root cause RECORDED (while it is blank, the guess-fix guard
      │   blocks a "done" claim when [gate] understanding_gate is on)
 Phase 4  the fix + a test that fails without it
      │
 exit: fix verified, ledger kept
      │
 ─── the 3-fix wall: three failed fix attempts on one symptom means
     STOP, the problem is architectural; escalate the design instead
```

## What you do

- **Report symptoms, not diagnoses.** "The invoice job 500s after 14:00 UTC"
  beats "the cache is broken", your diagnosis anchors the search wrong if it
  is wrong.
- **Hand over reproduction steps if you have them.** Phase 0 is the slowest
  step; anything you know (inputs, timing, environment) shortens it.
- **Respect the guard when it refuses a "done" on a quick patch.** The guard is
  not bureaucracy; a patch before root cause usually moves the symptom and
  destroys the evidence. A bug-lane push with no recorded `debug` gate is
  refused by the ship gate too.
- **At the 3-fix wall, change altitude.** Three failed fixes is the loop
  telling you this is a design problem wearing a bug costume. The next step is
  a design conversation, not fix number four.

## Common questions

- **"It's obviously a one-liner, why the ceremony?"** If it is truly obvious,
  Phase 0-3 take two minutes and the ledger is three lines. The ceremony is
  only heavy when the bug is, which is exactly when you need it.
- **"Where does the ledger go?"** To `.claude/debug/<slug>.md`, a local file
  that is not committed (`.claude/` is ignored by default). For recurring or
  costly incidents, copy it into an INC record so the next occurrence starts
  from evidence, not from zero.
- **"The bug came back."** Reopen with the OLD ledger; recurrence with
  evidence is a different (faster) search than a fresh symptom.
