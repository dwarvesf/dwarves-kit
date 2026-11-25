// The understanding-gate verdict, lib/classify/significance-classify.sh `classify` (classify_core):
//   significance HIGH when lane-classify.sh `risk` says full, or a design-bearing or new-public-surface phrase
//   fires; worthiness HIGH when at least SIGNIFICANCE_WORTHINESS_MIN distinct worthiness triggers fire (five text
//   triggers plus a non-empty impl-notes file); the verdict taps ONLY high x high, logs high significance with low
//   worthiness, and is not-significant otherwise (the header's anti-fatigue matrix).
// `n` is the number of distinct worthiness triggers that fired (0..6), `min` the knob.
import {bool, fun, nat, when} from 'gdp-wired'
import {pick} from './util.ts'

export const VERDICTS = ['tap', 'log', 'not-significant'] as const
export type Variant = 'shipped' | 'taps-on-worth-alone' | 'knob-inverted'
export const VARIANTS: Variant[] = ['taps-on-worth-alone', 'knob-inverted']

export function significance(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'significance' : `significance/${variant}`)
    .inputs({riskFull: bool, design: bool, surface: bool, n: nat, min: nat})
    .assume(e => e.n.atMost(6))
    .returns(e => {
      const sig = e.riskFull.or(e.design).or(e.surface)
      const worth = variant === 'knob-inverted' ? e.n.atMost(e.min) : e.n.atLeast(e.min)
      const v = variant === 'taps-on-worth-alone'
        ? when(worth, 0, when(sig, 1, 2))
        : when(sig.not(), 2, when(worth, 0, 1))
      return {verdict: pick(VERDICTS, v)}
    })
}

export function laws(f: ReturnType<typeof significance>) {
  const sig = (e: any) => e.riskFull.or(e.design).or(e.surface)
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('the gate taps only when significance and worthiness are both high', () => [],
        (o, e) => o.verdict.is('tap').implies(sig(e).and(e.n.atLeast(e.min)))),
      f.law('a change with no significance trigger is never tapped or logged', (e) => sig(e).not(),
        (o) => o.verdict.is('not-significant')),
      f.law('high significance with too few worthiness triggers is logged silently, never tapped', (e) => [sig(e), e.n.lt(e.min)],
        (o) => o.verdict.is('log')),
      f.law('a full-risk lane always makes the change significant', (e) => e.riskFull, (o) => o.verdict.is('not-significant').not()),
      f.relate('raising SIGNIFICANCE_WORTHINESS_MIN never adds a tap',
        (a, b) => [same(a.riskFull, b.riskFull), same(a.design, b.design), same(a.surface, b.surface), a.n.eq(b.n), a.min.atMost(b.min)],
        (x, y) => y.verdict.is('tap').implies(x.verdict.is('tap'))),
      f.relate('another worthiness trigger never turns a tap into a log',
        (a, b) => [same(a.riskFull, b.riskFull), same(a.design, b.design), same(a.surface, b.surface), a.n.atMost(b.n), a.min.eq(b.min)],
        (x, y) => x.verdict.is('tap').implies(y.verdict.is('tap'))),
    ],
  }
}
const same = (a: any, b: any) => a.implies(b).and(b.implies(a))
