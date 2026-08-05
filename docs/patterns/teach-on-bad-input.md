# The teach-on-bad-input pattern

A kit command given a bad input has exactly one good behavior, and it is neither
failing dry ("invalid input") nor proceeding silently on garbage. It is three
beats, in order, then stop:

1. **Name** what is wrong, concretely ("your seed card has no verification
   command").
2. **Teach** why it matters, in ONE line ("without it, failure is unmeasurable").
3. **Fix** by offering the concrete path: draft the missing piece, recommend the
   value, or route to the command that builds it.

Never lecture past beat 3. Never start the command's real work on a known-bad
input. If the user overrides ("run it anyway"), run it and RECORD the override
where the command's output lands, an informed override is their call; a silent
one is a defect.

Worked instantiation: `commands/gauntlet.md` "Bad input? Teach, then fix", a
per-input table of bad shapes, the one-line teach for each, and the graceful
floor (3+ missing inputs = "not ready", with the gap list framed as free
findings).

## The per-command tables (adopt incrementally; this section seeds the big five)

| Command | Bad input you may receive | Teach (the one line) | Then |
|---|---|---|---|
| `/kit:assign` | a bare title ("fix the thing") | a goal without an outcome and verification is unfinishable by construction | draft the scoped goal + recommended lane, show for approval |
| `/kit:assign` | five unrelated asks in one item | one row per outcome or nothing is ever "done" | split them; offer the batch as separate rows |
| `/kit:spec` | "spec it" with no decision brief and open design questions | a spec hardens decisions; hardening unmade decisions bakes in guesses | route to `/kit:think` or `/kit:design` first, name the open questions |
| `/kit:spec` | acceptance criteria that are vibes ("works well") | an unfalsifiable criterion cannot be verified, so the right arm has nothing to mirror | rewrite each as a checkable assertion with a command |
| `/kit:execute` | no VALIDATED spec (or several candidates) | execute builds the contract; an ambiguous contract builds an ambiguous system | resolve the active spec the standard way; refuse to auto-pick between two |
| `/kit:execute` | "skip the verifiers, I'm in a hurry" | unverified tasks convert build speed into debug time at the worst exchange rate | offer the tiny lane if it truly is tiny; otherwise run with verification |
| `/kit:debug` | a diagnosis instead of a symptom ("the cache is broken") | a wrong diagnosis anchors the search wrong; the symptom is the evidence | restate as symptom + reproduction; keep the diagnosis as hypothesis #1 |
| `/kit:debug` | "just patch it, root cause later" | later never comes, and the patch destroys the evidence | run Phase 0-3 fast; the iron law holds |
| `/kit:mega` | a flat list of unrelated tasks | sequencing unrelated work buys no safety, it only queues it | route to `/kit:dispatch` or plain goals (the triage ladder) |
| `/kit:mega` | a destination with no exit criterion | "done" without a destination-level check means the mega never closes honestly | ask for the ONE check that proves arrival; refuse to plan without it |
| `/kit:gauntlet` | (see the command's own table) | | |

Two meta-rules for authors adding a table to a command:

- The teach line explains the COST of the bad input, not the rule. "The hook
  will block you" teaches nothing; "failure becomes unmeasurable" does.
- The "Then" column must land on something runnable now: a draft to approve, a
  command to invoke, a value to accept. A dead-end teach is just a fancier
  error message.

## Lineage

Generalized from the gauntlet's input-validation section (first instance) and
the kit's existing refuse-with-a-path behaviors (test-plan-review-team refusing
a missing `## Test plan` with a pointer to `/kit:test-plan`; test-write refusing
a non-SOLID critique). The pattern names what those already did and sets the
three-beat ceiling so teaching never becomes lecturing.
