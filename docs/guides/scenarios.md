# Scenarios

Use this when the kit starts showing you "survival scenarios" or "must NOT happen" rows while you shape work, and you want to know what they are for.

## What happens

- The kit lists the situations your work must survive before anyone writes a test. You do not ask for this. It rides the steps you already use.
- A scenario is a situation with an actor: "a new contributor's session dies mid-build, and they reopen it tomorrow". It is not a test case ("assert that resume skips completed tasks"). Test cases come later, derived from scenarios. It is also not a vague category ("the system fails"), because that has no actor to invert.
- The kit makes scenarios once, at the cheapest step that can see them, and then sharpens them downhill. A later step adds detail. It never starts again from a blank page.
- Each set is built with three moves: walk the actor's journey, invert every promise the work makes, and sweep the standard categories (happy path and boundary, failure, recovery, adversarial, concurrent).
- Each step has a fixed place for its rows, shown below.

| Step | What you get |
|---|---|
| `/kit:think` | A "Survival scenarios" section in the brief: 3 to 5 situations, no test detail |
| `/kit:design` | The sketch is refined. New promises in the design are inverted into new rows. |
| `/kit:grill` | The `Done =` line arrives with 2 or 3 "must NOT happen" scenarios |
| `/kit:spec` | `## Edge Cases` is seeded from the sketch, then extended by a full pass |
| `/kit:test-plan` | Matrix rows are built from the scenarios and the acceptance criteria |

## What you do

1. **React to the sketch; do not author it.** The kit generates. Your job is to veto rows that cannot happen in your world, and to name the one situation only you know about: the odd client, the legacy cron job, the person who always pastes rich text.
2. **Take the must-NOT-happen rows seriously.** They are the cheapest insurance in the flow. One line at grill time, such as "money moves without approval", becomes a gate later. Left unnamed, it becomes an incident.
3. **Expect adversarial and recovery rows.** The kit adds these two on purpose, because people skip them: what games the check, and what happens after an interruption.
4. **Give a reason for every skipped category.** "No concurrent access, because a single daemon writes" is a good skip. Silence is not.
5. **Check that each row has an actor.** A row with no actor is a category. Ask the kit to name who is acting.
6. **Defining a new loop?** It is not designed until it has five survival rows: convergence, non-convergence, bad input, interruption and a gamed metric. The `/kit:loop-engineering` skill holds you to this.
7. **Trace a test back to its row.** The same rows flow from the brief to the spec's edge cases, then to the test matrix, then (for contributor-facing surfaces) to gauntlet cards. Any test traces to the situation that justified it.

## What you will see

In the brief that `/kit:think` saves, the section has this shape:

```
## Survival scenarios
<!-- scenario-gen: 3-5 rows from the Q5 sketch; situations, no oracles -->
| # | Scenario | Category |
|---|---|---|
```

A filled row reads like this (an example, not a run):

```
| 1 | A new contributor's session dies mid-build; they reopen it tomorrow | recovery |
```

A normal artifact ends up with 5 to 12 rows in a table of `#`, scenario, category and source move. Fewer than 5 usually means the "invert each promise" move was skipped. Many more than 12 at idea time usually means test cases are posing as scenarios.

The kit builds each set with three moves, in this order:

| Move | Question it asks | Example |
|---|---|---|
| Journey walk | At each step of the actor's path, what is needed, and what happens when it is missing? | The contributor opens the repo with no setup |
| Guarantee inversion | For each promise, what makes it false? Spend most of the time on promises nobody wrote down. | "Merge does not deploy" becomes "a merge deploys by accident" |
| Category sweep | Which standard categories have a hole? | No recovery row yet |

A good set meets four checks. Every unwritten promise in the artifact has an inversion row or a stated skip. At least one recovery row and one adversarial row exist, or the set argues their absence. Each row names its actor. No row carries an expected value above the test-plan step.

## When it breaks

| You see | Do this |
|---|---|
| This feels like extra work at idea time | It is 3 to 5 rows sketched while you already ask "what breaks at scale". Finding the same rows in production costs more. |
| A row says "the system fails" | It has no actor. Ask the kit to name who acts and what they do. |
| A row contains an assert or an expected value | It is a test case. Move it to the test plan and keep the situation. |
| No adversarial or recovery row exists | Ask for them, or write one line saying why they cannot apply. |
| The spec has no scenario set | `/kit:test-plan` runs the three moves first, writes the rows back to the spec, then builds the matrix. |
| You wonder if you may skip a category | Yes, with a stated reason. The kit records the reason beside the set. |
| You cannot find where the rows went | They move from the brief to the spec's edge cases, then to the test matrix. Search for the situation text. |
| The row count is under 5 | The "invert each promise" move was likely skipped. Ask the kit to run it. |
| The kit dropped a row you liked | An upstream row is never dropped silently. Ask for the one-line reason it carries. |

A scenario earns its place by changing a later step. If a row never becomes a spec edge case, a test row or a gate, ask the kit whether it belongs in the set.

## Related

- [grill.md](grill.md): where the must-NOT-happen rows are written.
- [spine.md](spine.md): the steps that carry scenarios downhill.
- [gauntlet.md](gauntlet.md): how scenarios become probe cards for a cold reader.
- [`docs/patterns/scenario-generation.md`](../patterns/scenario-generation.md): the full method.
