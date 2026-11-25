// The transient-error retry around `gh pr merge` (lib/wrap/wrap-common.sh:_gh_merge_retry, lines 86-118), as a
// gdp-wired rule. One request is the answer of one `gh pr merge` call; the state is where the loop is and how many
// calls it made.
//
// What the bash does, line by line:
//   WRAP_MERGE_RETRY_MAX=${WRAP_MERGE_RETRY_MAX:-3}, then (since the fix) a non-number falls back to 3
//   loop: out=$(gh pr merge ...); rc=$?
//     rc 0                                  -> success (return 0)
//     output says "already merged"          -> success (return 0); the caller still verifies MERGED
//     attempt >= MAX, or not transient      -> return rc (the real refusal, or the budget is spent)
//     else sleep attempt*SLEEP, attempt+1, call again
// `attempt` counts the calls made so far, and is compared AFTER the call, so MAX=0 still makes one call.
//
// Before the fix the MAX was used as given: `[ "$attempt" -ge "five" ]` is an error, the error reads as false, and a
// transient answer retried forever (299 calls in 5 s against a 502 stub). The kept variant 'unvalidated-max' is that
// code: param `maxIsNum` says whether the env value is a whole number.
import {bool, nat, oneOf, rule, when} from 'gdp-wired'

export const ANSWERS = ['ok', 'already', 'transient', 'refusal'] as const
export const PHASES = ['trying', 'merged', 'failed'] as const
export const Answer = oneOf(...ANSWERS)
export const Phase = oneOf(...PHASES)

// 'shipped' is the fixed bash. 'unvalidated-max' is the bash before the fix (a non-number MAX never stops the loop).
// 'retry-refusal' retries a real refusal too; 'no-cap' never consults the budget.
export type Variant = 'shipped' | 'unvalidated-max' | 'retry-refusal' | 'no-cap'
export const VARIANTS: Variant[] = ['unvalidated-max', 'retry-refusal', 'no-cap']

export const DEFAULT_MAX = 3

export function mergeRetry(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'merge-retry' : `merge-retry/${variant}`)
    // max: the numeric value when maxIsNum; ignored otherwise (the fix reads 3 then).
    .params({max: nat, maxIsNum: bool})
    .inputs({ans: Answer})
    .state({phase: Phase.from('trying'), calls: 0})
    .step(({max, maxIsNum, ans, phase, calls}) => {
      const trying = phase.is('trying')
      const made = calls.plus(1)
      // The effective budget the `-ge` test reads.
      const eff = when(maxIsNum, max, DEFAULT_MAX)
      const budgetSpent = variant === 'no-cap' ? trying.and(trying.not())
        : variant === 'unvalidated-max' ? maxIsNum.and(made.atLeast(max))
        : made.atLeast(eff)
      const stops = variant === 'retry-refusal' ? budgetSpent : budgetSpent.or(ans.is('refusal'))
      const success = ans.is('ok').or(ans.is('already'))
      return {
        calls: when(trying, made, calls),
        phase: when(trying.and(success), 'merged', when(trying.and(stops), 'failed', phase)),
      }
    })
}

export function laws(r: ReturnType<typeof mergeRetry>) {
  return {
    laws: [
      // The bound the comment promises ("WRAP_MERGE_RETRY_MAX attempts (default 3)"), with the one call MAX=0 still makes.
      r.law('a merge makes at most max(1, WRAP_MERGE_RETRY_MAX) gh calls, 3 when the value is not a number',
        ({calls, max, maxIsNum}) => when(maxIsNum, calls.atMost(max).or(calls.atMost(1)), calls.atMost(DEFAULT_MAX))),
      r.law('the loop has stopped once the budget is spent',
        ({phase, calls, max, maxIsNum}) => phase.is('trying').implies(calls.lt(when(maxIsNum, max, DEFAULT_MAX)).or(calls.eq(0)))),
    ],
    stepLaws: [
      r.stepLaw('a real refusal returns on the first try it is seen, never retried',
        (_b, a) => a.phase.is('failed'), (b) => b.phase.is('trying').and(b.ans.is('refusal'))),
      r.stepLaw('a merge succeeds only on a zero exit or an "already merged" answer',
        (b, a) => a.phase.is('merged').implies(b.phase.is('merged').or(b.ans.is('ok')).or(b.ans.is('already')))),
      r.stepLaw('a finished merge makes no further call',
        (b, a) => a.phase.eq(b.phase).and(a.calls.eq(b.calls)), (b) => b.phase.is('trying').not()),
    ],
  }
}

// The bash's observable outcome for a run, read off the rule's state.
export function outcome(st: {phase: string, calls: number}) {
  return {rc0: st.phase === 'merged', calls: st.calls, stopped: st.phase !== 'trying'}
}
