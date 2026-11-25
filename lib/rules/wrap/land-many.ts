// `wrap land <wt1> <wt2> ...`: several worktrees landed one at a time in argument order
// (lib/wrap/wrap-land.sh:cmd_land 410-466). Worktree i > 1 is first rebased onto origin/<default> when it was never
// pushed (_land_many_rebase); then _land_one. The first non-zero exit stops the run: the rest print "not run".
// One request is the outcome for the worktree whose turn it is: ok, fail (its land refused), rebaseFail.
import {nat, oneOf, rule, when} from 'gdp-wired'

export const OUTCOMES = ['ok', 'fail', 'rebaseFail'] as const

export type Variant = 'shipped' | 'continue-after-fail'
export const VARIANTS: Variant[] = ['continue-after-fail']

export function landMany(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'land-many' : `land-many/${variant}`)
    .params({n: nat})
    .inputs({out: oneOf(...OUTCOMES)})
    .state({next: 0, landed: 0, stopped: oneOf('no', 'yes').from('no')})
    .step(({n, out, next, landed, stopped}) => {
      const turn = stopped.is('no').and(next.lt(n))
      const fails = turn.and(out.is('ok').not())
      return {
        next: when(turn, next.plus(1), next),
        landed: when(turn.and(out.is('ok')), landed.plus(1), landed),
        stopped: when(variant === 'continue-after-fail' ? fails.and(fails.not()) : fails, 'yes', stopped),
      }
    })
}

export function laws(r: ReturnType<typeof landMany>) {
  return {
    laws: [
      r.law('no more worktrees run than were named', ({next, n}) => next.atMost(n)),
      r.law('every worktree that ran before the stop landed: nothing after a refusal runs',
        ({next, landed, stopped}) => stopped.is('no').implies(landed.eq(next)).and(stopped.is('yes').implies(landed.plus(1).eq(next)))),
    ],
    stepLaws: [
      r.stepLaw('after a refusal no further worktree is attempted', (b, a) => a.next.eq(b.next).and(a.landed.eq(b.landed)),
        (b) => b.stopped.is('yes')),
      r.stepLaw('worktrees run in argument order, one per turn', (b, a) => a.next.atMost(b.next.plus(1))),
    ],
  }
}
