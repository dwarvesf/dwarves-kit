// context-hints (hooks/context-hints.sh, UserPromptSubmit): the temporal line, as a gdp-wired rule. Always exits 0.
//
// State: <state dir>/<session>.json = {start, last}, reloaded on every prompt (:68-82, the `temporal` jq def :105-134).
//   CONTEXT_HINTS_TEMPORAL=0      -> no line, no write
//   no state file                 -> start = last = now; no line (elapsed < 1)
//   else elapsed = now - start, idle = now - last; a line when elapsed >= 1, plus the cache-hygiene nudge past 6 h
//   (elapsed > 21600); write {start, last: now}.
// (A state file that is not an object, or bad numbers, are the crash shapes; the bridge keeps to well-formed state.)
import {bool, nat, rule, when} from 'gdp-wired'

export type Variant = 'shipped' | 'restarts-clock' | 'line-on-first'
export const VARIANTS: Variant[] = ['restarts-clock', 'line-on-first']

export function contextHints(v: Variant = 'shipped') {
  return rule(v === 'shipped' ? 'context-hints' : `context-hints/${v}`)
    .params({off: bool})
    .inputs({now: nat})
    .state({has: bool.from(false), start: 0, last: 0, line: bool.from(false), nudge: bool.from(false)})
    .flags(({now, has, start, off}) => {
      const s = when(has, start, now)
      const elapsed = now.minus(s)
      return {on: off.not(), shows: off.not().and(v === 'line-on-first' ? elapsed.atLeast(0) : elapsed.atLeast(1)), long: elapsed.gt(21600)}
    })
    .step(({now, has, start, last, on, shows, long}) => ({
      has: has.or(on),
      start: when(on, when(has, v === 'restarts-clock' ? now : start, now), start),
      last: when(on, now, last),
      line: shows,
      nudge: shows.and(long),
    }))
}
export const make = contextHints

export function laws(r: ReturnType<typeof contextHints>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('the first prompt of a session adds nothing', (b, a) => a.line.not(), (b) => b.has.not()),
      r.stepLaw('the session start never moves once recorded', (b, a) => a.start.eq(b.start), (b) => b.has),
      r.stepLaw('every prompt records itself as the last one', (b, a) => a.last.eq(b.now), (b) => b.off.not()),
      r.stepLaw('with the temporal line off nothing is shown or written', (b, a) => a.line.not().and(a.start.eq(b.start)).and(a.last.eq(b.last)), (b) => b.off),
      r.stepLaw('the hygiene nudge comes only past six hours', (b, a) => a.nudge.implies(b.now.minus(b.start).gt(21600).and(b.has))),
    ],
  }
}
