// Which layer a config key's effective value comes from, three readers side by side:
//   kit_config_get       (lib/config/kit-config.sh:64-81)  project > operator > kit-root > caller default
//   kit_config_get_root  (lib/config/kit-config.sh:83-94)  operator > kit-root > caller default (project skipped)
//   config get/explain   (lib/config/config.sh:_resolve, 198-248) env > project > operator > kit-root > registry
//                         default, the project layer skipped for a root-only row; it promises to "mirror
//                         kit-config.sh's own precedence exactly".
// A layer counts when its file holds a non-empty value for [section] key. kit_config_get splits a dotted key at the
// LAST dot (`lane.normal.phases` is section `lane.normal`, key `phases`); config.sh split it at the FIRST dot before
// the fix (section `lane`, key `normal.phases`), so for a key with two dots it read no layer at all and reported the
// registry default while every real consumer read the file. That code is the kept variant 'first-dot-split'.
//
// Sources are coded as naturals: 0 default, 1 kit-root, 2 operator, 3 project, 4 env.
import {bool, fun, when} from 'gdp-wired'

export const SOURCES = ['default', 'kit-root', 'operator', 'project', 'env'] as const

export type Variant = 'shipped' | 'first-dot-split' | 'root-only-reads-project'
export const VARIANTS: Variant[] = ['first-dot-split', 'root-only-reads-project']

export function configPrecedence(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'config-precedence' : `config-precedence/${variant}`)
    .inputs({env: bool, proj: bool, op: bool, root: bool, rootOnly: bool, twoDots: bool})
    .returns(({env, proj, op, root, rootOnly, twoDots}) => {
      // What config.sh's own TOML reads can see for this key.
      const sees = variant === 'first-dot-split' ? twoDots.not() : twoDots.or(twoDots.not())
      const cProj = variant === 'root-only-reads-project' ? proj.and(sees) : proj.and(sees).and(rootOnly.not())
      const cOp = op.and(sees), cRoot = root.and(sees)
      return {
        get: when(proj, 3, when(op, 2, when(root, 1, 0))),
        getRoot: when(op, 2, when(root, 1, 0)),
        config: when(env, 4, when(cProj, 3, when(cOp, 2, when(cRoot, 1, 0)))),
      }
    })
}

export function laws(f: ReturnType<typeof configPrecedence>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('kit_config_get: a project value wins', ({proj}) => [proj], (o) => o.get.eq(3)),
      f.law('kit_config_get: the operator file wins over the kit root', ({proj, op}) => [proj.not(), op], (o) => o.get.eq(2)),
      f.law('kit_config_get: the caller default only when no layer sets the key',
        () => [], (o, {proj, op, root}) => o.get.eq(0).implies(proj.not().and(op.not()).and(root.not()))),
      f.law('kit_config_get_root never reads the project file', () => [], (o) => o.getRoot.lt(3)),
      f.law('kit_config_get_root agrees with kit_config_get whenever the project sets nothing',
        ({proj}) => [proj.not()], (o) => o.getRoot.eq(o.get)),
      f.law('an env var wins in config get', ({env}) => [env], (o) => o.config.eq(4)),
      // The promise in _resolve: "Mirrors kit-config.sh's own precedence exactly".
      f.law('config get reports the layer kit_config_get reads, for a row that is not root-only and has no env value',
        ({env, rootOnly}) => [env.not(), rootOnly.not()], (o) => o.config.eq(o.get)),
      f.law('config get reports the layer kit_config_get_root reads, for a root-only row with no env value',
        ({env, rootOnly}) => [env.not(), rootOnly], (o) => o.config.eq(o.getRoot)),
    ],
  }
}
