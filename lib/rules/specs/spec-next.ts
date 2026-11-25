// SPEC number reservation, as lib/spec/spec-next.sh keeps it for one repo.
//   - next (spec-next.sh:175-180): max of the union of the scan (specs in every worktree, branches, recent commit
//     subjects; _scan_numbers) and this repo's LIVE reservations (_reservations: within SPEC_RESERVE_TTL), plus 1.
//   - reserve (spec-next.sh:321-349): under the lock, compute next, append `RESERVE | num=<n>`, prune (expired
//     lines, and this repo's lines whose number the scan now holds: neither lowers the union's max while live),
//     print n.
//   - a reservation older than the TTL stops counting (an abandoned claim); `expire` ages every line past it.
//   - `realize k`: a spec, branch or commit subject with number k appears (the scan grows).
// The state keeps the scan's max and the live reservations' max (all `next` reads), the last number reserve
// printed, and whether a reservation has expired since it.
import {bool, max, nat, oneOf, rule, when} from 'gdp-wired'

export type Variant = 'shipped' | 'ignores-reservations' | 'reserve-unrecorded'
export const VARIANTS: Variant[] = ['ignores-reservations', 'reserve-unrecorded']
export const OPS = ['reserve', 'realize', 'expire', 'next'] as const

export function specNext(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'spec-next' : `spec-next/${variant}`)
    .inputs({op: oneOf(...OPS), k: nat})
    .state({scan: 0, res: 0, last: 0, fresh: bool.from(true), out: 0})
    .step(({op, k, scan, res, last, fresh}) => {
      const top = variant === 'ignores-reservations' ? scan : max(scan, res)
      const n = top.plus(1)
      const reserving = op.is('reserve')
      return {
        scan: when(op.is('realize'), max(scan, k), scan),
        res: when(op.is('expire'), 0, when(reserving.and(variant !== 'reserve-unrecorded' ? reserving : reserving.not()), n, res)),
        last: when(reserving, n, last),
        fresh: reserving.or(op.is('expire').not().and(fresh)),
        out: when(reserving.or(op.is('next')), n, 0),
      }
    })
}

export function laws(r: ReturnType<typeof specNext>) {
  return {
    laws: [
      r.law('until a reservation expires, the last reserved number stays taken', ({fresh, last, scan, res}) =>
        fresh.implies(last.atMost(max(scan, res)))),
    ],
    stepLaws: [
      r.stepLaw('reserve hands out a number above every number taken or reserved',
        (b, a) => a.last.gt(b.scan).and(a.last.gt(b.res)), (b) => b.op.is('reserve')),
      r.stepLaw('two reserves with no expiry between them never hand out the same number',
        (b, a) => a.last.gt(b.last), (b) => b.op.is('reserve').and(b.fresh)),
      r.stepLaw('a reserved number reads as taken to the very next caller',
        (b, a) => a.res.atLeast(a.last), (b) => b.op.is('reserve')),
      r.stepLaw('next never moves the ledger or the scan',
        (b, a) => a.scan.eq(b.scan).and(a.res.eq(b.res)).and(a.last.eq(b.last)), (b) => b.op.is('next')),
      r.stepLaw('next and reserve agree: next prints what reserve would claim',
        (b, a) => a.out.eq(max(b.scan, b.res).plus(1)), (b) => b.op.is('next').or(b.op.is('reserve'))),
    ],
  }
}

// By design (the TTL reclaims an abandoned claim), not fixed: a number reserved and never realized is handed out
// again once its line is older than SPEC_RESERVE_TTL.
export function refuted(r: ReturnType<typeof specNext>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a reserved number is never handed out twice',
        (b, a) => a.last.gt(b.last), (b) => b.op.is('reserve').and(b.last.gt(0))),
    ],
  }
}
