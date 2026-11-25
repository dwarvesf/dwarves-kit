// One rung-4 redteam round (lib/gate/redteam-gate.sh:cmd_round), as a gdp-wired decision.
//
// Facts: the verdict word (secure | findings | capped | other), the cost= argument (a plain decimal, missing, or
// malformed), and whether a rid was given. The result: whether the call is refused with exit 64 before writing,
// and, when accepted, what it writes: an OUTCOME end bracket with caught=<bool>, a TOKENS row carrying the cost,
// and a `GATE | redteam | ran` row (always `ran`; the verdict rides in the reason).
import {bool, fun, oneOf} from 'gdp-wired'

export const VERDICTS = ['secure', 'findings', 'capped', 'other'] as const
export const COSTS = ['decimal', 'missing', 'malformed'] as const
export const Verdict = oneOf(...VERDICTS)
export const Cost = oneOf(...COSTS)

export type Variant = 'shipped' | 'cost-optional' | 'capped-uncaught'
export const VARIANTS: Variant[] = ['cost-optional', 'capped-uncaught']

export function redteamRound(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'redteam-round' : `redteam-round/${variant}`)
    .inputs({verdict: Verdict, cost: Cost, rid: bool})
    .returns(({verdict, cost, rid}) => {
      const costOk = variant === 'cost-optional' ? cost.is('malformed').not() : cost.is('decimal')
      const accepted = rid.and(verdict.is('other').not()).and(costOk)
      return {
        accepted,
        caught: variant === 'capped-uncaught' ? verdict.is('findings') : verdict.is('secure').not(),
        gateRan: accepted,
      }
    })
}

export function laws(f: ReturnType<typeof redteamRound>) {
  return [
    f.law('a round with no plain-decimal cost is refused and writes nothing', (e) => [e.cost.is('decimal').not()], (o) => o.accepted.not()),
    f.law('a verdict outside secure, findings, capped is refused', (e) => [e.verdict.is('other')], (o) => o.accepted.not()),
    f.law('only a secure round is recorded caught=false', (e) => [e.verdict.is('other').not()], (o, e) => o.caught.not().implies(e.verdict.is('secure'))),
    f.law('the fail-closed cap counts as caught', (e) => [e.verdict.is('capped')], (o) => o.caught),
    f.law('every accepted round writes its GATE row', (e) => [e.rid, e.cost.is('decimal'), e.verdict.is('other').not()], (o) => o.accepted.and(o.gateRan)),
  ]
}

// A reviewer law the code refutes (FINDINGS.md): the round's GATE row is `ran` whatever the verdict.
export function refutedLaws(f: ReturnType<typeof redteamRound>) {
  return [f.law('a capped round (the fail-closed stop, never SECURE) never records the redteam gate as ran',
    (e) => [e.verdict.is('capped')], (o) => o.gateRan.not())]
}
