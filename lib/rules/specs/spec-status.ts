// The spec `Status:` lifecycle as written by lib/spec/spec-status.sh `set` (the one writer) and read by `get`.
// Modelled from the code, not the docs:
//   - main `set` (spec-status.sh:124-132): the target is upper-cased and must be a canonical state (column 1 of
//     lib/spec/states.tsv); an alias (BUILT, SUPERSEDED, ...) or any other word exits 64 and touches nothing.
//   - _set (spec-status.sh:71-101): a missing file or one with no header exits 1, untouched; the same state is a
//     no-op; leaving a terminal state (class `terminal`: SHIPPED, PARKED) prints a reopen notice and still writes;
//     every other move writes silently. The `next` column is never consulted (states.tsv says it is advisory).
//   - _read (spec-status.sh:42-68): NONE (no header), UNKNOWN (a first word not declared), else the canonical state.
// One request is one `set <file> <word>`; the state is what `get` reads afterwards, plus what the step printed.
import {bool, oneOf, rule, when} from 'gdp-wired'

export const STATES = ['NONE', 'UNKNOWN', 'DRAFT', 'APPROVED', 'VALIDATED', 'SHIPPED', 'PARKED'] as const
export const TARGETS = ['DRAFT', 'APPROVED', 'VALIDATED', 'SHIPPED', 'PARKED', 'NONCANON'] as const
export const State = oneOf(...STATES)
export const Target = oneOf(...TARGETS)

export type Variant = 'shipped' | 'silent-reopen' | 'writes-alias' | 'touches-headerless' | 'same-state-notice'
export const VARIANTS: Variant[] = ['silent-reopen', 'writes-alias', 'touches-headerless', 'same-state-notice']

const CANON = ['DRAFT', 'APPROVED', 'VALIDATED', 'SHIPPED', 'PARKED'] as const

export function specStatus(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'spec-status' : `spec-status/${variant}`)
    .inputs({to: Target})
    .state({st: State.from('DRAFT'), notice: bool.from(false), refused: bool.from(false)})
    .step(({to, st}) => {
      const canon = to.is('NONCANON').not()
      const headerless = variant === 'touches-headerless' ? st.is('NONE').and(st.is('NONE').not()) : st.is('NONE')
      const accepted = (variant === 'writes-alias' ? st.is('NONE').not() : canon).and(headerless.not())
      const same = CANON.map(c => st.is(c).and(to.is(c))).reduce((a, b) => a.or(b))
      const terminal = st.is('SHIPPED').or(st.is('PARKED'))
      const moves = accepted.and(same.not())
      // The written word: the target (an alias is written as itself, which `get` then reads as its state; the
      // broken variant writes a non-canonical word, read back as UNKNOWN).
      const written = CANON.reduce((acc, c) => when(to.is(c), c, acc), when(to.is('NONCANON'), 'UNKNOWN', st) as never)
      const notice = variant === 'silent-reopen' ? moves.and(moves.not())
        : variant === 'same-state-notice' ? accepted.and(terminal)
          : moves.and(terminal)
      return {
        st: when(moves, written, st),
        notice,
        refused: accepted.not(),
      }
    })
}

export function laws(r: ReturnType<typeof specStatus>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a spec with no Status: header is never touched by set',
        (b, a) => a.st.is('NONE').and(a.refused), (b) => b.st.is('NONE')),
      r.stepLaw('set never gives a headed spec a missing header',
        (b, a) => a.st.is('NONE').not(), (b) => b.st.is('NONE').not()),
      r.stepLaw('an alias or undeclared word is never written: set exits nonzero and the state stays',
        (b, a) => a.st.eq(b.st).and(a.refused), (b) => b.to.is('NONCANON')),
      r.stepLaw('set only ever writes a canonical state',
        (b, a) => a.st.eq(b.st).not().implies(a.st.is('NONE').not().and(a.st.is('UNKNOWN').not()))),
      r.stepLaw('a set on a headed spec leaves it at the requested canonical state',
        (b, a) => CANON.map(c => b.to.is(c).implies(a.st.is(c))).reduce((x, y) => x.and(y)).and(a.refused.not()),
        (b) => b.st.is('NONE').not().and(b.to.is('NONCANON').not())),
      r.stepLaw('setting the state a spec already has changes nothing and prints no notice',
        (b, a) => a.st.eq(b.st).and(a.notice.not()),
        (b) => CANON.map(c => b.st.is(c).and(b.to.is(c))).reduce((x, y) => x.or(y))),
      r.stepLaw('leaving a terminal state always prints a reopen notice',
        (b, a) => a.notice,
        (b) => b.st.is('SHIPPED').or(b.st.is('PARKED')).and(b.to.is('NONCANON').not())
          .and(CANON.map(c => b.st.is(c).and(b.to.is(c))).reduce((x, y) => x.or(y)).not())),
      r.stepLaw('a reopen notice is printed only when a terminal spec moves',
        (b, a) => a.notice.implies(b.st.is('SHIPPED').or(b.st.is('PARKED')).and(a.st.eq(b.st).not()))),
    ],
  }
}

// Laws a reviewer asks (and docs/WORKFLOW.md's lifecycle `DRAFT -> VALIDATED -> SHIPPED` suggests) that the
// code-faithful rule REFUTES: the writer is permissive by design (DECISION-BRIEF-declared-state-machines.md,
// "Detect, don't dictate"; states.tsv `next` is advisory), so these are findings, confirmed by the bridge.
export function refuted(r: ReturnType<typeof specStatus>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a spec becomes SHIPPED only from APPROVED or VALIDATED (its declared next)',
        (b, a) => a.st.is('SHIPPED').implies(b.st.is('SHIPPED').or(b.st.is('APPROVED')).or(b.st.is('VALIDATED')))),
      r.stepLaw('a move off the declared next path (a skip or a step back) is announced',
        (b, a) => a.notice,
        (b) => b.st.is('VALIDATED').and(b.to.is('DRAFT'))),
    ],
  }
}
