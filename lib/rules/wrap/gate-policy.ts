// Is a quality gate on? The [gate] key defaults (lib/gate/gate-policy.sh:enabled, lines 39-72).
//
// The bash: an unknown key -> on. rest = kit_config_get gate.<key> with the project file out of the picture
// (operator > kit-root > the code default: true for board_row_gate, fixture_identities, review_verdict, else false).
// pv = the project .kit.toml value (with --at <base>, the copy committed at <base>).
//   pv true                         -> on   (turning a gate on is never commit-gated)
//   pv false and --at               -> off  (a base copy is committed by definition)
//   pv false and the file is tracked and clean -> off
//   otherwise                       -> on iff rest is literally `true`
import {bool, fun, oneOf} from 'gdp-wired'

export const PVS = ['absent', 'true', 'false', 'other'] as const
export const RESTS = ['true', 'false', 'other'] as const

export type Variant = 'shipped' | 'dirty-false-applies' | 'unknown-key-off'
export const VARIANTS: Variant[] = ['dirty-false-applies', 'unknown-key-off']

export function gatePolicy(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'gate-policy' : `gate-policy/${variant}`)
    // rest: what operator > kit-root > the code default resolves to (computed by the bridge from the files, and
    // by the rule restDefault below when neither file sets the key).
    .inputs({known: bool, opSet: oneOf(...PVS), rootSet: oneOf(...PVS), defaultOn: bool,
      pv: oneOf(...PVS), at: bool, clean: bool})
    .returns(({known, opSet, rootSet, defaultOn, pv, at, clean}) => {
      // kit_config_get without the project layer: the first file with a non-empty value, else the code default.
      const restTrue = opSet.is('true').or(opSet.is('absent').and(rootSet.is('true').or(rootSet.is('absent').and(defaultOn))))
      const offByProject = pv.is('false').and(variant === 'dirty-false-applies' ? pv.is('false') : at.or(clean))
      const on = known.not().and(variant === 'unknown-key-off' ? known : known.not())
        .or(known.and(pv.is('true').or(offByProject.not().and(restTrue))))
      return {on, restTrue}
    })
}

export function laws(f: ReturnType<typeof gatePolicy>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('an unknown key reads as on, so a broken kit never drops a gate', ({known}) => [known.not()], (o) => o.on),
      f.law('a known gate is on only when some layer resolves it to a literal true',
        ({known}) => [known], (o, {pv}) => o.on.implies(pv.is('true').or(o.restTrue))),
      f.law('an opt-in gate is off when no file sets it',
        ({known, opSet, rootSet, pv, defaultOn}) => [known, defaultOn.not(), opSet.is('absent'), rootSet.is('absent'), pv.is('absent')],
        (o) => o.on.not()),
      f.law('a default-on gate is on when no file sets it',
        ({known, opSet, rootSet, pv, defaultOn}) => [known, defaultOn, opSet.is('absent'), rootSet.is('absent'), pv.is('absent')],
        (o) => o.on),
      f.law('turning a gate on in the project file is never commit-gated', ({known, pv}) => [known, pv.is('true')], (o) => o.on),
      f.law('an uncommitted or dirty project false never switches off a gate the operator turned on',
        ({known, pv, at, clean, opSet}) => [known, pv.is('false'), at.not(), clean.not(), opSet.is('true')], (o) => o.on),
      f.law('a project false committed at the base switches the gate off', ({known, pv, at}) => [known, pv.is('false'), at],
        (o) => o.on.not()),
    ],
  }
}
