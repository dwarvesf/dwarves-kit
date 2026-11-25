// batch-debt-warn (hooks/batch-debt-warn.sh, PreToolUse Bash) as a gdp-wired rule. Advisory: every path exits 0.
//
// State lives in the ledger stream merge-watch/<session>.log (reloaded from disk on every call):
//   :14-15  the command's FIRST line has a segment headed by `gh pr merge`    -> else nothing
//   :19-25  the ledger lib resolves and the MERGE line is appended            -> else nothing
//   :28     a WARNED line already in the stream                               -> nothing (one warn per session)
//   :29     fewer than 2 MERGE lines (this one counted)                       -> nothing
//   :30-33  a lane START in runs/*.log stamped after the first MERGE           -> nothing
//   :35-37  else append WARNED and print the warning as additionalContext
import {bool, rule, when} from 'gdp-wired'

export type Variant = 'shipped' | 'warns-every-merge' | 'warns-first-merge'
export const VARIANTS: Variant[] = ['warns-every-merge', 'warns-first-merge']

export function batchDebtWarn(v: Variant = 'shipped') {
  return rule(v === 'shipped' ? 'batch-debt-warn' : `batch-debt-warn/${v}`)
    .inputs({merge: bool, ledger: bool, started: bool})
    .state({merges: 0, warned: bool.from(false), warns: 0, last: bool.from(false)})
    .flags(({merge, ledger, started, merges, warned}) => {
      const counted = merge.and(ledger)
      const enough = v === 'warns-first-merge' ? merges.plus(1).atLeast(1) : merges.plus(1).atLeast(2)
      const once = v === 'warns-every-merge' ? counted : warned.not()
      return {counted, warn: counted.and(once).and(enough).and(started.not())}
    })
    .step(({counted, warn, merges, warned, warns}) => ({
      merges: when(counted, merges.plus(1), merges),
      warned: warned.or(warn),
      warns: when(warn, warns.plus(1), warns),
      last: warn,
    }))
}

export function laws(r: ReturnType<typeof batchDebtWarn>) {
  return {
    laws: [
      r.law('a session is warned at most once', ({warns}) => warns.atMost(1)),
      r.law('the WARNED mark is down exactly when a warning was given', ({warned, warns}) => warned.implies(warns.eq(1)).and(warned.not().implies(warns.eq(0)))),
    ],
    stepLaws: [
      r.stepLaw('a warning comes only on a second or later merge with no lane START since the first',
        (b, a) => a.last.implies(b.merge.and(b.merges.atLeast(1)).and(b.started.not()))),
      r.stepLaw('a command that is not a merge changes nothing', (b, a) => a.merges.eq(b.merges).and(a.warns.eq(b.warns)), (b) => b.merge.not()),
    ],
  }
}
export const make = batchDebtWarn
