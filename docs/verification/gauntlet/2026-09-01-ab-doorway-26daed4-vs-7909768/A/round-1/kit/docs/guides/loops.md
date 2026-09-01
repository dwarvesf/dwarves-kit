# Bounded loops (user guide)

Several kit commands do not run once; they LOOP: try, check, revise, try again.
Every loop in the kit is bounded, it carries a hard cap and a verifiable stop,
and "did not converge" is a reported outcome, never a silent retry-forever. This
guide is what that means for you.

```
 attempt -> check against a stop condition
    │             │
    │        stop holds -> DONE (verdict + record)
    │        progress but cap hit -> HONEST HALT (verdict: what is left)
    │        no progress -> HONEST HALT (that fact is itself the finding)
    └────────── revise, go again (only while under the cap)
```

## The loops you will meet

| Loop | It converges | Cap | You see |
|---|---|---|---|
| Goal (`/goal`) | one objective until its verification command passes | your stated stop | done, or a named blocker |
| Debug (`/kit:debug`) | root cause before any fix | 3 fixes = architecture wall | evidence ledger; a confirmed cause, then the fix |
| Execute (`/kit:execute`) | each spec task through verify | 2 retries per task | per-task verdicts; escalations, not silent retries |
| Revise engines (`/kit:test-plan-review-team`, `/kit:gauntlet`) | one artifact until findings clear | 3 rounds | SOLID / REVISE / RECONSIDER |

## What you do at each outcome

- **Converged**: read the record (each loop persists one: verification output,
  evidence ledger, round records) rather than re-verifying by vibe. The record
  is the proof; it is what review and ship gates consume.
- **REVISE / cap hit with progress**: the artifact improved but is not clean.
  The remaining findings are listed; apply them yourself or rerun the loop
  later. Nothing is blocked by default, revise engines advise.
- **RECONSIDER / no progress**: the loop is telling you the problem is not at
  the level it can fix, a design gap, a mis-scoped task, a missing tool. Change
  the level: revisit the spec, the requirement, or the approach. Rerunning the
  same loop harder is the one guaranteed waste.

## Common questions

- **"Why not let it keep looping until it succeeds?"** Unbounded loops hide
  non-convergence as cost. The cap converts "it is not working" into information
  you get today, with a record of what was tried.
- **"Can I raise the cap?"** You can, per run, but first ask what the extra
  rounds would learn that the recorded rounds did not. Three rounds without a
  severity drop is a design signal, not a patience problem.
- **"Which loop do I want?"** Say the intent, the kit routes: "fix this bug" is
  debug, "build this spec" is execute, "keep going until X passes" is a goal,
  "make this artifact good" is a revise engine.
