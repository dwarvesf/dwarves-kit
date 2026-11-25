// The merge gate every wrap merge reads (lib/wrap/wrap-merge.sh:_pr_gate, lines 11-63), in two parts.
//
// 1. check-verdict: which run of one check name stands for that name. jq: group_by(.name // .context), then
//    sort_by([(pending ? 1 : 0), rtime]) | last. sort_by is stable, so among equal keys the later array entry wins.
//    As a rule: the runs of one name arrive in array order, the state is the run that stands. A run's time is the
//    first real of completedAt/startedAt/createdAt (0 here = none; "" sorts below every time).
// 2. pr-gate: the verdict from the PR's fields, once the standing run of every name is known (anyBad: some name's
//    standing run is neither SUCCESS nor SKIPPED; hasChecks: the rollup has any entry).
//
// The order of the jq `if` chain is the order of the `when`s below.
import {bool, fun, nat, oneOf, rule, when} from 'gdp-wired'

// ---------------------------------------------------------------- check-verdict

export type CheckVariant = 'shipped' | 'latest-wins'
export const CHECK_VARIANTS: CheckVariant[] = ['latest-wins']

export function checkVerdict(variant: CheckVariant = 'shipped') {
  return rule(variant === 'shipped' ? 'check-verdict' : `check-verdict/${variant}`)
    .inputs({pending: bool, time: nat, ok: bool})
    .state({has: bool.from(false), bPending: bool.from(false), bTime: 0, bOk: bool.from(false),
      anyPending: bool.from(false), maxDone: 0})
    .step(({pending, time, ok, has, bPending, bTime, bOk, anyPending, maxDone}) => {
      // key(run) >= key(best), keys compared [pending, time] in order.
      const geq = variant === 'latest-wins'
        ? time.atLeast(bTime)
        : pending.and(bPending.not()).or(pending.and(bPending).or(pending.not().and(bPending.not())).and(time.atLeast(bTime)))
      const take = has.not().or(geq)
      return {
        has: has.or(has.not()),
        bPending: when(take, pending, bPending), bTime: when(take, time, bTime), bOk: when(take, ok, bOk),
        anyPending: anyPending.or(pending),
        maxDone: when(pending.not().and(time.gt(maxDone)), time, maxDone),
      }
    })
}

export function checkLaws(r: ReturnType<typeof checkVerdict>) {
  return {
    laws: [
      // The doc's fail-closed promise: "Every pending entry sorts last in its group whatever its time".
      r.law('a check with any pending run is read as pending', ({anyPending, bPending}) => anyPending.implies(bPending)),
      r.law('with no pending run the standing run is the latest completed one',
        ({anyPending, bTime, maxDone, has}) => has.and(anyPending.not()).implies(bTime.eq(maxDone))),
      // helper: the standing run is never older than any completed run while none is pending
      r.law('a standing pending run means some run was pending', ({anyPending, bPending}) => bPending.implies(anyPending)),
      r.law('no completed run is newer than the standing one unless a run is pending',
        ({anyPending, bTime, maxDone}) => anyPending.or(maxDone.atMost(bTime))),
      r.law('before the first run nothing is recorded',
        ({has, anyPending, bPending, maxDone}) => has.not().implies(anyPending.not().and(bPending.not()).and(maxDone.eq(0)))),
    ],
    stepLaws: [],
  }
}

// ---------------------------------------------------------------- pr-gate

export const MERGEABLES = ['MERGEABLE', 'CONFLICTING', 'UNKNOWN'] as const
export const REVIEWS = ['APPROVED', 'CHANGES_REQUESTED', 'NONE'] as const
export const MSTATES = ['CLEAN', 'HAS_HOOKS', 'UNSTABLE', 'BLOCKED', 'BEHIND', 'DIRTY', 'ABSENT'] as const

// 'shipped' is the fixed bash (a missing mergeStateStatus fails closed); 'absent-is-clean' is the bash before the
// fix, where `(.mergeStateStatus // "CLEAN")` let a PR JSON with no merge state pass as CLEAN once it had checks.
export type GateVariant = 'shipped' | 'absent-is-clean' | 'draft-late' | 'empty-rollup-ok'
export const GATE_VARIANTS: GateVariant[] = ['absent-is-clean', 'draft-late', 'empty-rollup-ok']

export function prGate(variant: GateVariant = 'shipped') {
  return fun(variant === 'shipped' ? 'pr-gate' : `pr-gate/${variant}`)
    .inputs({isDraft: bool, baseOk: bool, mergeable: oneOf(...MERGEABLES), hasChecks: bool, anyBad: bool,
      review: oneOf(...REVIEWS), mstate: oneOf(...MSTATES)})
    .returns(({isDraft, baseOk, mergeable, hasChecks, anyBad, review, mstate}) => {
      const stateOk = mstate.is('CLEAN').or(mstate.is('HAS_HOOKS')).or(mstate.is('UNSTABLE'))
        .or(variant === 'absent-is-clean' ? mstate.is('ABSENT') : mstate.is('ABSENT').and(mstate.is('CLEAN')))
      const draftFirst = variant === 'draft-late' ? isDraft.and(isDraft.not()) : isDraft
      const s1 = draftFirst
      const s2 = s1.not().and(baseOk.not())
      const conflict = s1.not().and(s2.not()).and(mergeable.is('CONFLICTING'))
      const s3 = s1.not().and(s2.not()).and(conflict.not()).and(mergeable.is('MERGEABLE').not())
      const pre = s1.or(s2).or(conflict).or(s3).not()
      const emptyWait = variant === 'empty-rollup-ok' ? pre.and(pre.not()) : pre.and(hasChecks.not()).and(mstate.is('CLEAN').not())
      const badWait = pre.and(emptyWait.not()).and(anyBad)
      const wait = emptyWait.or(badWait)
      const pre2 = pre.and(wait.not())
      const changes = pre2.and(review.is('CHANGES_REQUESTED'))
      const stateSkip = pre2.and(changes.not()).and(stateOk.not())
      const lateDraft = variant === 'draft-late' ? pre2.and(changes.not()).and(stateSkip.not()).and(isDraft) : pre2.and(pre2.not())
      const skip = s1.or(s2).or(s3).or(changes).or(stateSkip).or(lateDraft)
      const ok = pre2.and(changes.not()).and(stateSkip.not()).and(lateDraft.not())
      return {ok, conflict, wait, skip}
    })
}

export function gateLaws(f: ReturnType<typeof prGate>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a draft is never eligible, whatever the rest of the state says', ({isDraft}) => [isDraft], (o) => o.ok.not()),
      f.law('a draft is always a SKIP', ({isDraft}) => [isDraft], (o) => o.skip),
      f.law('a PR is OK only against the default branch', () => [], (o, {baseOk}) => o.ok.implies(baseOk)),
      f.law('a PR is OK only when GitHub says MERGEABLE', () => [], (o, {mergeable}) => o.ok.implies(mergeable.is('MERGEABLE'))),
      f.law('a failing or pending check never reads OK', ({anyBad}) => [anyBad], (o) => o.ok.not()),
      f.law('an empty rollup passes only when GitHub reports the merge state CLEAN',
        ({hasChecks}) => [hasChecks.not()], (o, {mstate}) => o.ok.implies(mstate.is('CLEAN'))),
      f.law('requested changes never read OK', ({review}) => [review.is('CHANGES_REQUESTED')], (o) => o.ok.not()),
      // "Anything but a clean state fails closed here" (HAS_HOOKS and UNSTABLE are the two the code names as clean).
      f.law('a PR is OK only in a CLEAN, HAS_HOOKS or UNSTABLE merge state', () => [],
        (o, {mstate}) => o.ok.implies(mstate.is('CLEAN').or(mstate.is('HAS_HOOKS')).or(mstate.is('UNSTABLE')))),
      f.law('CONFLICT is answered only for a CONFLICTING PR', () => [], (o, {mergeable}) => o.conflict.implies(mergeable.is('CONFLICTING'))),
      f.law('exactly one verdict', () => [], (o) =>
        o.ok.or(o.conflict).or(o.wait).or(o.skip)
          .and(o.ok.and(o.conflict.or(o.wait).or(o.skip)).not())
          .and(o.conflict.and(o.wait.or(o.skip)).not())
          .and(o.wait.and(o.skip).not())),
    ],
  }
}
