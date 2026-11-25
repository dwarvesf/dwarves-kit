// One `queue.sh run` night over its rows (lib/queue/queue.sh cmd_run, L1040-1185), as a gdp-wired rule.
//
// One request is one row as cmd_run meets it:
//   terminal   the slug's last journal verdict is done or gated: skipped, no window, no journal row (L1063-1066)
//   skip       a preflight reason (repo missing, dirty tree, not on the default branch, pointer not allow-listed):
//              journaled `skipped`, no window (L1068-1088)
//   held       another conductor holds the slug's heartbeat: skipped, no window (the in-flight claim, L1095-1099)
//   run        a launch; `v` is the verdict it journals, `calls` the TOOL_CALLS it self-reported
// The night stops (every later row untouched) on two consecutive `error`/`stalled` verdicts (L1165-1174), on
// `--max-megas N` launches (L1177-1180), or when the queue-wide tool-call total reaches its ceiling (L1153-1160).
import {bool, nat, no, oneOf, rule, when} from 'gdp-wired'

export const Row = oneOf('terminal', 'skip', 'held', 'run')
export const V = oneOf('done', 'gated', 'stalled', 'error')

export type Variant = 'shipped' | 'skip-resets' | 'no-stop'
export const VARIANTS: Variant[] = ['skip-resets', 'no-stop']

export function queueNight(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'queue-night' : `queue-night/${variant}`)
    .params({max: nat, maxTotal: nat})
    .inputs({row: Row, v: V, calls: nat})
    .state({stopped: bool.from(false), consec: 0, attempts: 0, total: 0, launched: bool.from(false)})
    .flags(({row, v, calls, max, maxTotal, stopped, consec, attempts, total}) => {
      const runs = stopped.not().and(row.is('run'))
      const fails = v.is('error').or(v.is('stalled'))
      const total1 = total.plus(calls)
      const consec1 = when(fails, consec.plus(1), 0)
      const ceiling = maxTotal.atLeast(1).and(total1.atLeast(maxTotal))
      const streak = variant === 'no-stop' ? no : consec1.atLeast(2)
      const capped = max.atLeast(1).and(attempts.plus(1).atLeast(max))
      // A skipped row must not reset the streak (L1161-1164): an attacker could otherwise interleave skippable rows.
      const skipResets = variant === 'skip-resets' ? stopped.not().and(row.is('skip')) : no
      return {runs, fails, ceiling, streak, capped, skipResets}
    })
    .step(({calls, stopped, consec, attempts, total, maxTotal, runs, fails, ceiling, streak, capped, skipResets}) => ({
      launched: runs,
      attempts: when(runs, attempts.plus(1), attempts),
      total: when(runs.and(maxTotal.atLeast(1)), total.plus(calls), total),
      // The ceiling check returns before the streak is counted (L1157-1158).
      consec: when(runs.and(ceiling.not()), when(fails, consec.plus(1), 0), when(skipResets, 0, consec)),
      stopped: stopped.or(runs.and(ceiling.or(streak).or(capped))),
    }))
}

export type NightRule = ReturnType<typeof queueNight>

export function laws(r: NightRule) {
  return {
    laws: [
      r.law('a night that has not stopped never carries two failures in a row', ({stopped, consec}) => stopped.or(consec.atMost(1))),
      r.law('a night never launches more rows than --max-megas', ({max, attempts}) => max.atLeast(1).implies(attempts.atMost(max))),
      r.law('a night still going has a launch left under --max-megas', ({max, attempts, stopped}) => stopped.not().and(max.atLeast(1)).implies(attempts.lt(max))),
    ],
    stepLaws: [
      r.stepLaw('a stopped night opens no window', (b, a) => a.launched.not(), (b) => b.stopped),
      r.stepLaw('two consecutive error or stalled rows stop the night', (b, a) => a.stopped,
        (b) => b.row.is('run').and(b.v.is('error').or(b.v.is('stalled'))).and(b.consec.eq(1))),
      r.stepLaw('a skipped, held or already-terminal row never moves the failure streak', (b, a) => a.consec.eq(b.consec),
        (b) => b.row.is('run').not()),
      r.stepLaw('a done or gated row resets the failure streak', (b, a) => a.consec.eq(0),
        (b) => b.stopped.not().and(b.row.is('run')).and(b.ceiling.not()).and(b.v.is('done').or(b.v.is('gated')))),
      r.stepLaw('only a launched row counts toward --max-megas', (b, a) => a.attempts.eq(b.attempts), (b) => b.row.is('run').not()),
    ],
  }
}
