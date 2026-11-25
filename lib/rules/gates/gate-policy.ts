// The [gate] on/off reader (lib/gate/gate-policy.sh:enabled), as a gdp-wired decision.
//
// Facts: whether the key is one of the seven known keys, whether it defaults on (DEFAULT_ON), the value the
// operator overlay and the kit-root kit.toml give it (kit-config.sh:kit_config_get with the project layer out of
// the picture: operator, else kit root, else the code default), the project .kit.toml value (`pv`), whether the
// project value is read at a base rev (`--at`), and whether the working-tree .kit.toml is tracked and clean.
// The result is `on` (exit 0) or off (exit 1). Callers (ship-rules.sh:ship_rules_switch_on) read only exit 1 as off.
import {bool, fun, oneOf} from 'gdp-wired'

export const VALUES = ['absent', 'true', 'false', 'other'] as const
export const Value = oneOf(...VALUES)

export type Variant = 'shipped' | 'dirty-false-applies' | 'true-gated' | 'unknown-off'
export const VARIANTS: Variant[] = ['dirty-false-applies', 'true-gated', 'unknown-off']

export function gatePolicy(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'gate-policy' : `gate-policy/${variant}`)
    .inputs({known: bool, defOn: bool, op: Value, root: Value, pv: Value, at: bool, clean: bool})
    .returns(({known, defOn, op, root, pv, at, clean}) => {
      // `rest`: operator, else kit root, else the default; only a literal true counts.
      const restIsTrue = op.is('true').or(op.is('absent').and(root.is('true'))).or(op.is('absent').and(root.is('absent')).and(defOn))
      const committed = variant === 'dirty-false-applies' ? at.or(at.not()) : at.or(clean)
      const pvTrue = variant === 'true-gated' ? pv.is('true').and(committed) : pv.is('true')
      const off = pv.is('false').and(committed)
      const unknownOn = variant === 'unknown-off' ? known.and(known.not()) : known.not()
      return {on: unknownOn.or(known.and(pvTrue.or(off.not().and(pvTrue.not()).and(restIsTrue))))}
    })
}

export function laws(f: ReturnType<typeof gatePolicy>) {
  return [
    f.law('an unknown key is on', (e) => [e.known.not()], (o) => o.on),
    f.law('a project true turns a gate on whether or not .kit.toml is committed', (e) => [e.pv.is('true')], (o) => o.on),
    f.law('an uncommitted or edited project false never turns off a gate the operator turned on',
      (e) => [e.pv.is('false'), e.at.not(), e.clean.not(), e.op.is('true')], (o) => o.on),
    f.law('a committed project false turns the gate off', (e) => [e.known, e.pv.is('false'), e.clean], (o) => o.on.not()),
    f.law('a project false read at the merge base turns the gate off', (e) => [e.known, e.pv.is('false'), e.at], (o) => o.on.not()),
    f.law('a known gate is on only when some layer says a literal true',
      (e) => [e.known], (o, e) => o.on.implies(e.pv.is('true').or(e.op.is('true')).or(e.op.is('absent').and(e.root.is('true')))
        .or(e.op.is('absent').and(e.root.is('absent')).and(e.defOn)))),
    f.law('the operator overlay wins over the kit root', (e) => [e.known, e.pv.is('absent'), e.op.is('absent').not()],
      (o, e) => o.on.implies(e.op.is('true')).and(e.op.is('true').implies(o.on))),
  ]
}
