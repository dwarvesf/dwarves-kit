// Is the module that owns a hook switched off? (lib/config/hook-module.sh, one awk pass, lines 33-55)
//
// The bash: the hook's module is the first modules.tsv row whose hooks column names it (default core|opt-in);
// spine or no row -> never off. Then [modules].<module> across the non-empty files project, operator, kit-root:
// in each layer the first line `<module>=` (blanks, quotes and comments stripped) whose value is literally true or
// false is that layer's value; any other value is skipped. The highest layer with a value decides; with none the
// table default decides (core on, opt-in off). Exit 0 ("off") only when the answer is false.
//
// kit_config_get (lib/config/kit-config.sh) is the other reader of the same key: per layer it takes the FIRST line
// of the key (any non-empty value, `true`, `yes` or `0`) and the first layer with one wins. The module docs promise
// the two agree (tests/test-anchor-module-gate.sh "pins the precedence against kit_config_get"); hook-module.sh's own
// header names the two differences (a non-boolean value falls through). Each layer here carries its first two lines
// of the key, so both readers can be computed from the same file.
import {fun, oneOf, when} from 'gdp-wired'

export const VALS = ['absent', 'true', 'false', 'other'] as const
export const KINDS = ['module', 'spine', 'unknown'] as const
const Val = oneOf(...VALS)

export type Variant = 'shipped' | 'first-line-decides' | 'opt-in-default-on' | 'kit-root-wins'
export const VARIANTS: Variant[] = ['first-line-decides', 'opt-in-default-on', 'kit-root-wins']

export function moduleSwitch(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'module-switch' : `module-switch/${variant}`)
    .inputs({kind: oneOf(...KINDS), core: oneOf('core', 'opt-in'),
      p1: Val, p2: Val, o1: Val, o2: Val, r1: Val, r2: Val})
    .returns(({kind, core, p1, p2, o1, o2, r1, r2}) => {
      const isBool = (v: typeof p1) => v.is('true').or(v.is('false'))
      // A layer's value: 1 true, 2 false, 0 none.
      const layer = (a: typeof p1, b: typeof p1) => variant === 'first-line-decides'
        ? when(a.is('true'), 1, when(a.is('absent').not(), 2, when(b.is('true'), 1, when(b.is('absent').not(), 2, 0))))
        : when(a.is('true'), 1, when(a.is('false'), 2, when(b.is('true'), 1, when(b.is('false'), 2, 0))))
      const P = layer(p1, p2), O = layer(o1, o2), R = layer(r1, r2)
      const def = variant === 'opt-in-default-on' ? 1 : when(core.is('core'), 1, 2)
      const chosen = variant === 'kit-root-wins'
        ? when(R.gt(0), R, when(O.gt(0), O, when(P.gt(0), P, def)))
        : when(P.gt(0), P, when(O.gt(0), O, when(R.gt(0), R, def)))
      // kit_config_get's view of the same key: the first line per layer, the first layer with one.
      const first = (a: typeof p1, b: typeof p1) => when(a.is('absent').not(), when(a.is('true'), 1, when(a.is('false'), 2, 3)),
        when(b.is('absent').not(), when(b.is('true'), 1, when(b.is('false'), 2, 3)), 0))
      const kP = first(p1, p2), kO = first(o1, o2), kR = first(r1, r2)
      void isBool
      return {
        off: kind.is('module').and(chosen.eq(2)),
        decided: chosen,
        kcg: when(kP.gt(0), kP, when(kO.gt(0), kO, kR)),
      }
    })
}

export function laws(f: ReturnType<typeof moduleSwitch>) {
  const lit = (v: {is: (x: string) => any}) => v.is('true').or(v.is('false')).or(v.is('absent'))
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a spine hook is never switched off', ({kind}) => [kind.is('spine')], (o) => o.off.not()),
      f.law('a hook the table does not list is never switched off', ({kind}) => [kind.is('unknown')], (o) => o.off.not()),
      f.law('an opt-in module is off unless some layer sets it literally true',
        ({kind, core, p1, p2, o1, o2, r1, r2}) => [kind.is('module'), core.is('opt-in'),
          p1.is('true').not(), p2.is('true').not(), o1.is('true').not(), o2.is('true').not(), r1.is('true').not(), r2.is('true').not()],
        (o) => o.off),
      f.law('a core module is on unless some layer sets it literally false',
        ({core, p1, p2, o1, o2, r1, r2}) => [core.is('core'),
          p1.is('false').not(), p2.is('false').not(), o1.is('false').not(), o2.is('false').not(), r1.is('false').not(), r2.is('false').not()],
        (o) => o.off.not()),
      f.law('a literal project value decides over the operator and kit-root files',
        ({kind, p1}) => [kind.is('module'), p1.is('false')], (o) => o.off),
      f.law('a non-boolean value never switches a module off on its own',
        ({kind, core, p1, p2, o1, o2, r1, r2}) => [kind.is('module'), core.is('core'),
          p1.is('false').not(), p2.is('false').not(), o1.is('false').not(), o2.is('false').not(), r1.is('false').not(), r2.is('false').not()],
        (o) => o.off.not()),
      // The agreement the docs promise, over files whose every line of the key is a literal true/false.
      f.law('the hook gate and kit_config_get read the same layer value when every line is a literal boolean',
        ({p1, p2, o1, o2, r1, r2}) => [lit(p1), lit(p2), lit(o1), lit(o2), lit(r1), lit(r2)],
        (o) => o.kcg.gt(0).implies(o.kcg.eq(o.decided))),
    ],
  }
}
