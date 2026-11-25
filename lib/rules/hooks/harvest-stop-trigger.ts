// The harvest's per-turn counter (hooks/harvest.sh --stop-trigger :460-484, opt-in, not wired in hooks.json by
// default) as a gdp-wired rule. Each request is one Stop.
//
//   :461     HARVEST_STOP_TRIGGER not truthy               -> nothing (no count)
//   :463     n = HARVEST_STOP_N (default 10, at least 1)
//   :471-473 cur = the stored count + 1, written back (turns/<session>)
//   :474-477 cur mod n != 0                                 -> skip; else fire (a detached harvest)
// The rule keeps k = stored count mod n (the file keeps the raw count; for a fixed n the two step alike), so the
// state is any k < n reloaded from disk.
import {bool, nat, rule, when} from 'gdp-wired'

export type Variant = 'shipped' | 'off-by-one' | 'no-reset'
export const VARIANTS: Variant[] = ['off-by-one', 'no-reset']

export function harvestStopTrigger(v: Variant = 'shipped') {
  return rule(v === 'shipped' ? 'harvest-stop-trigger' : `harvest-stop-trigger/${v}`)
    .params({on: bool, n: nat})
    .pre(({n}) => n.atLeast(1))
    .state({k: 0, fired: bool.from(false)})
    .flags(({on, n, k}) => ({fire: on.and(v === 'off-by-one' ? k.eq(n) : k.plus(1).eq(n))}))
    .step(({on, n, k, fire}) => ({
      k: when(on, when(fire, v === 'no-reset' ? k.plus(1) : 0, k.plus(1)), k),
      fired: fire,
    }))
}
export const make = harvestStopTrigger

export function laws(r: ReturnType<typeof harvestStopTrigger>) {
  return {
    laws: [r.law('the count stays below N', ({k, n}) => k.lt(n))],
    stepLaws: [
      r.stepLaw('an opt-in trigger is silent until enabled', (b, a) => a.fired.not().and(a.k.eq(b.k)), (b) => b.on.not()),
      r.stepLaw('it fires on the Nth turn since the last fire', (b, a) => a.fired, (b) => b.on.and(b.k.plus(1).eq(b.n))),
      r.stepLaw('it fires on no other turn', (b, a) => a.fired.implies(b.k.plus(1).eq(b.n))),
      r.stepLaw('a fire starts the count again', (b, a) => a.k.eq(0), (b) => b.on.and(b.k.plus(1).eq(b.n))),
    ],
  }
}
