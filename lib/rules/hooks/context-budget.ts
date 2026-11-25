// context-budget (hooks/context-budget.sh, UserPromptSubmit) as gdp-wired rules. Advisory: it always exits 0.
//
// The band of one prompt (:98-109), compared in integers: below when ctx*100 < warn*window, strong when
// ctx*100 >= strong*window, warn between. The hook runs only when 0 < warn < strong <= 100 (:43-44).
// The per-session state file holds the last threshold fired (:111-115): absent (-1), 0 (warn) or 1 (strong). Below the
// warn line it is removed (:100-103); a band fires only when it is above the last one fired, and is then written.
// Encoded here as last = 0 (none), 1 (warn), 2 (strong); band = 0 below, 1 warn, 2 strong.
import {fun, nat, rule, when} from 'gdp-wired'

export function contextBand() {
  return fun('context-budget.band')
    .inputs({ctx: nat, window: nat, warn: nat, strong: nat})
    .assume(({warn, strong, window}) => warn.gt(0).and(warn.lt(strong)).and(strong.atMost(100)).and(window.gt(0)))
    .returns(({ctx, window, warn, strong}) => {
      const c = ctx.times(100)
      const below = c.lt(warn.mul(window))
      const top = c.atLeast(strong.mul(window))
      return {band: when(below, 0, when(top, 2, 1))}
    })
}

export type Variant = 'shipped' | 'no-clear' | 'fires-every-prompt'
export const VARIANTS: Variant[] = ['no-clear', 'fires-every-prompt']

export function contextBudget(v: Variant = 'shipped') {
  return rule(v === 'shipped' ? 'context-budget' : `context-budget/${v}`)
    .inputs({band: nat})
    .assume(({band}) => band.atMost(2))
    .state({last: 0, fired: 0})
    .flags(({band, last}) => ({fire: band.gt(0).and(v === 'fires-every-prompt' ? band.gt(0) : band.gt(last))}))
    .step(({band, last, fire}) => ({
      last: when(band.eq(0), v === 'no-clear' ? last : 0, when(fire, band, last)),
      fired: when(fire, band, 0),
    }))
}

export function laws(r: ReturnType<typeof contextBudget>) {
  return {
    laws: [r.law('the state file only ever holds none, warn or strong', ({last}) => last.atMost(2))],
    stepLaws: [
      r.stepLaw('below the warn line nothing fires and the state clears', (b, a) => a.fired.eq(0).and(a.last.eq(0)), (b) => b.band.eq(0)),
      r.stepLaw('a threshold fires only when it is above the last one fired', (b, a) => a.fired.gt(0).implies(b.band.gt(b.last))),
      r.stepLaw('a fire records the threshold that fired', (b, a) => a.last.eq(b.band), (b) => b.band.gt(b.last)),
      r.stepLaw('strong is never followed by a warn without a drop under the warn line', (b, a) => a.fired.eq(0), (b) => b.last.eq(2).and(b.band.gt(0))),
      r.stepsLaw('each threshold fires once until context drops under the warn line', 2,
        (first, last, reqs) => reqs[1].band.atMost(first.band).implies(last.fired.eq(0)), (b, j) => j === 0 ? b.band.gt(0) : undefined),
    ],
    decisions: [
      contextBand().law('strong means at least the strong share of the window', () => [], (o, e) => o.band.eq(2).implies(e.ctx.times(100).atLeast(e.strong.mul(e.window)))),
      contextBand().law('below means under the warn share of the window', () => [], (o, e) => o.band.eq(0).implies(e.ctx.times(100).lt(e.warn.mul(e.window)))),
    ],
  }
}
export const make = contextBudget
