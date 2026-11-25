// The star-tap nudge (lib/gate/quiz-gate.sh): `tap` decides whether to print the nudge, `respond` logs the
// human's choice. Both are advisory: neither ever blocks a merge (tap always exits 0).
//
// tap facts: the PR kind (--pr-kind, default gate) and the significance classifier's verdict (tap, log,
// not-significant, or nothing when the classifier fails). respond facts: the response word.
import {fun, oneOf} from 'gdp-wired'

export const KINDS = ['gate', 'gatedFinal', 'routine'] as const
export const SIG = ['tap', 'log', 'notSignificant', 'nothing'] as const
export const RESPONSES = ['engage', 'defer', 'accept', 'wave', 'other'] as const
export const Kind = oneOf(...KINDS)
export const Sig = oneOf(...SIG)
export const Response = oneOf(...RESPONSES)

export type Variant = 'shipped' | 'nudge-on-log' | 'any-pr'
export const VARIANTS: Variant[] = ['nudge-on-log', 'any-pr']

export function quizTap(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'quiz-tap' : `quiz-tap/${variant}`)
    .inputs({kind: Kind, verdict: Sig})
    .returns(({kind, verdict}) => {
      const gatePr = variant === 'any-pr' ? kind.is('routine').or(kind.is('routine').not()) : kind.is('gate').or(kind.is('gatedFinal'))
      const tapped = variant === 'nudge-on-log' ? verdict.is('tap').or(verdict.is('log')) : verdict.is('tap')
      return {nudge: gatePr.and(tapped), exit0: kind.is('gate').or(kind.is('gate').not())}
    })
}

export function tapLaws(f: ReturnType<typeof quizTap>) {
  return [
    f.law('a routine (non-gate) PR is never nudged', (e) => [e.kind.is('routine')], (o) => o.nudge.not()),
    f.law('only the classifier\'s tap verdict nudges (log and not-significant never do)', (e) => [e.verdict.is('tap').not()], (o) => o.nudge.not()),
    f.law('a tap verdict on a gate or gated-final PR nudges', (e) => [e.verdict.is('tap'), e.kind.is('routine').not()], (o) => o.nudge),
    f.law('the nudge never blocks: tap always exits 0', () => [], (o) => o.exit0),
  ]
}

export function quizRespond() {
  return fun('quiz-respond').inputs({response: Response})
    .returns(({response}) => ({logged: response.is('other').not(), asAccept: response.is('accept').or(response.is('wave'))}))
}
export function respondLaws(f: ReturnType<typeof quizRespond>) {
  return [
    f.law('every engage, defer or accept response is logged to the debt ledger', (e) => [e.response.is('other').not()], (o) => o.logged),
    f.law('the legacy word wave is logged as accept', (e) => [e.response.is('wave')], (o) => o.asAccept),
    f.law('an unknown response is refused and logs nothing', (e) => [e.response.is('other')], (o) => o.logged.not()),
  ]
}
