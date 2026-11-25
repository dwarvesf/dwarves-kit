// spec-drift-guard (hooks/spec-drift-guard.sh, PreToolUse Write) as a gdp-wired decision. Advisory: it always exits 0.
//
//   :14-15   no file_path                                                         -> silent
//   :23-28   a config/doc/lock file, or under node_modules, vendor, dist, build, .git, .claude -> silent
//   :35-42   no open spec under docs/specs/ (spec_active --set) and no .gsd/          -> silent
//   :54-58   the path, its basename, or (off the repo root) its dirname appears in an open spec -> silent
//   :68-76   otherwise: allow, with a "not in any active spec" warning as additionalContext
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'blocks-on-drift' | 'warns-on-config'
export const VARIANTS: Variant[] = ['blocks-on-drift', 'warns-on-config']

export function specDriftGuard(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'spec-drift-guard' : `spec-drift-guard/${v}`)
    .inputs({hasPath: bool, skipped: bool, specs: bool, mentioned: bool})
    .returns(({hasPath, skipped, specs, mentioned}) => {
      const drift = hasPath.and(v === 'warns-on-config' ? hasPath : skipped.not()).and(specs).and(mentioned.not())
      return {warn: drift, block: v === 'blocks-on-drift' ? drift : drift.and(drift.not())}
    })
}

export function laws(f: ReturnType<typeof specDriftGuard>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('spec drift never blocks a write', () => [], (o) => o.block.not()),
      f.law('a warning means the file is outside every open spec', () => [], (o, e) => o.warn.implies(e.specs.and(e.mentioned.not()))),
      f.law('a config, doc or vendored file never warns', (e) => [e.skipped], (o) => o.warn.not()),
      f.law('with no open spec the guard is silent', (e) => [e.specs.not()], (o) => o.warn.not()),
      f.law('a new source file no open spec names is warned about', (e) => [e.hasPath, e.skipped.not(), e.specs, e.mentioned.not()], (o) => o.warn),
    ],
  }
}
export const make = specDriftGuard
