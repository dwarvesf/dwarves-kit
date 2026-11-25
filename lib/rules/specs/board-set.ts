// A board row's Status, as lib/board/backlog.sh `set <ID> <state> [note]` (set_state, backlog.sh:213-271) moves it.
// The machine is declared in lib/board/states.tsv (state, class, next); set reads only the state list, the
// terminal class and the active rows' file order:
//   - a target outside the declared states exits 64, nothing written (backlog.sh:229);
//   - no row for the id exits 1; two or more rows exit 1 with "dedupe first" (backlog.sh:230-241);
//   - otherwise the leading keyword is replaced, from ANY state: a move out of a terminal state (shipped,
//     dropped) to another state prints a reopen notice; a move between two active states to an EARLIER one in
//     file order prints a move-back notice; every other move is silent (backlog.sh:245-253). `next` is advisory.
// One row id; `rows` is how many rows carry it; `other` is a leading keyword outside the vocabulary.
import {bool, oneOf, rule, when} from 'gdp-wired'
import {BOARD_MACHINE, pick} from './util.ts'

// Read from lib/board/states.tsv (tests/test-board-states.sh refuses a copy of the vocabulary under lib/).
export const STATES = BOARD_MACHINE.map(([s]) => s) as unknown as readonly ['queued', 'shipped', 'dropped']
export const ACTIVE = BOARD_MACHINE.filter(([, c]) => c === 'active').map(([s]) => s) as unknown as readonly string[]
const TERMINAL = BOARD_MACHINE.filter(([, c]) => c === 'terminal').map(([s]) => s)
export const State = oneOf(...STATES, 'other')
export const Target = oneOf(...STATES, 'bogus')
export const NOTICES = ['none', 'reopen', 'back'] as const

export type Variant = 'shipped' | 'silent-reopen' | 'writes-duplicates' | 'no-back-notice'
export const VARIANTS: Variant[] = ['silent-reopen', 'writes-duplicates', 'no-back-notice']

const isAt = (x: any, xs: readonly string[]) => xs.map(s => x.is(s)).reduce((a: any, b: any) => a.or(b))

export function boardSet(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'board-set' : `board-set/${variant}`)
    .inputs({to: Target})
    .state({st: State.from('queued'), rows: 1, notice: oneOf(...NOTICES).from('none'), refused: bool.from(false)})
    .step(({to, st, rows}) => {
      const declared = to.is('bogus').not()
      const one = variant === 'writes-duplicates' ? rows.atLeast(1) : rows.eq(1)
      const writes = declared.and(one)
      const same = STATES.map(s => st.is(s).and(to.is(s))).reduce((a, b) => a.or(b))
      const fromTerminal = isAt(st, TERMINAL)
      // backward: both active, the target declared earlier in states.tsv than the current state
      const back = ACTIVE.flatMap((f, fi) => ACTIVE.slice(0, fi).map(t => st.is(f).and(to.is(t)))).reduce((a, b) => a.or(b))
      const reopen = writes.and(same.not()).and(fromTerminal).and(variant === 'silent-reopen' ? fromTerminal.not() : fromTerminal)
      const backN = writes.and(reopen.not()).and(back).and(variant === 'no-back-notice' ? back.not() : back)
      const next = STATES.reduce((acc, s) => when(to.is(s), s, acc), st as never)
      return {
        st: when(writes, next, st),
        rows,
        notice: pick(NOTICES, when(reopen, 1, when(backN, 2, 0))),
        refused: writes.not(),
      }
    })
}

export function laws(r: ReturnType<typeof boardSet>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('set never changes how many rows carry the id', (b, a) => a.rows.eq(b.rows)),
      r.stepLaw('a state outside states.tsv is refused and nothing is written',
        (b, a) => a.st.eq(b.st).and(a.refused), (b) => b.to.is('bogus')),
      r.stepLaw('an id carried by two or more rows is never written (dedupe first)',
        (b, a) => a.st.eq(b.st).and(a.refused), (b) => b.rows.atLeast(2)),
      r.stepLaw('a missing row is never written', (b, a) => a.refused, (b) => b.rows.eq(0)),
      r.stepLaw('set only ever writes a declared state',
        (b, a) => a.st.eq(b.st).not().implies(a.st.is('other').not())),
      r.stepLaw('a set on a single row always lands on the requested state, from any state',
        (b, a) => STATES.map(s => b.to.is(s).implies(a.st.is(s))).reduce((x, y) => x.and(y)).and(a.refused.not()),
        (b) => b.rows.eq(1).and(b.to.is('bogus').not())),
      r.stepLaw('a move out of a terminal state is always announced as a reopen',
        (b, a) => a.notice.is('reopen'),
        (b) => b.rows.eq(1).and(isAt(b.st, TERMINAL)).and(b.to.is('bogus').not())
          .and(STATES.map(s => b.st.is(s).and(b.to.is(s))).reduce((x, y) => x.or(y)).not())),
      r.stepLaw('a move back to an earlier active state is always announced',
        (b, a) => a.notice.is('back'),
        (b) => b.rows.eq(1).and(ACTIVE.flatMap((f, fi) => ACTIVE.slice(0, fi).map(t => b.st.is(f).and(b.to.is(t)))).reduce((x, y) => x.or(y)))),
      r.stepLaw('a notice is printed only for a reopen or a move back',
        (b, a) => a.notice.is('none').not().implies(a.refused.not().and(isAt(b.st, TERMINAL).or(isAt(b.st, ACTIVE))))),
    ],
  }
}

// docs/briefs/DECISION-BRIEF-declared-state-machines.md promises "Writers detect an undeclared move and say so";
// the writer announces only reopens and moves back, so a forward skip off the `next` path is silent. Not fixed:
// no `next` column lists parked or dropped, so announcing every off-path move would fire on every park and drop
// (a decision for the brief's owner, reported instead).
export function refuted(r: ReturnType<typeof boardSet>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a move off the declared next path is announced',
        (b, a) => a.notice.is('none').not(), (b) => b.rows.eq(1).and(b.st.is('queued')).and(b.to.is('shipped'))),
    ],
  }
}
