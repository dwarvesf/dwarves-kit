# Pattern: the review-fix loop

A multi-lens review is not a one-shot gate. A fix batch that resolves review
findings can introduce new ones, so the review must run again on the fix, until
the findings that matter stop appearing. This pattern names the three moves that
make an automatic review loop pay for itself instead of drowning the operator in
noise.

## Why this exists

A live money-path estate went through four ship rounds in one session. The
review of round two found four critical bugs that round two itself introduced:
an unfenced write on the exact key a prior round had fenced, and a rewrite that
laundered the rows the guard refused to commit. Neither per-PR review would have
seen them, because each bug lived in the interaction of two merged changes. The
review that caught them ran over the whole diff range, with several lenses, and
had to run again after each fix. That is the loop this pattern captures.

## The three moves

### Move 1: default-run, advisory-verdict

The review runs without being asked. It is a phase, not an operator question.
But it does not block: the verdict is advisory, the same as every other kit
phase (`AGENTS.md` enforcement boundary). Auto-RUN and auto-BLOCK are different.
The operator wants the review to happen every time; the operator does not want a
gate that forbids shipping until zero findings, because that never ships. So the
loop runs by default and reports; only the existing hard gates (safety, push-to-
main, verification pipeline) stop a ship.

### Move 2: convergence-ranking

A finding two or more lenses hit independently ranks first and is the loop's
stop-condition. A single-lens finding is advisory taste, demoted. The evidence:
in the session above, every multi-lens finding was a real defect, while most
single-lens findings were preference. Convergence is the cheapest available
signal for "this is real," so the loop trusts it: the merge step tags each
finding with the lens count, sorts by it, and the operator reads the convergent
ones first.

### Move 3: the bounded loop

After a fix batch resolves the convergent findings, re-run the review on the FIX
diff, in fresh context, and stop when no convergent finding remains OR a round
cap is hit. The cap prevents an infinite polish spiral: two rounds caught the
real regressions in practice, so two is the default ceiling. A round that still
surfaces a convergent money-path or security finding at the cap does not silently
pass: it is reported as an unresolved-at-cap verdict for the operator to judge.

## The scaling gate (the cost guard)

Running every lens at the top model tier on every change is expensive and
dilutes signal, which is why review stayed advisory-optional before this pattern.
Automation needs a gate keyed to risk, folded into the existing lane routing:

| Lane | Lens set | Loop | Design-time pass |
|---|---|---|---|
| full (auth, data-loss, money, migration, contract) | all domain lenses + advisor | up to 2 rounds | default |
| normal | the existing lighter review | 1 pass, no loop | opt-in |
| tiny | none | none | none |

The gate is the reason this is safe to default: the cost lands only where the
blast radius earns it. Lenses always dispatch as subagents (fresh context, off
the main thread), so a heavy review does not consume the operator's own context
window.

## Both arms, not one

Shift-left is real but partial. A design-time pass (over the brief and spec)
catches a different class than a code review: a missing invariant, an unhandled
failure mode, a threat surface, what breaks at ten times the load. Those are
cheap to fix in a spec and expensive in a PR, so the full lane runs them by
default. But a design pass cannot see a bug that lives in the interaction of two
future code changes. The loop therefore adds a design-time pass; it never
removes the post-build review. Every artifact still gets its two checks, per the
V-model.

## SDLC instances

- **Design-time pass:** the brief and spec, before build (`brief-reviewer`,
  `/kit:devs-team`, advisor over-suggest). Catches missing requirements.
- **Post-build loop:** the code review after each fix batch (`/kit:review-team`
  + advisor critique, convergence-ranked, looped). Catches regressions a fix
  batch introduces.
