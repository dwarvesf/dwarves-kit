// The harvest throttle (lib/reflect/hook-util.sh hu_throttled, used by hooks/backlog-stage.sh :239 and
// hooks/intake-sweep.sh :187; hooks/harvest.sh debounced :200-211 is the same machine) as a gdp-wired rule.
//
//   backlog-stage.sh :45  BACKLOG_STAGE_AUTO not truthy -> the hook exits before anything (opt-in, default off)
//   hu_throttled :36      an interval of 0 or less turns the throttle off (every run goes ahead)
//   hu_throttled :39-41   a stamp younger than the interval (now - mtime < interval) -> skip this run
//   hu_throttled :42      otherwise touch the stamp (mtime = now) and go ahead
// The stamp is a file on disk, so every law is proven from any state. A stamp dated in the future reads as young
// (now - mtime is negative), so it holds the throttle shut until now passes mtime + interval.
import {bool, nat, rule, when} from 'gdp-wired'

export type Variant = 'shipped' | 'stamps-when-skipped' | 'ignores-stamp'
export const VARIANTS: Variant[] = ['stamps-when-skipped', 'ignores-stamp']

export function throttle(v: Variant = 'shipped') {
  return rule(v === 'shipped' ? 'harvest-throttle' : `harvest-throttle/${v}`)
    .params({auto: bool, interval: nat})
    .inputs({now: nat})
    .state({has: bool.from(false), stamp: 0, ran: bool.from(false)})
    .flags(({auto, interval, now, has, stamp}) => {
      const young = has.and(stamp.gt(now).or(now.minus(stamp).lt(interval)))
      return {go: auto.and(interval.eq(0).or(v === 'ignores-stamp' ? has.or(has.not()) : young.not()))}
    })
    .step(({auto, interval, now, has, stamp, go}) => {
      const touch = auto.and(interval.gt(0)).and(v === 'stamps-when-skipped' ? auto : go)
      return {has: has.or(touch), stamp: when(touch, now, stamp), ran: go}
    })
}
export const make = throttle

export function laws(r: ReturnType<typeof throttle>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('an opt-in harvest is silent until enabled', (b, a) => a.ran.not().and(a.stamp.eq(b.stamp)), (b) => b.auto.not()),
      r.stepLaw('a run never follows a stamp younger than the interval',
        (b, a) => a.ran.implies(b.interval.eq(0).or(b.has.not()).or(b.stamp.atMost(b.now).and(b.now.minus(b.stamp).atLeast(b.interval))))),
      r.stepLaw('a skipped run leaves the stamp where it was', (b, a) => a.stamp.eq(b.stamp), (b) => b.auto.and(b.interval.gt(0)).and(b.has).and(b.now.minus(b.stamp).lt(b.interval))),
      r.stepLaw('a run restamps the clock', (b, a) => a.stamp.eq(b.now).and(a.has), (b) => b.auto.and(b.interval.gt(0)).and(b.has.not())),
      r.stepsLaw('two runs are never closer than the interval', 2,
        (first, last, reqs) => last.ran.implies(reqs[1].now.atLeast(first.now).and(reqs[1].now.minus(first.now).atLeast(first.interval))),
        (b, j) => j === 0 ? b.auto.and(b.interval.gt(0)).and(b.has.not()) : undefined),
    ],
  }
}
