# The failure-policy vocabulary

Every judging node in the kit (a verifier, a reviewer, a retry loop) eventually decides one
of three things about what it just judged: keep going, stop and ask a human, or stop and
kill the line of work. Today each node names that decision in its own local words (`PASS`,
`FAIL:escalate`, `SHIP`, `DO NOT SHIP`, "ESCALATE to user"). This doc names the shared
concept underneath those words so the DECISION TYPE is comparable across nodes, without
replacing any node's own verdict grammar.

Absorbed from openclaw/acpx's pr-triage decision tree (`docs/research/2026-07-25-acpx-absorption.md`).
Fills PHILOSOPHY.md N5's stated gap: "failure semantics for mid-graph nodes unnamed."

## The three policies

| Policy | Means | Who acts |
|---|---|---|
| **continue** | The judged thing is fine as-is (or was made fine by an in-loop fix). Proceed to the next step. | Nobody; the loop keeps moving. |
| **escalate** | The judged thing needs a decision only a human can make well: architecture, risk, an ambiguous spec. The work is correct-shaped but the next step is a judgment call. | The human, at the next checkpoint. |
| **close** | The judged thing is wrong-shaped or unclear at a level no amount of retrying fixes: a task that doesn't match its spec, a PR that shouldn't exist, a line of work that should stop rather than be argued about. | Nobody decides it forward; it stops. A human can always reopen it, but reopening is a new judgment, not a resumption. |

`escalate` and `close` are easy to conflate because both stop the loop. The difference is
what happens next: `escalate` hands a live decision to a human ("which of these two designs
do you want"); `close` hands nothing forward ("this was never going to work, drop it"). A
verdict that asks "should I even continue this at all?" is `close`; one that asks "which way
should I continue?" is `escalate`.

## Mapping onto verdict grammars that already exist

This vocabulary is an interpretive layer, not a new grammar to enforce. Nothing below
renames an existing verdict string.

| Node | Existing verdict | Policy |
|---|---|---|
| `task-verifier` / `integration-verifier` (`agents/task-verifier.md`) | `PASS` | continue |
| `task-verifier` / `integration-verifier` | `FAIL:fixable`, resolved within the retry cap | continue |
| `task-verifier` / `integration-verifier` | `FAIL:fixable`, retry cap exhausted (`/kit:execute` 2d) | escalate |
| `task-verifier` / `integration-verifier` | `FAIL:escalate` reason is "requires a design decision" | escalate |
| `task-verifier` / `integration-verifier` | `FAIL:escalate` reason is "the spec itself may be wrong" | close |
| `/kit:review`, `/kit:review-team` (`## Verdict`) | `SHIP` | continue |
| `/kit:review`, `/kit:review-team` | `FIX THEN SHIP` | escalate (a human decides which findings to fix now vs defer) |
| `/kit:review`, `/kit:review-team` | `DO NOT SHIP` | escalate, or close if the finding is "this diff shouldn't exist" (wrong approach, not a fixable defect) |

## Root cause vs symptom is its own judged step, not a clause

A fix that resolves a symptom instead of the root cause looks like `continue` (the check
goes green) but is a `close`-shaped defect wearing a `continue` verdict: the underlying
problem is still there and will resurface. `/kit:review` Step 2a (`commands/review.md`)
makes "does this solve the root cause, not the symptom" its own judged item with its own
`root-cause:` finding-key, instead of a clause buried inside the Correctness checklist,
so it cannot be silently skipped when a reviewer is scanning for the usual suspects.
`/kit:debug`'s iron law (no fix without a recorded root cause) is the same principle
applied off-cycle, at diagnosis time instead of review time.

## Emitter and reader

The named policy lands in the gate ledger as an additive field on the existing SPEC-129
`OUTCOME` marker: `bash lib/gate/gate-ledger.sh outcome <rid> <phase> end caught=<bool> policy=<close|escalate|continue>`.
`policy=` is optional (omitting it is unchanged behavior; every existing reader stays
byte-identical per the additive-equivalence property `tests/test-gate-outcome.sh` pins).
`gate-ledger.sh outcome-read` reads it back. `lib/telemetry/lane-telemetry.sh report`
is the reader: it prints a failure-policy breakdown (close/escalate/continue counts) over
every run ledger that carries the field, and stays silent when no run does (no fake zeros).

`/kit:execute`'s Build-phase outcome call (Step 4, `commands/execute.md`) is the current
emitter: `policy=close` when a task-verifier `FAIL:escalate` named the spec itself as wrong
and the build stopped without a fix, `policy=escalate` when any task needed a human decision
and the build stopped or resumed on one, `policy=continue` otherwise.
