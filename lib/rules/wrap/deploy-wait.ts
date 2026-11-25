// `wrap deploy-wait <owner>/<name> <sha>`: the bounded wait for a push-deploy's check runs
// (lib/wrap/wrap-deploy.sh:_deploy_wait_poll, lines 105-157). Each loop: one `gh api .../check-runs` read.
//   exit 0 read: judge the runs (highest id per name, filtered by --check):
//       every --check matched and every run completed -> stop: DEPLOYED (exit 0) if every conclusion is success,
//                                                          else FAILED (exit 1)
//       a --check with no run yet, or a run still open  -> keep waiting
//     an answer that does not parse                    -> ERROR (exit 2)
//   non-zero read: transient (the _gh_merge_transient whitelist) -> keep waiting; anything else -> ERROR (exit 2)
//   keep waiting: if waited >= timeout -> TIMEOUT (exit 124); else sleep DEPLOY_POLL_SECS,
//                 waited = max(waited + poll, wall time since start)
// Requests: one read, with the wall seconds the gh call itself took (slow). State: waited, the wall clock, phase.
import {nat, oneOf, rule, when, max} from 'gdp-wired'

export const READS = ['success', 'failed', 'open', 'missing', 'transient', 'error', 'unreadable'] as const
export const PHASES = ['polling', 'deployed', 'failed', 'error', 'timeout'] as const
export const EXIT: Record<string, number> = {deployed: 0, failed: 1, error: 2, timeout: 124}

export type Variant = 'shipped' | 'wall-ignored' | 'skipped-passes' | 'missing-passes'
export const VARIANTS: Variant[] = ['skipped-passes', 'missing-passes']

export function deployWait(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'deploy-wait' : `deploy-wait/${variant}`)
    .params({timeout: nat, poll: nat})
    // DEPLOY_POLL_SECS defaults to 10; the rule is stated for a poll of at least 1 (see `ends` below)
    .pre(({poll}) => poll.atLeast(1))
    .inputs({read: oneOf(...READS), slow: nat})
    .state({phase: oneOf(...PHASES).from('polling'), waited: 0, wall: 0, reads: 0, last: oneOf(...READS).from('open')})
    .step(({timeout, poll, read, slow, phase, waited, wall, reads, last}) => {
      const live = phase.is('polling')
      const done = variant === 'skipped-passes' ? read.is('success').or(read.is('failed')) : read.is('success')
      const missingDone = variant === 'missing-passes' ? read.is('missing') : read.is('missing').and(read.is('success'))
      const ok = live.and(done.or(missingDone))
      const bad = live.and(ok.not()).and(read.is('failed'))
      const err = live.and(read.is('error').or(read.is('unreadable')))
      const waiting = live.and(ok.not()).and(bad.not()).and(err.not())
      const out = waiting.and(waited.atLeast(timeout))
      const sleeps = waiting.and(out.not())
      const wall2 = wall.plus(slow).plus(when(sleeps, poll, 0))
      return {
        phase: when(ok, 'deployed', when(bad, 'failed', when(err, 'error', when(out, 'timeout', phase)))),
        waited: when(sleeps, variant === 'wall-ignored' ? waited.plus(poll) : max(waited.plus(poll), wall2), waited),
        wall: when(live, wall2, wall),
        reads: when(live, reads.plus(1), reads),
        last: when(live, read, last),
      }
    })
}

export function laws(r: ReturnType<typeof deployWait>) {
  return {
    laws: [
      r.law('DEPLOYED only on a read where every matching run completed with success',
        ({phase, last}) => phase.is('deployed').implies(last.is('success'))),
      r.law('while it waits, the wait clock never runs behind the wall clock', ({phase, waited, wall}) => phase.is('polling').implies(wall.atMost(waited))),
      r.law('a wait that timed out had reached its timeout', ({phase, waited, timeout}) => phase.is('timeout').implies(waited.atLeast(timeout))),
    ],
    stepLaws: [
      r.stepLaw('a completed run that did not succeed fails the wait, never DEPLOYED', (_b, a) => a.phase.is('failed'),
        (b) => b.phase.is('polling').and(b.read.is('failed'))),
      r.stepLaw('a --check with no matching run never reads as deployed', (_b, a) => a.phase.is('deployed').not(),
        (b) => b.phase.is('polling').and(b.read.is('missing'))),
      r.stepLaw('a non-transient read error stops the wait at once', (_b, a) => a.phase.is('error'),
        (b) => b.phase.is('polling').and(b.read.is('error').or(b.read.is('unreadable')))),
      r.stepLaw('a read at or past the timeout never sleeps again', (b, a) => a.phase.is('polling').not(),
        (b) => b.phase.is('polling').and(b.waited.atLeast(b.timeout))),
      r.stepLaw('each sleep moves the wait clock by at least the poll interval', (b, a) => a.waited.atLeast(b.waited.plus(b.poll)),
        (b) => b.phase.is('polling').and(b.waited.lt(b.timeout)).and(b.read.is('open').or(b.read.is('missing')).or(b.read.is('transient')))),
      r.stepLaw('a finished wait reads nothing more', (b, a) => a.reads.eq(b.reads).and(a.phase.eq(b.phase)), (b) => b.phase.is('polling').not()),
    ],
  }
}

// Every wait ends: with DEPLOY_POLL_SECS >= 1 each read either ends the wait or moves the wait clock towards the
// timeout. (With DEPLOY_POLL_SECS=0 only the wall clock moves it; the bound then rests on gh taking time.)
export function ends(r: ReturnType<typeof deployWait>) {
  return r.leadsTo('every wait ends', {
    from: ({phase}) => phase.is('polling'),
    to: ({phase}) => phase.is('polling').not(),
    rank: ({timeout, waited}) => timeout.minus(waited),
    helpful: () => ({read: 0, slow: 0}),
  })
}
