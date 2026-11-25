// The verification pipeline's retry loop (commands/execute.md, "Routing"), as a gdp-wired rule.
// This rule is the code that runs: bin/verify-loop steps it with rule.compiled(). Nothing re-implements its
// decisions; the laws below are proven over every run of it (lib/rules/prove.ts).
//
// One request is one thing the lead observed for a run: an end verifier's verdict, a fix-agent's report, or the
// attempt state of a builder that went silent. The state is the run's phase and the fix cycles it has spent.
import {nat, oneOf, rule, when} from 'gdp-wired'

export const EVENTS = ['pass', 'fixable', 'known', 'escalate', 'close', 'cannot_fix', 'silent_grace', 'lost'] as const
export const PHASES = ['open', 'passed', 'escalated', 'partial', 'closed'] as const
export const Event = oneOf(...EVENTS)
export const Phase = oneOf(...PHASES)

// The shipped rule, and the bugs it rules out (kept so the proof suite asserts each one is refused).
export type Variant = 'shipped' | 'uncapped' | 'known-spends' | 'escalate-retried'

export function verifyLoop(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'verify-loop' : `verify-loop/${variant}`)
    .params({max: nat})
    .inputs({ev: Event})
    .state({phase: Phase.from('open'), retries: 0})
    .step(({max, ev, phase, retries}) => {
      const open = phase.is('open')
      const capped = variant === 'uncapped' ? open.and(open.not()) : retries.atLeast(max)
      // A fixable verdict spends one fix cycle while the cap allows; at the cap the run ends PARTIAL.
      const fixes = open.and(ev.is('fixable')).and(capped.not())
      const atCap = open.and(ev.is('fixable')).and(capped)
      // A known failure spends no retry (known-failures.sh classify says `known`).
      const knownSpends = variant === 'known-spends' ? open.and(ev.is('known')) : open.and(open.not())
      // FAIL:escalate stops and goes to the human; a fix-agent that cannot fix escalates at once.
      const escalates = variant === 'escalate-retried'
        ? open.and(ev.is('cannot_fix'))
        : open.and(ev.is('escalate').or(ev.is('cannot_fix')))
      const retriesEscalate = variant === 'escalate-retried' ? open.and(ev.is('escalate')) : open.and(open.not())
      const next = when(open.and(ev.is('pass')), 'passed',
        when(escalates, 'escalated',
          when(open.and(ev.is('close')), 'closed',
            when(atCap, 'partial', phase))))
      return {
        phase: next,
        retries: when(fixes.or(knownSpends).or(retriesEscalate), retries.plus(1), retries),
      }
    })
}

export const TERMINAL = ['passed', 'escalated', 'partial', 'closed'] as const

export function laws(r: ReturnType<typeof verifyLoop>) {
  return {
    laws: [
      r.law('a run never spends more fix cycles than the cap', ({retries, max}) => retries.atMost(max)),
    ],
    stepLaws: [
      r.stepLaw('a fixable verdict at the cap ends the run PARTIAL, with no further fix',
        (b, a) => a.phase.is('partial').and(a.retries.eq(b.retries)),
        (b) => b.phase.is('open').and(b.ev.is('fixable')).and(b.retries.atLeast(b.max))),
      r.stepLaw('a run passes only on a PASS verdict',
        (b, a) => a.phase.is('passed').implies(b.phase.is('passed').or(b.ev.is('pass')))),
      r.stepLaw('FAIL:escalate is never retried: it ends the run at the human',
        (b, a) => a.phase.is('escalated').and(a.retries.eq(b.retries)),
        (b) => b.phase.is('open').and(b.ev.is('escalate'))),
      r.stepLaw('a fix-agent that cannot fix escalates at once',
        (b, a) => a.phase.is('escalated'),
        (b) => b.phase.is('open').and(b.ev.is('cannot_fix'))),
      r.stepLaw('a known failure, a resumed builder or a lost attempt spends no retry',
        (b, a) => a.retries.eq(b.retries),
        (b) => b.ev.is('known').or(b.ev.is('silent_grace')).or(b.ev.is('lost'))),
      r.stepLaw('a fix cycle is spent only on a FAIL:fixable verdict',
        (b, a) => a.retries.gt(b.retries).implies(b.ev.is('fixable'))),
      r.stepLaw('a finished run never reopens or spends a retry',
        (b, a) => a.phase.eq(b.phase).and(a.retries.eq(b.retries)),
        (b) => b.phase.is('open').not()),
    ],
  }
}
