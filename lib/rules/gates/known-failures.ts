// The tiered mega-goal's known-failure classifier (lib/gate/known-failures.sh:cmd_classify), a gdp-wired decision.
//
// Facts: the run log exists; the --exit value (zero, non-zero, absent, not a number: absent and garbage read as 1);
// the base's [test] failure_line and count_line are set; the failure names parsed from the log (none, all on the
// known list, or one that is not); the known list can be read; the executed count parsed (0 = none or zero);
// --prev-count (absent = 0 here, with `prevSet`); --base-count (`baseSet`, `baseOk` a number, `base`).
// Result: pass | known | fail (exit 0, 0, 1) as two flags, pass and known; neither is fail. Order is the script's.
import {bool, fun, nat, oneOf} from 'gdp-wired'

export const EXITS = ['zero', 'nonzero', 'absent', 'garbage'] as const
export const NAMES = ['none', 'known', 'new'] as const
export const Exit = oneOf(...EXITS)
export const Names = oneOf(...NAMES)

export type Variant = 'shipped' | 'crash-masked' | 'count-unchecked' | 'absent-exit-passes'
export const VARIANTS: Variant[] = ['crash-masked', 'count-unchecked', 'absent-exit-passes']

export function knownFailures(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'known-failures' : `known-failures/${variant}`)
    .inputs({log: bool, exit: Exit, failLine: bool, names: Names, listOk: bool, countLine: bool, count: nat,
      prevSet: bool, prev: nat, baseSet: bool, baseOk: bool, base: nat})
    .returns(({log, exit, failLine, names, listOk, countLine, count, prevSet, prev, baseSet, baseOk, base}) => {
      const zero = variant === 'absent-exit-passes' ? exit.is('zero').or(exit.is('absent')) : exit.is('zero')
      const namesOk = variant === 'crash-masked' ? names.is('new').not() : names.is('known')
      const countOk = variant === 'count-unchecked' ? countLine.or(countLine.not())
        : countLine.and(count.gt(0)).and(prevSet.not().or(count.atLeast(prev))).and(baseSet.not().or(baseOk.and(count.atLeast(base))))
      const known = failLine.and(namesOk).and(listOk).and(countOk)
      // pass and known exit 0; neither = fail (exit 1)
      return {pass: log.and(zero), known: log.and(zero.not()).and(known)}
    })
}

export function laws(f: ReturnType<typeof knownFailures>) {
  return [
    f.law('a zero exit passes', (e) => [e.log, e.exit.is('zero')], (o) => o.pass),
    f.law('a caller that forgets --exit never gets pass', (e) => [e.exit.is('absent').or(e.exit.is('garbage'))], (o) => o.pass.not()),
    f.law('a red run with no parsed failure is never known (a crash is never masked)', (e) => [e.exit.is('zero').not(), e.names.is('none')], (o) => o.pass.not().and(o.known.not())),
    f.law('a new failure is never known', (e) => [e.exit.is('zero').not(), e.names.is('new')], (o) => o.pass.not().and(o.known.not())),
    f.law('known needs a non-zero executed count', (e) => [e.count.eq(0)], (o) => o.known.not()),
    f.law('an executed count below the previous count is never known', (e) => [e.prevSet, e.count.lt(e.prev)], (o) => o.known.not()),
    f.law('a base count that cannot be read never proves known', (e) => [e.baseSet, e.baseOk.not()], (o) => o.known.not()),
    f.law('an executed count below the base run never proves known', (e) => [e.baseSet, e.count.lt(e.base)], (o) => o.known.not()),
    f.law('with no failure_line at the base a red run is a plain failure', (e) => [e.exit.is('zero').not(), e.failLine.not()], (o) => o.pass.not().and(o.known.not())),
    f.law('no run log is a failure', (e) => [e.log.not()], (o) => o.pass.not().and(o.known.not())),
  ]
}
