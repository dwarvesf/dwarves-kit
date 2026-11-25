// `gate-ledger.sh inherit <rid> full --from <parent>` (lib/gate/gate-ledger.sh:inherit, :1043), a decision.
//
// Facts per spec-level phase (think, design, design-critique, spec, validate, design-record, test-plan: the
// INHERITABLE set the kit-root full lane requires): the LAST state of that phase's GATE rows in the parent ledger
// (none, ran with a well-formed timestamp, ranBadTs, skipped, rejected, override, inherited = an override the parent
// itself inherited), and whether the child already holds this parent's inherited line for it (`had`). Run facts: the
// lane is full, the parent rid differs from the child, the parent ledger exists, and the child holds an inherited
// line from a DIFFERENT parent for one of these phases (`conflict`).
// Result: the exit code (0, 1, 64, 65) and, per phase, whether a `GATE | <phase> | override | inherited from ...`
// line is written.
import {bool, fun, oneOf, when} from 'gdp-wired'

export const PHASES = ['think', 'design', 'design-critique', 'spec', 'validate', 'design-record', 'test-plan'] as const
export const STATES = ['none', 'ran', 'ranBadTs', 'skipped', 'rejected', 'override', 'inherited'] as const
export const PState = oneOf(...STATES)
const key = (i: number) => `p${i}`

export type Variant = 'shipped' | 'any-ran' | 'mix-parents' | 'rewrites'
export const VARIANTS: Variant[] = ['any-ran', 'mix-parents', 'rewrites']

export function inherit(variant: Variant = 'shipped') {
  const inputs: Record<string, any> = {full: bool, distinct: bool, parentLedger: bool, conflict: bool}
  PHASES.forEach((_, i) => { inputs[key(i)] = PState; inputs[`had${i}`] = bool })
  return fun(variant === 'shipped' ? 'inherit' : `inherit/${variant}`)
    .inputs(inputs)
    .returns((e: any) => {
      const ran = PHASES.map((_, i) => e[key(i)].is('ran'))
      const allRan = variant === 'any-ran' ? ran.reduce((a, b) => a.or(b)) : ran.reduce((a, b) => a.and(b))
      const usage = e.full.not().or(e.distinct.not())
      const judged = e.parentLedger.and(allRan)
      const conflict = variant === 'mix-parents' ? e.conflict.and(e.conflict.not()) : e.conflict
      const writes = usage.not().and(judged).and(conflict.not())
      const out: Record<string, any> = {
        rc: when(usage, 64, when(judged.not(), 1, when(conflict, 65, 0))),
      }
      PHASES.forEach((_, i) => { out[`w${i}`] = writes.and(variant === 'rewrites' ? e[`had${i}`].or(e[`had${i}`].not()) : e[`had${i}`].not()) })
      return out
    })
}

export function laws(f: ReturnType<typeof inherit>) {
  const anyWrite = (o: any) => PHASES.map((_, i) => o[`w${i}`]).reduce((a: any, b: any) => a.or(b))
  return [
    f.law('inherit writes only when every spec-level phase\'s last parent state is ran', () => [],
      (o: any, e: any) => anyWrite(o).implies(PHASES.map((_, i) => e[key(i)].is('ran')).reduce((a: any, b: any) => a.and(b)))),
    f.law('a parent whose phase it inherited itself is refused, nothing written', (e: any) => [e.p4.is('inherited')],
      (o: any) => anyWrite(o).not().and(o.rc.eq(0).not())),
    f.law('a child that inherited from another parent is refused with 65, nothing written',
      (e: any) => [e.full, e.distinct, e.parentLedger, e.conflict, ...PHASES.map((_, i) => e[key(i)].is('ran'))],
      (o: any) => o.rc.eq(65).and(anyWrite(o).not())),
    f.law('a ran line with a malformed timestamp is not evidence', (e: any) => [e.p0.is('ranBadTs')], (o: any) => anyWrite(o).not()),
    f.law('re-running the same call writes no phase twice', () => [],
      (o: any, e: any) => PHASES.map((_, i) => e[`had${i}`].implies(o[`w${i}`].not())).reduce((a: any, b: any) => a.and(b))),
    f.law('inherit serves the full lane only', (e: any) => [e.full.not()], (o: any) => o.rc.eq(64).and(anyWrite(o).not())),
    f.law('no host-local parent ledger means a refusal', (e: any) => [e.full, e.distinct, e.parentLedger.not()], (o: any) => o.rc.eq(1)),
  ]
}
