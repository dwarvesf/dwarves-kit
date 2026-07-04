# Spec: Stale-ADR inversion in the generic review surfaces

Generated: 2026-07-04
Status: VALIDATED
Lane: normal (advisory wording only, no new agent/gate/severity machinery, three
files touched; classified `normal` by `lib/lane-classify.sh`).

## Problem

Every surface that tells a reviewer to read a spec/ADR/intent doc has a one-sided
failure mode: a doc can be used to blanket-mute a finding ("the spec says X, so this
is fine") without ever checking whether the code still matches what the doc claims.
shadcn/improve's playbook names the fix directly: "a stale ADR is itself a finding...
don't use the doc to suppress it" (`research/2026-07-04-pxpipe-plannotator-improve-absorption.md`
§3, A4, in `ops-toolkit`). None of the kit's three generic review surfaces
(`agents/advisor.md`, `commands/review.md`, `commands/review-team.md`) state the
two-sided rule today.

## Solution

Inject one identical rule block, verbatim (copy-paste, no paraphrase drift), into
each of the 3 surfaces, at the point each surface already reads intent docs:

1. `agents/advisor.md` -- new bullet in the critique-mode (P5) "look for" list.
2. `commands/review.md` -- new bullet inside the Architecture checklist, right after
   the existing "Does this match the spec ...?" line it completes.
3. `commands/review-team.md` -- injected INTO the Architecture-lens dispatch prompt's
   fenced text block (Reviewer 2), because a dispatched reviewer does not inherit the
   parent session's rules; the rule must ride inside the literal prompt text.

Rule text (identical in all 3, `file:line` at time of writing):

> **Stale-ADR inversion.** Behavior that matches what a spec/ADR/intent doc claims is
> BY DESIGN, not a finding, even if it looks surprising at first glance. Code that has
> DRIFTED from what a spec/ADR/intent doc claims IS itself a finding: report the drift
> naming the doc's line and the code's line. A doc can never blanket-mute observed
> behavior. Emit a drift finding with a `stale-adr:` finding-key prefix (e.g.
> `stale-adr: <doc>:<line> claims X, <code>:<line> does Y`) so it reads as this lens
> type, distinct from other findings.

The `stale-adr:` finding-key prefix is the naming convention advisor P6 needs: a
later grep-based pre-flag check and a later observatory adapter (both downstream
sub-goals of the `gate-review-absorptions` mega-goal) can select this lens type by
prefix without any new schema.

**Not changed:** no new agent, no new gate, no new severity tier, no change to what a
reviewer MUST do beyond this one advisory lens. The specialized domain reviewers
(security/api/frontend/infra/performance) are out of scope; they inherit any parent
rule only via `review-team.md`'s dispatch template, which this spec does not touch
for them.

## Design

`obvious: not design-bearing`. No new component, no schema, no external integration,
no irreversible choice, and exactly one viable approach (state the same rule text at
the 3 points reviewers already read intent docs). The before/after is fully captured
by the rule-text block above, so a diagram would restate it without adding
information.

## Acceptance criteria

1. The identical rule text (byte-for-byte) appears in `agents/advisor.md`,
   `commands/review.md`, and `commands/review-team.md`.
2. A seeded code-vs-ADR contradiction, run through the rule, is reported as a
   `stale-adr:`-prefixed finding naming both the doc line and the code line.
3. A seeded by-design match (code that matches its doc) is NOT flagged when run
   through the same rule.
4. No new agent, gate, or severity machinery was added.

## Verification

Fixture capture (real primary flow, simulated dispatch per the sub-goal contract):
`docs/verification/spec-143-stale-adr-inversion.md`. Includes a positive control
(the drift case, RED without the rule / flagged with it) and a negative control (the
by-design case, silent either way it should stay silent -- proving the rule does not
over-fire).
