// post-compact-reinject (hooks/post-compact-reinject.sh, SessionStart compact) as a gdp-wired decision.
//
//   :16-21  PROJECT: the ## Project paragraph of CLAUDE.md (else AGENTS.md)
//   :29-39  SPEC: the branch's spec or the lone open spec; `ambiguous` names the candidates and picks none
//   :41-54  INTENT: the spec's Problem/Intent/Goal paragraph (python3; skipped without it)
//   :62-71  RULES: the fixed block (no push to main/master, no rm -rf, read the spec, ...)
//   :73-78  printed as hookSpecificOutput.additionalContext. It used python3's json.dumps, and under set -e a missing
//           python3 ended the hook before it printed anything; fixed to jq ('pre-fix' keeps that path).
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'pre-fix' | 'names-ambiguous'
export const VARIANTS: Variant[] = ['pre-fix', 'names-ambiguous']

export function postCompactReinject(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'post-compact-reinject' : `post-compact-reinject/${v}`)
    .inputs({spec: bool, ambig: bool, python: bool})
    .assume(({spec, ambig}) => spec.and(ambig).not())
    .returns(({spec, ambig, python}) => {
      const prints = v === 'pre-fix' ? python : python.or(python.not())
      return {rules: prints, namesSpec: prints.and(v === 'names-ambiguous' ? spec.or(ambig) : spec), ambigLine: prints.and(ambig)}
    })
}

export function laws(f: ReturnType<typeof postCompactReinject>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('compaction always re-injects the push-to-main and rm -rf rules', () => [], (o) => o.rules),
      f.law('an ambiguous spec is named as ambiguous, never picked', (e) => [e.ambig], (o) => o.namesSpec.not().and(o.ambigLine)),
      f.law('the active spec is named when there is one', (e) => [e.spec], (o) => o.namesSpec),
    ],
  }
}
export const make = postCompactReinject
