// anchor-root (hooks/anchor-root.sh, the wrapper every wired hook but secrets-guard runs through) as a gdp-wired
// decision: does the hook run, and with what exit code.
//
//   :22-25  safety-gate, secrets-guard, ship-gate, spec-drift-guard, commit-format, anti-rationalization: always run.
//           Any other hook: lib/config/hook-module.sh off <hook> exits 0 (its module resolves to false: project
//           .kit.toml, then the operator kit.toml, then the kit root, then the table default, opt-in = off) -> exit 0.
//   :30-33  the hook runs under an explicit bash with exec, so its exit code (2 = block) passes through untouched.
import {bool, fun, oneOf} from 'gdp-wired'

export const Kind = oneOf('spine', 'module', 'unlisted')
export type Variant = 'shipped' | 'spine-toggleable' | 'swallows-exit'
export const VARIANTS: Variant[] = ['spine-toggleable', 'swallows-exit']

export function anchorRoot(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'anchor-root' : `anchor-root/${v}`)
    .inputs({kind: Kind, moduleOff: bool, hookBlocks: bool})
    .assume(({kind, moduleOff}) => kind.is('unlisted').implies(moduleOff.not()))  // hook-module.sh: an unlisted hook is never off
    .returns(({kind, moduleOff, hookBlocks}) => {
      const skipped = v === 'spine-toggleable' ? moduleOff : kind.is('module').and(moduleOff)
      const runs = skipped.not()
      return {runs, block: runs.and(hookBlocks).and(v === 'swallows-exit' ? kind.is('spine').not() : runs)}
    })
}
export const make = anchorRoot

export function laws(f: ReturnType<typeof anchorRoot>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a spine hook is never skipped, whatever the module config', (e) => [e.kind.is('spine')], (o) => o.runs),
      f.law('an opt-in hook is silent until its module is enabled', (e) => [e.kind.is('module'), e.moduleOff], (o) => o.runs.not().and(o.block.not())),
      f.law("a hook that runs keeps its block", (e) => [e.hookBlocks], (o, e) => o.runs.implies(o.block)),
      f.law('the wrapper never blocks on its own', () => [], (o, e) => o.block.implies(e.hookBlocks)),
    ],
  }
}
