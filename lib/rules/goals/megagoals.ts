// The mega-goal Pick-up counter (lib/goal/megagoals.sh: count_subgoals L85-98 and the visibility rule in cmd_list
// L127-133), as a gdp-wired rule over a ROADMAP's lines.
//
// One request is one line, classified the way the awk program sees it:
//   sec     a `## Sub-goals...` or `## Status...` heading (opens a counted section)
//   h2      any other `## ` heading;  h1: a `# ` heading;  h3: a `### ` (or deeper) heading
//   done / open / parked   a line carrying that box token (lib/mega/box.tsv; done wins over open over parked)
//   text    anything else
// `inSem` is where the line really is: inside a Sub-goals or Status section, which (markdown) ends at the next heading
// of level 1 or 2. It is a ghost: the script keeps only `insec`.
import {bool, no, oneOf, rule, when, yes, type Cond} from 'gdp-wired'

export const LINES = ['sec', 'h2', 'h1', 'h3', 'done', 'open', 'parked', 'text'] as const
export const Line = oneOf(...LINES)
const sel = (c: Cond, a: Cond, b: Cond) => c.and(a).or(c.not().and(b))

// 'h1-leaks' is count_subgoals as it was found: only a `## ` heading closed the section, so the boxes under a later
// `# ` heading were counted as sub-goals (FINDINGS.md F7).
export type Variant = 'shipped' | 'h1-leaks' | 'parked-hidden'
export const VARIANTS: Variant[] = ['h1-leaks', 'parked-hidden']

export function megagoals(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'megagoals' : `megagoals/${variant}`)
    .params({all: bool})
    .inputs({line: Line})
    .state({insec: bool.from(false), inSem: bool.from(false), done: 0, total: 0, active: 0, parked: 0, outside: 0})
    .flags(({line, insec, inSem}) => {
      const closes = line.is('h2').or(variant === 'h1-leaks' ? line.is('h2') : line.is('h1'))
      const box = line.is('done').or(line.is('open')).or(line.is('parked'))
      return {counts: insec.and(box), closes, box, semIn: inSem}
    })
    .step(({line, insec, inSem, done, total, active, parked, outside, counts, closes}) => ({
      insec: sel(line.is('sec'), yes, sel(closes, no, insec)),
      inSem: sel(line.is('sec'), yes, sel(line.is('h2').or(line.is('h1')), no, inSem)),
      done: when(counts.and(line.is('done')), done.plus(1), done),
      active: when(counts.and(line.is('open')), active.plus(1), active),
      parked: when(counts.and(line.is('parked')), parked.plus(1), parked),
      total: when(counts, total.plus(1), total),
      outside: when(counts.and(inSem.not()), outside.plus(1), outside),
    }))
}

export type MegagoalsRule = ReturnType<typeof megagoals>

// cmd_list L127-133: shown unless (no boxes, or no open and no parked box) and not --all; "(parked)" when no open
// box is left and a parked one is.
export const shown = (s: any, variant: Variant = 'shipped') => {
  const parkedShows = variant === 'parked-hidden' ? no : s.parked.atLeast(1)
  return s.total.atLeast(1).and(s.active.atLeast(1).or(parkedShows).or(s.all)).or(s.total.eq(0).and(s.all))
}

export function laws(r: MegagoalsRule, variant: Variant = 'shipped') {
  return {
    laws: [
      r.law('done, open and parked boxes add up to the total', ({done, active, parked, total}) => done.plus(active).plus(parked).eq(total)),
      r.law('the counted section is open exactly when the line is inside Sub-goals or Status', ({insec, inSem}) => insec.iff(inSem)),
      r.law('a box outside the Sub-goals and Status sections is never counted', ({outside}) => outside.eq(0)),
      r.law('a mega-goal with open work is always listed', (s) => s.active.atLeast(1).implies(shown(s, variant))),
      r.law('a mega-goal whose only unfinished boxes are parked is still listed', (s) => s.active.eq(0).and(s.parked.atLeast(1)).implies(shown(s, variant))),
      r.law('a fully done mega-goal is hidden unless --all', (s) => s.total.atLeast(1).and(s.active.eq(0)).and(s.parked.eq(0)).and(s.all.not()).implies(shown(s, variant).not())),
    ],
    stepLaws: [],
  }
}
