// Which copy of a duplicated board row survives, for the two collapse verbs of lib/board/backlog.sh, over up to
// three copies of one id in file order (copy 2 present when `three`):
//   - dedupe <ID> (backlog.sh:273-308): the first shipped copy, else the first dropped, else the first parked,
//     else the LAST occurrence.
//   - dedupe-all (backlog.sh:314-338): the first copy whose leading keyword is not `queued`, else the first copy.
// `keep` is dedupe's survivor, `keepAll` dedupe-all's.
import {bool, fun, oneOf, when} from 'gdp-wired'
import {BOARD_MACHINE} from './util.ts'

// The declared states, read from lib/board/states.tsv (no copy of the vocabulary under lib/), plus `other`.
export const LEADS = [...BOARD_MACHINE.map(([s]) => s), 'other'] as unknown as readonly ['queued', 'shipped', 'dropped', 'parked', 'other']
const Lead = oneOf(...LEADS)

export type Variant = 'shipped' | 'dedupe-keeps-first' | 'all-keeps-last'
export const VARIANTS: Variant[] = ['dedupe-keeps-first', 'all-keeps-last']

export function boardDedupe(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'board-dedupe' : `board-dedupe/${variant}`)
    .inputs({c0: Lead, c1: Lead, c2: Lead, three: bool})
    .returns(({c0, c1, c2, three}) => {
      const has = (i: number) => i < 2 ? three.or(three.not()) : three
      const c = [c0, c1, c2]
      const first = (p: (x: any) => any, otherwise: any) =>
        when(p(c[0]), 0, when(p(c[1]), 1, when(p(c[2]).and(has(2)), 2, otherwise)))
      const last = variant === 'dedupe-keeps-first' ? 0 : when(three, 2, 1)
      const keep = first(x => x.is('shipped'), first(x => x.is('dropped'), first(x => x.is('parked'), last)))
      const keepAll = variant === 'all-keeps-last' ? when(three, 2, 1) : first(x => x.is('queued').not(), 0)
      return {keep, keepAll}
    })
}

const at = (e: any, i: any, p: (x: any) => any) => i.eq(0).and(p(e.c0)).or(i.eq(1).and(p(e.c1))).or(i.eq(2).and(e.three).and(p(e.c2)))
const anyCopy = (e: any, p: (x: any) => any) => p(e.c0).or(p(e.c1)).or(e.three.and(p(e.c2)))

export function laws(f: ReturnType<typeof boardDedupe>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('both verbs keep exactly one of the copies', () => [],
        (o, e) => o.keep.atMost(when(e.three, 2, 1)).and(o.keepAll.atMost(when(e.three, 2, 1)))),
      f.law('dedupe keeps a shipped copy whenever there is one', (e) => anyCopy(e, x => x.is('shipped')),
        (o, e) => at(e, o.keep, x => x.is('shipped'))),
      f.law('dedupe keeps a dropped copy when there is one and none is shipped',
        (e) => [anyCopy(e, x => x.is('dropped')), anyCopy(e, x => x.is('shipped')).not()], (o, e) => at(e, o.keep, x => x.is('dropped'))),
      f.law('dedupe keeps the last copy when none is shipped, dropped or parked',
        (e) => anyCopy(e, x => x.is('shipped').or(x.is('dropped')).or(x.is('parked'))).not(), (o, e) => o.keep.eq(when(e.three, 2, 1))),
      f.law('dedupe-all keeps a flipped (non-queued) copy over a queued one', (e) => anyCopy(e, x => x.is('queued').not()),
        (o, e) => at(e, o.keepAll, x => x.is('queued').not())),
      f.law('dedupe-all keeps the first copy when every copy is still queued', (e) => anyCopy(e, x => x.is('queued').not()).not(),
        (o) => o.keepAll.eq(0)),
    ],
  }
}

// Reviewer laws the faithful rule refutes (documented behaviour, not fixed): `board set` says "dedupe first", and
// `dedupe` on a [claimed, queued] pair keeps the queued copy, dropping the flip; dedupe-all keeps the claimed one.
export function refuted(f: ReturnType<typeof boardDedupe>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('dedupe never drops a flipped (non-queued) copy to keep a queued one', (e) => anyCopy(e, x => x.is('queued').not()),
        (o, e) => at(e, o.keep, x => x.is('queued').not())),
      f.law('dedupe and dedupe-all keep the same copy', () => [], (o) => o.keep.eq(o.keepAll)),
    ],
  }
}
