# The autonomy dial

Use this when you want the kit to check in with you more, or less, while it works.

## What happens

- You set the dial per run, by how you phrase the ask. There is no config file to edit.
- The kit reads your phrase and picks one of four positions: propose, low, high or max. Low is the default.
- A higher position means fewer courtesy check-ins. It never means fewer gates.
- At every position the kit still stops at the four hard stops ([gates-and-proof.md](gates-and-proof.md)): safety-gate, push-to-main, anti-rationalization and the verification pipeline.
- It also stops where a human must decide: a change to architecture direction, to which file is canonical, to a guardrail, to a risk lane, or to secrets and access. These stops come from the pause rules in `AGENTS.md`.
- At high and max, a judgment call you would have been asked about is written down instead of interrupting you. You review the calls afterward, not the pauses during.

## What you do

1. **Say the position in the ask.** The phrase is the interface:

   | You say | Position | It stops at |
   |---|---|---|
   | "propose it, don't run anything" | propose | after planning; waits for your go |
   | "run it, check with me at each phase" | low (default) | every advisory phase boundary |
   | "run the lane, only stop at hard stops" | high | the four hard stops, and the push or PR |
   | "run it all the way to a PR, your call" | max | the four hard stops, and a real blocker |

2. **Match the dial to how reversible the work is, not to how much you trust the agent.** Reversible work on a branch tolerates max. Anything outward-facing (a send, a publish, a deploy) deserves low, even from an agent you trust. A wrong check-in costs seconds. A wrong send does not.

   | Work | Position |
   |---|---|
   | You are not sure the plan is right yet | propose |
   | A change in a shared area, or a spec you want to watch | low |
   | A well-specced change on a branch | high |
   | A reversible change you will review in the PR anyway | max |
   | A send, a publish or a deploy | low, even from an agent you trust |

3. **Name a concern to make it a checkpoint.** "Check with me before touching the schema" works at any position.
4. **Review the recorded calls after a high or max run.** They live in `docs/implementation-notes/<spec-slug>.md`. Skipping that review turns recorded decisions back into silent ones.

Two things never move with the dial:

- **The four hard stops hold at every position.** Max autonomy is not gate bypass. It is fewer check-ins.
- **Decisions taken alone get recorded.** The builder appends an entry whenever it decides something the spec left open, deviates, or hits a tradeoff.

## What you will see

A hard stop prints a block message and the run halts, even at max. The safety gate on a destructive delete:

```
BLOCKED: Destructive delete detected. Use 'trash' or 'mv' to a temp directory instead of rm -rf (build artifacts like node_modules/dist are allowlisted).
```

A decision the run made alone shows up as an entry in the implementation note (the shape comes from `commands/execute.md`):

```
## YYYY-MM-DD HH:MM <title>
Context: ...
Decision/Change: ...
Why: ...
Alternatives considered: ...
Impact: ...
Open questions: ...
```

A build with nothing to record leaves one line: `No deviations; matches the spec verbatim`.

## When it breaks

| You see | Do this |
|---|---|
| It asked you a question at max | It hit a hard stop, or a real fork with an irreversible cost either way. This is the designed floor, not disobedience. |
| It did not ask you something you wanted to weigh in on | Lower the dial next run, or name the concern in the ask. A named concern becomes a checkpoint. |
| It stopped at the push or PR on a high run | That is the high position. Say "all the way to a PR" for max. |
| A hard stop fired and you want to continue | Take the way through in [gates-and-proof.md](gates-and-proof.md). Do not look for a switch. The dial does not waive a hard stop. |
| You cannot find what the run decided | Read `docs/implementation-notes/<spec-slug>.md` for the spec in question. |

## Related

- [gates-and-proof.md](gates-and-proof.md): the four hard stops and the way through each
- [spine.md](spine.md): the phase boundaries the low position stops at
- [grill.md](grill.md): the interview the kit runs before it works
- [scenarios.md](scenarios.md): the extra checks it surfaces while you shape work
