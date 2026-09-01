# The scenario-generation pattern

One shared method for producing test SCENARIOS, the situations an artifact must
survive, used by every workflow beat that needs them (think, design, grill,
spec, test-plan, loop-engineering, gauntlet). A scenario is not a test case: a
scenario is a situation ("the session dies mid-execute"); test cases are its
projections into runnable checks. Scenarios are generated ONCE at the cheapest
altitude that can see them, then flow downhill; a beat never regenerates from
scratch what an earlier beat already named.

## The three generation moves (run all three, in this order)

1. **Journey walk.** Name the actor(s), walk their path step by step, and at
   each step ask "what does the actor need here, and what happens when it is
   missing?" Every step is a scenario seed. The gauntlet's J-matrix is this
   move with actor = new contributor; a feature spec's actor is the end user; a
   loop's actor is the operator driving it.
2. **Guarantee inversion.** List every promise the artifact makes (explicit
   acceptance criteria AND implicit ones: "merge does not deploy", "the loop
   halts", "no secret leaves the vault"). For each, ask "what makes this
   false?" Each answer is a failure-injection scenario. Implicit promises are
   where the blind spots live; spend most of the time here.
3. **Category sweep.** Check the set against the standard categories and fill
   holes deliberately or skip them with a stated reason:
   happy-path / boundary (empty, max, off-by-one, unicode) / failure-injection
   (dependency down, bad input, partial state) / recovery (interruption,
   resume, rollback) / adversarial (gaming the check, hostile input, the
   answer-key read) / concurrent (two actors, two sessions, a race).

Output shape, every time: a table `| # | Scenario | Category | Source move |`,
5-12 rows for a normal artifact. Fewer than 5 means move 2 was skipped; more
than ~12 at explore altitude means test cases are masquerading as scenarios,
collapse them.

## Where each beat fires and what flows downhill

| Altitude | Beat | Produces | Flows into |
|---|---|---|---|
| explore (`/kit:think`, `/kit:design`) | scenario sketch: 3-5 survival scenarios, majority from move 2 | situations only, no oracles | the Decision Brief |
| define (`/kit:grill` phase-0) | the done scenario + 2-3 must-NOT-happen scenarios | the negative space of Done= | the goal draft |
| contract (`/kit:spec`) | `## Edge Cases` + `## Failure modes` seeded FROM the sketch, extended by a full three-move pass | the reviewed scenario set (spec-validate critiques it) | the spec |
| verify design (`/kit:test-plan`) | the coverage matrix derived from scenarios + ACs; if the spec carries no scenario set, run the three moves FIRST, write them back, then derive | runnable cases with oracles | tests / gauntlet cards |
| define a loop (`skills/loop-engineering`) | the loop's own survival set (convergence, non-convergence, bad input, interrupted run, gamed metric) as a mandatory anatomy slot | the loop's spec + its tests | the new engine |

The downhill rule is the point of the wiring: the explore-time sketch is made
by the person/agent with the most context and the least sunk cost; every later
beat REFINES it (adds oracles, splits rows, prunes with a reason) instead of
starting blank at a more expensive altitude.

## Quality bar (what review checks)

- Every implicit guarantee named in the artifact's own prose has an inversion
  row or a stated skip.
- At least one recovery and one adversarial row exist, or their absence is
  argued, these are the two categories humans skip most.
- Each row names its actor. An actorless scenario ("the system fails") is a
  category, not a scenario; re-run move 1 on it.
- Rows carry NO oracles above the test-plan altitude. An explore-time oracle
  is premature precision that hardens a guess.

## Lineage

Move 1 generalizes the gauntlet's journey matrix (SPEC-227) and classic
user-journey mapping. Move 2 is fault-tree thinking scaled down (invert the
guarantee, not the gate). Move 3 is the category matrix the kit's test-design
standard and `/kit:test-plan` already enforce, applied earlier. The downhill
rule mirrors the kit's state-stores principle: nothing re-entered between
phases.
