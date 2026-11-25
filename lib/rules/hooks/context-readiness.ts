// context-readiness (hooks/context-readiness.sh, SessionStart): the "next:" routing it injects, as a gdp-wired decision.
//
//   :54-62   spec_active --live resolves the branch's spec, the lone open spec, or `ambiguous`
//   :63-65   ambiguous                    -> "multiple live specs ... disambiguate"
//   :66-73   no spec: a queued board      -> "N queued on the board ..."; else "no spec found ... /kit:think"
//   :76-99   a spec: status via spec-status.sh get (DRAFT | APPROVED | VALIDATED | NONE for a spec with no header)
//            DRAFT -> validate; APPROVED|VALIDATED -> every task [x] and total > 0: reviewed (## Review) -> ship,
//            else review; otherwise continue. Any other status (NONE) -> no suggestion at all.
// Tasks are counted by grep: total `- [.]`, done `- [x]` (so done <= total; an `- [X]` is never done).
import {bool, fun, nat, oneOf} from 'gdp-wired'

export const Status = oneOf('DRAFT', 'APPROVED', 'VALIDATED', 'NONE')
export type Variant = 'shipped' | 'ship-unreviewed' | 'ambiguity-guesses'
export const VARIANTS: Variant[] = ['ship-unreviewed', 'ambiguity-guesses']

export function contextReadiness(v: Variant = 'shipped') {
  return fun(v === 'shipped' ? 'context-readiness' : `context-readiness/${v}`)
    .inputs({ambig: bool, spec: bool, status: Status, total: nat, done: nat, reviewed: bool, queued: nat})
    .assume(({done, total}) => done.atMost(total))
    .returns(({ambig, spec, status, total, done, reviewed, queued}) => {
      const amb = v === 'ambiguity-guesses' ? ambig.and(spec.not()) : ambig
      const none = amb.not().and(spec.not())
      const live = amb.not().and(spec)
      const working = live.and(status.is('APPROVED').or(status.is('VALIDATED')))
      const allDone = done.eq(total).and(total.gt(0))
      const finished = working.and(allDone)
      return {
        disambiguate: amb,
        board: none.and(queued.gt(0)),
        think: none.and(queued.eq(0)),
        validate: live.and(status.is('DRAFT')),
        ship: v === 'ship-unreviewed' ? finished : finished.and(reviewed),
        review: finished.and(reviewed.not()),
        cont: working.and(allDone.not()),
        silent: live.and(status.is('NONE')),
      }
    })
}

export function laws(f: ReturnType<typeof contextReadiness>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('ambiguity never routes into one spec', (e) => [e.ambig], (o) => o.disambiguate.and(o.ship.not()).and(o.review.not()).and(o.cont.not()).and(o.validate.not())),
      f.law('ship is suggested only when every task is done and the spec is reviewed', () => [], (o, e) => o.ship.implies(e.done.eq(e.total).and(e.total.gt(0)).and(e.reviewed))),
      f.law('review is suggested only when every task is done', () => [], (o, e) => o.review.implies(e.done.eq(e.total).and(e.total.gt(0)))),
      f.law('a DRAFT spec is routed to validation, never to execution', (e) => [e.ambig.not(), e.spec, e.status.is('DRAFT')], (o) => o.validate.and(o.cont.not()).and(o.ship.not())),
      f.law('a queued board is offered only when there is no spec', () => [], (o, e) => o.board.implies(e.spec.not().and(e.ambig.not()))),
      f.law('at most one next step is suggested', () => [], (o) => {
        const xs = [o.disambiguate, o.board, o.think, o.validate, o.ship, o.review, o.cont]
        let c = xs[0].and(xs[0].not())
        for (let i = 0; i < xs.length; i++) for (let j = i + 1; j < xs.length; j++) c = c.or(xs[i].and(xs[j]))
        return c.not()
      }),
    ],
    // Not a promise the docs make in words, but the header's point ("command suggestions based on project state"):
    // a live spec whose header has no Status (it counts as open) gets no next step at all.
    refutedDecisions: [
      f.law('every session start with a resolvable state suggests a next step', () => [],
        (o) => o.disambiguate.or(o.board).or(o.think).or(o.validate).or(o.ship).or(o.review).or(o.cont)),
    ],
  }
}
export const make = contextReadiness
