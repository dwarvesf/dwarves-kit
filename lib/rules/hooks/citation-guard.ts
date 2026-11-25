// citation-guard (hooks/citation-guard.sh, Stop) as a gdp-wired decision.
//
//   :31-34   not one JSON object, or no readable transcript_path          -> exit 0
//   :41-61   the last assistant entry's text (code and URLs stripped)       -> no text: exit 0
//   :65-74   no path:line citations                                        -> exit 0
//   :82-105  every citation resolves (the file exists with that many lines) -> exit 0
//   :110-125 log the unresolved ones
//   :127-131 CITATION_GUARD_STRICT=1 -> exit 2 (block the Stop); otherwise exit 0
import {bool, fun} from 'gdp-wired'

export type Variant = 'shipped' | 'blocks-unarmed' | 'blocks-on-any-citation'
export const VARIANTS: Variant[] = ['blocks-unarmed', 'blocks-on-any-citation']

export function citationGuard(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'citation-guard' : `citation-guard/${v}`)
    .inputs({transcript: bool, refs: bool, unresolved: bool, strict: bool, active: bool})  // active: stop_hook_active, never read
    .assume(({refs, unresolved}) => unresolved.implies(refs))
    .returns(({transcript, refs, unresolved, strict}) => {
      const bad = transcript.and(v === 'blocks-on-any-citation' ? refs : unresolved)
      return {log: transcript.and(unresolved), block: bad.and(v === 'blocks-unarmed' ? bad : strict)}
    })
}
export const make = citationGuard

export function laws(f: ReturnType<typeof citationGuard>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('without strict mode it never blocks', (e) => [e.strict.not()], (o) => o.block.not()),
      f.law('it blocks only on an unresolved citation', () => [], (o, e) => o.block.implies(e.unresolved)),
      f.law('strict mode blocks a Stop that cites a line that does not exist', (e) => [e.transcript, e.unresolved, e.strict], (o) => o.block),
    ],
    // The other Stop hooks (anti-rationalization, slop-cleaner) let a Stop that is already continuing through; this one
    // never reads stop_hook_active, so in strict mode it can block every Stop of a turn while the message keeps a bad ref.
    refutedDecisions: [
      f.law('a Stop that is already continuing is never blocked', (e) => [e.active], (o) => o.block.not()),
    ],
  }
}
