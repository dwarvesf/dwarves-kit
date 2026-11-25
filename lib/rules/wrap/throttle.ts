// The run throttle the backlog-funnel hooks share (lib/reflect/hook-util.sh:hu_throttled, lines 31-46).
//   interval <= 0                      -> never throttled (return 1), the stamp untouched
//   the stamp exists and now - mtime < interval -> throttled (return 0), the stamp untouched
//   otherwise                          -> create or refresh the stamp (mtime = now), return 1 (run)
// Requests: call, or tick (time passes by dt seconds). State: whether the stamp exists, its age, and the last answer.
import {bool, nat, oneOf, rule, when} from 'gdp-wired'

export type Variant = 'shipped' | 'skip-refreshes' | 'off-still-throttles'
export const VARIANTS: Variant[] = ['skip-refreshes', 'off-still-throttles']

export function throttle(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'throttle' : `throttle/${variant}`)
    // on: the interval is > 0; interval: its value (read only when on)
    .params({on: bool, interval: nat})
    .inputs({op: oneOf('call', 'tick'), dt: nat})
    .state({stamp: bool.from(false), age: 0, ran: bool.from(false), skipped: bool.from(false)})
    .step(({on, interval, op, dt, stamp, age}) => {
      const call = op.is('call')
      const active = variant === 'off-still-throttles' ? on.or(on.not()) : on
      const skip = call.and(active).and(stamp).and(age.lt(interval))
      const runs = call.and(skip.not())
      const refresh = variant === 'skip-refreshes' ? call.and(active) : runs.and(on)
      return {
        stamp: stamp.or(refresh),
        age: when(refresh, 0, when(op.is('tick'), age.plus(dt), age)),
        ran: runs, skipped: skip,
      }
    })
}

export function laws(r: ReturnType<typeof throttle>) {
  return {
    laws: [
      r.law('a call is never both run and skipped', ({ran, skipped}) => ran.and(skipped).not()),
    ],
    stepLaws: [
      r.stepLaw('a run is skipped only when a stamp younger than the interval exists',
        (b, a) => a.skipped.implies(b.on.and(b.stamp).and(b.age.lt(b.interval)))),
      r.stepLaw('with the throttle off (interval <= 0) every call runs', (_b, a) => a.ran, (b) => b.op.is('call').and(b.on.not())),
      r.stepLaw('a skipped call does not refresh the stamp, so the window runs from the last real run',
        (b, a) => a.age.eq(b.age), (b) => b.op.is('call').and(b.on).and(b.stamp).and(b.age.lt(b.interval))),
      r.stepLaw('once the interval has passed since the last run, the next call runs',
        (_b, a) => a.ran.and(a.age.eq(0)), (b) => b.op.is('call').and(b.on).and(b.age.atLeast(b.interval))),
      r.stepLaw('a call that runs with the throttle on starts a new window', (_b, a) => a.stamp.and(a.age.eq(0)),
        (b) => b.op.is('call').and(b.on).and(b.stamp.not().or(b.age.atLeast(b.interval)))),
    ],
  }
}
