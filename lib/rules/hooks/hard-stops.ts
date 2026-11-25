// The four hard stops and the autonomy dial (docs/guides/autonomy.md, docs/guides/gates-and-proof.md) as a gdp-wired
// decision: does a triggered hard stop halt the run, at each autonomy position?
//
// The dial is prose only: no hook, command or lib reads a position (propose | low | high | max); the agent reads the
// operator's phrase. So the code-faithful composition takes the position as an input nothing reads:
//   safety-gate      halts on its trigger, always (safety-gate.ts; it reads no config)
//   push-to-main     halts on its trigger, always (safety-gate.ts names main/master; ship-gate owns the default branch)
//   anti-rationalization halts on its trigger only while [gate] understanding_gate is on (off by default) and only
//                    on a fresh Stop: the second Stop of a turn carries stop_hook_active and passes (anti-rationalization.ts)
//   verification pipeline halts at the fix cap (lib/rules/verify-loop.ts, run by bin/verify-loop)
import {bool, fun, oneOf} from 'gdp-wired'
import {iff} from './_kit.ts'

export const Position = oneOf('propose', 'low', 'high', 'max')
export const Stop = oneOf('safety', 'pushMain', 'antiRat', 'verify')
export type Variant = 'shipped' | 'max-waives'
export const VARIANTS: Variant[] = ['max-waives']

export function hardStops(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'hard-stops' : `hard-stops/${v}`)
    .inputs({position: Position, stop: Stop, triggered: bool, understandingGate: bool, continuing: bool})
    .returns(({position, stop, triggered, understandingGate, continuing}) => {
      const antiRat = understandingGate.and(continuing.not())
      const holds = stop.is('antiRat').not().or(antiRat)
      const waived = v === 'max-waives' ? position.is('max') : position.is('max').and(position.is('max').not())
      return {halts: triggered.and(holds).and(waived.not())}
    })
}
export const make = hardStops

export function laws(f: ReturnType<typeof hardStops>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.relate('no hard stop depends on the autonomy position',
        (a, b) => [a.stop.eq(b.stop), iff(a.triggered, b.triggered), iff(a.understandingGate, b.understandingGate), iff(a.continuing, b.continuing)],
        (x, y) => iff(x.halts, y.halts)),
      f.law('safety-gate and push-to-main halt at every position', (e) => [e.stop.is('safety').or(e.stop.is('pushMain')), e.triggered], (o) => o.halts),
      f.law('the verification pipeline halts at every position', (e) => [e.stop.is('verify'), e.triggered], (o) => o.halts),
    ],
    // Promised by gates-and-proof.md ("these four are never waived") and autonomy.md ("At every position the kit
    // still stops at the four hard stops"); refuted by the code: anti-rationalization is off unless the understanding
    // gate is on (documented, in the table), and passes the second Stop of a turn (not documented).
    refutedDecisions: [
      f.law('every triggered hard stop halts at every position', (e) => [e.triggered], (o) => o.halts),
      f.law('anti-rationalization halts at every position while the understanding gate is on',
        (e) => [e.stop.is('antiRat'), e.triggered, e.understandingGate], (o) => o.halts),
    ],
  }
}
