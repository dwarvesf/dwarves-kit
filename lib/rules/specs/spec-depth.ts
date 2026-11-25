// The Depth line's two decisions, as lib/spec/spec-depth.sh makes them:
//   - size (spec-depth.sh:cmd_size): `small` exits 0 and lets lib/gate/ship-rules.sh skip the fresh-context
//     validation of a normal-lane spec; anything else is `large`. The header promises: small = Lane normal +
//     Depth standard (or absent) + 1 to 3 tasks. FIX: a Depth line that is present but parses to no level
//     (`research (foo)` with no repo:/outside: prefix, `deep (x)`) used to read as standard (`${LEVELS:-standard}`)
//     and so could be small; it now reads as `invalid`, large (variant 'malformed-is-standard').
//   - check (spec-depth.sh:cmd_check + parse): a problem (exit 1) for a malformed segment, a reason that only says
//     the work matters, standard combined with a deeper level, standard with a non-empty `## Open questions`,
//     or no Depth line on a NEW spec (Generated on/after DEPTH_REQUIRED_FROM, or numbered at or above
//     DEPTH_REQUIRED_FROM_SPEC); an older spec without the line only warns.
// `lv` is the level set parse() leaves: empty, standard alone, deeper levels only, or standard with a deeper one.
// `malformed`: some segment failed to parse (it adds no level). `reasonBad`: some reason is empty or only says the
// work matters. `genNew`/`genOld`: a Generated date on/after or before the cut-off (neither: no date).
// `numNew`/`numOld`: the spec number at/above or below the cut-off (neither: no number).
import {bool, fun, nat, oneOf, when} from 'gdp-wired'
import {pick} from './util.ts'

export type Variant = 'shipped' | 'malformed-is-standard' | 'date-only' | 'standard-mixes'
export const VARIANTS: Variant[] = ['malformed-is-standard', 'date-only', 'standard-mixes']

export function specDepth(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'spec-depth' : `spec-depth/${variant}`)
    .inputs({
      laneNormal: bool, hasLine: bool, lv: oneOf('empty', 'standard', 'deeper', 'both'),
      malformed: bool, reasonBad: bool, genNew: bool, genOld: bool, numNew: bool, numOld: bool, oq: bool, tasks: nat,
    })
    .assume(e => e.genNew.and(e.genOld).not().and(e.numNew.and(e.numOld).not())
      // no line: no levels and nothing parsed; a line whose every segment parsed has some level
      .and(e.hasLine.not().implies(e.lv.is('empty').and(e.malformed.not()).and(e.reasonBad.not())))
      .and(e.hasLine.and(e.malformed.not()).implies(e.lv.is('empty').not())))
    .returns(e => {
      // size: the level set, `standard` when it is empty (no line); a line with no valid level is `invalid`.
      const readsStandard = variant === 'malformed-is-standard'
        ? e.lv.is('standard').or(e.lv.is('empty'))
        : e.lv.is('standard').or(e.lv.is('empty').and(e.hasLine.not()))
      const small = e.laneNormal.and(readsStandard).and(e.tasks.atLeast(1)).and(e.tasks.atMost(3))
      // check
      const parseProblem = e.malformed.or(e.reasonBad).or(variant === 'standard-mixes' ? e.malformed : e.lv.is('both'))
      const isNew = variant === 'date-only' ? e.genNew : e.genNew.or(e.numNew)
      const missingFails = e.hasLine.not().and(isNew)
      const stdOq = e.hasLine.and(e.lv.is('standard')).and(e.oq)
      const fail = parseProblem.or(missingFails).or(stdOq)
      const warn = e.hasLine.not().and(isNew.not())
      return {size: pick(['small', 'large'] as const, when(small, 0, 1)), fail, warn}
    })
}

export function laws(f: ReturnType<typeof specDepth>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a small spec is normal-lane with 1 to 3 tasks', () => [],
        (o, e) => o.size.is('small').implies(e.laneNormal.and(e.tasks.atLeast(1)).and(e.tasks.atMost(3)))),
      f.law('a spec that names a deeper level is never small', (e) => e.lv.is('deeper').or(e.lv.is('both')),
        (o) => o.size.is('large')),
      f.law('a Depth line that is present but names no valid level is never small', (e) => e.hasLine.and(e.lv.is('empty')),
        (o) => o.size.is('large')),
      f.law('a normal-lane spec with Depth standard (or none) and 1 to 3 tasks is small',
        (e) => [e.laneNormal, e.lv.is('standard').or(e.hasLine.not()), e.tasks.atLeast(1), e.tasks.atMost(3)],
        (o) => o.size.is('small')),
      f.law('a new spec (generated on or after the cut-off, or numbered at or above it) with no Depth line fails check',
        (e) => [e.hasLine.not(), e.genNew.or(e.numNew)], (o) => o.fail),
      f.law('a missing Generated line never grants the grace period: the number decides',
        (e) => [e.hasLine.not(), e.genNew.not(), e.genOld.not(), e.numNew], (o) => o.fail),
      f.law('an older spec with no Depth line only warns', (e) => [e.hasLine.not(), e.genNew.not(), e.numNew.not()],
        (o) => o.fail.not().and(o.warn)),
      f.law('standard combined with a deeper level fails check', (e) => e.lv.is('both'), (o) => o.fail),
      f.law('standard with a non-empty Open questions section fails check', (e) => [e.hasLine, e.lv.is('standard'), e.oq],
        (o) => o.fail),
      f.law('a malformed segment or a reason that only says the work matters fails check', (e) => e.malformed.or(e.reasonBad),
        (o) => o.fail),
    ],
  }
}
