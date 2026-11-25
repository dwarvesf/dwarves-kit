// The stored-state move check of a repo's own registry, lib/board/state_check.py `move_problem` (shared by
// `board state-check --staged` and any set-state wrapper): moving a stored value from `old` (none: no value yet)
// to `new` is refused when `new` is undeclared, when `new` is a legacy value, or, when the machine declares
// `transitions` and `old` is a declared state, when `new` is not among old's allowed targets. A legacy or
// undeclared `old` is grandfathered (no transition check).
// Under `ignore_case`, values are read case-folded (norm lowercases them) and classify() folds both sides.
// FIX: the transition lookup did not fold: `transitions.get(old)` and `new not in allowed` compared the lowercased
// value with the registry's own spelling, so a registry that writes `Open = ["Done"]` refused every declared
// move (variant 'case-sensitive-transitions'). It now folds like classify().
// Inputs: the kinds of old and new, whether the machine has transitions, whether new is listed for old (up to the
// machine's case rule), ignore_case, and whether the registry spells those names in lowercase.
import {bool, fun, oneOf, when} from 'gdp-wired'
import {pick} from './util.ts'

export type Variant = 'shipped' | 'case-sensitive-transitions' | 'checks-from-legacy' | 'accepts-legacy'
export const VARIANTS: Variant[] = ['case-sensitive-transitions', 'checks-from-legacy', 'accepts-legacy']

export function stateCheck(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'state-check' : `state-check/${variant}`)
    .inputs({oldKind: oneOf('none', 'declared', 'legacy', 'undeclared'), newKind: oneOf('declared', 'legacy', 'undeclared'),
      hasTrans: bool, listed: bool, ic: bool, regLower: bool})
    .returns(e => {
      const lookup = variant === 'case-sensitive-transitions' ? e.ic.not().or(e.regLower) : e.ic.or(e.ic.not())
      const checked = variant === 'checks-from-legacy' ? e.oldKind.is('none').not() : e.oldKind.is('declared')
      const badTrans = checked.and(e.hasTrans).and(e.listed.and(lookup).not())
      const legacy = variant === 'accepts-legacy' ? e.newKind.is('legacy').and(e.newKind.is('legacy').not()) : e.newKind.is('legacy')
      const why = when(e.newKind.is('undeclared'), 1, when(legacy, 2, when(badTrans, 3, 0)))
      return {why: pick(['ok', 'undeclared', 'legacy', 'transition'] as const, why)}
    })
}

export function laws(f: ReturnType<typeof stateCheck>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a newly written value is always a declared state', () => [], (o, e) => o.why.is('ok').implies(e.newKind.is('declared'))),
      f.law('a legacy value is refused when newly written', (e) => e.newKind.is('legacy'), (o) => o.why.is('ok').not()),
      f.law('a declared transition is never refused, whatever the case of the value or the registry',
        (e) => [e.newKind.is('declared'), e.oldKind.is('declared'), e.listed], (o) => o.why.is('ok')),
      f.law('a move from a declared state off its declared transitions is refused',
        (e) => [e.oldKind.is('declared'), e.hasTrans, e.listed.not()], (o) => o.why.is('ok').not()),
      f.law('without a transitions table any declared value is accepted', (e) => [e.hasTrans.not(), e.newKind.is('declared')], (o) => o.why.is('ok')),
      f.law('a legacy or undeclared old value is grandfathered: only the new value is checked',
        (e) => [e.oldKind.is('legacy').or(e.oldKind.is('undeclared')), e.newKind.is('declared')], (o) => o.why.is('ok')),
    ],
  }
}
