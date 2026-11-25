// The dispatch Attempt state machine (lib/goal/attempt-state.sh), as a gdp-wired rule.
//
// One request is one verb the lead runs: dispatch, mark-disconnected, resume, lose-attempt, commit-result, abandon.
// A refused verb (exit 1, "REFUSED", an illegal transition) writes nothing: every refusal path in the script returns
// before `_save`, so the rule keeps the state as it was.
//
// State, as `<task>.task` stores it (attempt-state.sh:_save):
//   task       state=queued|dispatched|done|lost
//   n          the number of `attempt|...` lines (attempt k is the script's `a<k+1>`)
//   winner     winner=a<k+1>, kept here as k+1 (0 = no winner)
//   Att[k]     attempt k's state; `none` for k >= n (no such line)
//   Wk[k]      attempt k's worker
//   Until[k], HasUntil[k]  attempt k's grace deadline (the 4th field, empty or epoch seconds)
//   Excl[w]    worker w is on the `excluded=` list
//
// The target of a verb is the attempt the request names (`a`). The script resolves an unnamed verb to the one live
// attempt (`_index_live`); with no live attempt it refuses, which is what every named non-live target does too, so the
// bridge names the attempt and the rule needs no lookup.
import {bool, everyKey, forall, nat, no, oneOf, rule, when, yes} from 'gdp-wired'

export const OPS = ['dispatch', 'disconnect', 'resume', 'lose', 'commit', 'abandon'] as const
export const TASK = ['queued', 'dispatched', 'done', 'lost'] as const
export const ATT = ['none', 'running', 'disconnected', 'lost', 'committed', 'superseded'] as const
export const Op = oneOf(...OPS)
export const TaskSt = oneOf(...TASK)
export const AttSt = oneOf(...ATT)

// The shipped script, and the bugs its laws rule out (kept so prove.ts asserts each one is refused).
export type Variant = 'shipped' | 'second-dispatch' | 'grace-extends' | 'lose-early' | 'recommit' | 'no-exclusion'
export const VARIANTS: Variant[] = ['second-dispatch', 'grace-extends', 'lose-early', 'recommit', 'no-exclusion']

export function attemptState(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'attempt-state' : `attempt-state/${variant}`)
    .inputs({op: Op, a: nat, w: nat, g: nat, t: nat})
    .state({task: TaskSt.from('queued'), n: 0, winner: 0})
    .maps({Att: AttSt.from('none'), Wk: 0, Until: 0, HasUntil: bool.from(false), Excl: bool.from(false)})
    .flags(({op, a, w, g, t, task, n, Att, HasUntil, Until, Excl}) => {
      const tgt = Att.at(a)
      const tgtLive = tgt.is('running').or(tgt.is('disconnected'))
      // as_dispatch: refused for an excluded worker (L218), or while any attempt is live (L222-226, _index_live),
      // or when the task cannot move to dispatched (_task_goto: queued>dispatched, or already dispatched).
      const noLive = variant === 'second-dispatch' ? yes : everyKey(k => Att.at(k).is('running').not().and(Att.at(k).is('disconnected').not()))
      const excluded = variant === 'no-exclusion' ? no : Excl.at(w)
      const dispatches = op.is('dispatch').and(excluded.not()).and(noLive).and(task.is('queued').or(task.is('dispatched')))
      // as_mark_disconnected / as_resume: _attempt_goto from running or disconnected (same-state is a no-op move).
      const disconnects = op.is('disconnect').and(tgtLive)
      const resumes = op.is('resume').and(tgtLive)
      // as_lose_attempt: only a disconnected attempt (L282), only once the window is over (L287: refused while
      // now <= until; an empty until never refuses), and the task must move to queued (dispatched>queued, or same).
      const windowOver = variant === 'lose-early' ? yes : HasUntil.at(a).not().or(t.gt(Until.at(a)))
      const loses = op.is('lose').and(tgt.is('disconnected')).and(windowOver).and(task.is('dispatched').or(task.is('queued')))
      // as_commit_result: on a done task a non-committed live attempt is recorded superseded (NOOP); a committed one is
      // left alone; a lost or superseded one is an illegal move (refused). Otherwise the attempt must be live and the
      // task dispatched (queued>done and lost>done are illegal).
      // The bug a task-keyed commit rules out: a late worker (here one whose attempt was already lost) commits again
      // over the winner.
      const recommit = variant === 'recommit' ? op.is('commit').and(task.is('done')).and(tgt.is('lost')) : no
      const commitsFirst = op.is('commit').and(task.is('done').not()).and(tgtLive).and(task.is('dispatched'))
      const commits = commitsFirst.or(recommit)
      const supersedesLate = op.is('commit').and(task.is('done')).and(tgtLive).and(recommit.not())
      // as_abandon: _task_goto lost (from queued or dispatched; lost>lost is a no-op), every live attempt superseded.
      // `_load || refuse` (L336): abandon needs the task file, which exists exactly once an attempt was dispatched.
      const abandons = op.is('abandon').and(n.atLeast(1)).and(task.is('done').not())
      const extendDeadline = variant === 'grace-extends' ? yes : HasUntil.at(a).not()
      return {dispatches, disconnects, resumes, loses, commits, supersedesLate, abandons, setsUntil: disconnects.and(extendDeadline)}
    })
    .step(({a, w, g, t, task, n, winner, Att, Wk, Until, HasUntil, Excl,
      dispatches, disconnects, resumes, loses, commits, supersedesLate, abandons, setsUntil}) => ({
      Att: Att.each(k => {
        const c = Att.at(k)
        const live = c.is('running').or(c.is('disconnected'))
        return when(dispatches.and(k.eq(n)), c.of('running'),
          when(disconnects.and(k.eq(a)), c.of('disconnected'),
            when(resumes.and(k.eq(a)), c.of('running'),
              when(loses.and(k.eq(a)), c.of('lost'),
                when(commits.and(k.eq(a)), c.of('committed'),
                  when(supersedesLate.and(k.eq(a)), c.of('superseded'),
                    // the winner's live siblings lost the race (L322-327); abandon resolves every live attempt (L341-344)
                    when(commits.or(abandons).and(live), c.of('superseded'), c)))))))
      }),
      Wk: Wk.set(n, when(dispatches, w, Wk.at(n))),
      Until: Until.set(a, when(setsUntil, t.plus(g), Until.at(a))),
      // mark-disconnected sets a deadline once; resume clears it (L269); dispatch writes an empty one.
      HasUntil: HasUntil.each(k => when(setsUntil.and(k.eq(a)), yes,
        when(resumes.and(k.eq(a)).or(dispatches.and(k.eq(n))), no, HasUntil.at(k)))),
      Excl: Excl.set(Wk.at(a), Excl.at(Wk.at(a)).or(loses)),
      n: when(dispatches, n.plus(1), n),
      winner: when(commits, a.plus(1), winner),
      task: when(dispatches, task.of('dispatched'),
        when(loses, task.of('queued'),
          when(commits, task.of('done'),
            when(abandons, task.of('lost'), task)))),
    }))
}

export type AttemptRule = ReturnType<typeof attemptState>

const liveAt = (Att: any, k: any) => Att.at(k).is('running').or(Att.at(k).is('disconnected'))

export function laws(r: AttemptRule) {
  return {
    laws: [
      r.law('a task never has two live attempts', ({Att}) => forall((j, k) => liveAt(Att, j).and(liveAt(Att, k)).implies(j.eq(k)))),
      r.law('only the newest attempt can be live', ({Att, n}) => forall(k => liveAt(Att, k).implies(k.plus(1).eq(n)))),
      r.law('no attempt exists past the last one dispatched', ({Att, n}) => forall(k => k.atLeast(n).implies(Att.at(k).is('none')))),
      r.law('a task is dispatched exactly when its newest attempt is live', ({task, Att, n}) =>
        task.is('dispatched').iff(n.atLeast(1).and(liveAt(Att, n.minus(1))))),
      r.law('a task is done exactly when it has a winner', ({task, winner}) => task.is('done').iff(winner.atLeast(1))),
      r.law('the winner is a committed attempt', ({winner, Att}) => winner.atLeast(1).implies(Att.at(winner.minus(1)).is('committed'))),
      r.law('at most one attempt ever commits a result', ({Att, winner}) =>
        forall(k => Att.at(k).is('committed').implies(winner.eq(k.plus(1))))),
      r.law('a disconnected attempt always has a grace deadline', ({Att, HasUntil}) =>
        forall(k => Att.at(k).is('disconnected').implies(HasUntil.at(k)))),
    ],
    stepLaws: [
      r.stepLaw('an excluded worker is never dispatched again',
        (b, a) => a.n.eq(b.n), (b) => b.op.is('dispatch').and(b.Excl.at(b.w))),
      r.stepLaw('an attempt is lost only after its grace window is over',
        (b, a) => a.Att.at(b.a).is('lost').implies(b.t.gt(b.Until.at(b.a))), (b) => b.Att.at(b.a).is('disconnected').and(b.HasUntil.at(b.a))),
      r.stepLaw('a repeated disconnect never pushes the deadline out',
        (b, a) => a.Until.at(b.a).eq(b.Until.at(b.a)), (b) => b.Att.at(b.a).is('disconnected')),
      r.stepLaw('a done task stays done with the same winner',
        (b, a) => a.task.is('done').and(a.winner.eq(b.winner)), (b) => b.task.is('done')),
      r.stepLaw('an abandoned task never runs again',
        (b, a) => a.task.is('lost').and(a.n.eq(b.n)), (b) => b.task.is('lost')),
      r.stepLaw('an excluded worker stays excluded',
        (b, a) => forall(k => b.Excl.at(k).implies(a.Excl.at(k)))),
      r.stepLaw('a finished attempt never moves again', (b, a) => forall(k =>
        b.Att.at(k).is('lost').or(b.Att.at(k).is('committed')).or(b.Att.at(k).is('superseded')).implies(a.Att.at(k).eq(b.Att.at(k))))),
      r.stepLaw('losing an attempt excludes its worker and frees the task',
        (b, a) => a.Excl.at(b.Wk.at(b.a)).and(a.task.is('queued')),
        (b) => b.op.is('lose').and(b.Att.at(b.a).is('disconnected')).and(b.HasUntil.at(b.a).not().or(b.t.gt(b.Until.at(b.a)))).and(b.task.is('dispatched'))),
    ],
  }
}
