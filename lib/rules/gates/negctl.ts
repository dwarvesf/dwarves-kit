// The mechanised negative control (lib/gate/negctl.sh, mutate mode), as a gdp-wired rule: the six-step run is a
// lifecycle whose verdict is the FIRST failure (`fail()` keeps the first reason; negctl.sh:323).
//
// One request is one step's observation, in the script's order (stage = how many steps have been observed):
//   0  the tree is clean (no tracked file modified or staged)          else REFUSED, exit 2, nothing runs
//   1  the test is green before the mutation                           else FAIL: not green before
//   2  the mutation changed a tracked file (beyond the baseline)       else FAIL: changed no tracked file
//   3  the test is RED under the mutation (`ok`), `load` = that RED     else FAIL: stayed green (vacuous);
//      is only a load or compile error (red_load_error)                load and not NEGCTL_ALLOW_LOAD_RED -> FAIL
//   4  restore leaves the tree as the pre-run snapshot, every changed  else FAIL: tree differs / unrestorable
//      tracked path has a HEAD blob
//   5  the test is green after the restore                             else FAIL: not green after restore
// `red` is a ghost: some observation at stage 3 was a real RED.
import {bool, nat, oneOf, rule, when} from 'gdp-wired'

export const VERDICTS = ['pass', 'refused', 'notGreen', 'noChange', 'vacuous', 'loadRed', 'restore', 'notGreenAfter'] as const
export const Verdict = oneOf(...VERDICTS)

export type Variant = 'shipped' | 'last-failure-wins' | 'vacuous-passes' | 'load-red-counts'
export const VARIANTS: Variant[] = ['last-failure-wins', 'vacuous-passes', 'load-red-counts']

export function negctl(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'negctl' : `negctl/${variant}`)
    .params({allowLoad: bool})
    .inputs({ok: bool, load: bool})
    .state({stage: 0, verdict: Verdict.from('pass'), red: bool.from(false)})
    .step(({allowLoad, ok, load, stage, verdict, red}) => {
      const running = stage.lt(6).and(verdict.is('refused').not())
      const at = (k: number) => running.and(stage.eq(k))
      const loadFails = variant === 'load-red-counts' ? load.and(load.not()) : load.and(allowLoad.not())
      const failNow = when(at(1).and(ok.not()), 'notGreen',
        when(at(2).and(ok.not()), 'noChange',
          when(at(3).and(ok.not()).and(variant === 'vacuous-passes' ? ok : ok.not()), 'vacuous',
            when(at(3).and(ok).and(loadFails), 'loadRed',
              when(at(4).and(ok.not()), 'restore',
                when(at(5).and(ok.not()), 'notGreenAfter', verdict))))))
      const keep = variant === 'last-failure-wins' ? failNow.eq(verdict) : verdict.is('pass').not()
      return {
        stage: when(running, stage.plus(1), stage),
        verdict: when(at(0).and(ok.not()), 'refused', when(keep, verdict, failNow)),
        red: red.or(at(3).and(ok).and(loadFails.not())),
      }
    })
}

export function laws(r: ReturnType<typeof negctl>) {
  return {
    laws: [
      r.law('a control past the RED step passes only if the test really went RED under the mutation',
        ({stage, verdict, red}) => stage.atLeast(4).and(verdict.is('pass')).implies(red)),
      r.law('no verdict is reached before the tree check', ({stage, verdict}) => stage.eq(0).implies(verdict.is('pass'))),
      r.law('a refused run never got past the tree check', ({verdict, stage}) => verdict.is('refused').implies(stage.atMost(1))),
    ],
    stepLaws: [
      r.stepLaw('a dirty tree is refused before anything runs', (b, a) => a.verdict.is('refused').and(a.stage.eq(1)),
        (b) => b.stage.eq(0).and(b.ok.not()).and(b.verdict.is('pass'))),
      r.stepLaw('a refused run runs no later step', (b, a) => a.stage.eq(b.stage).and(a.verdict.is('refused')), (b) => b.verdict.is('refused')),
      r.stepLaw('the first failure names the verdict; a later step never overwrites it', (b, a) => a.verdict.eq(b.verdict),
        (b) => b.verdict.is('pass').not()),
      r.stepLaw('a test that stays green under the mutation fails the control (vacuous)', (b, a) => a.verdict.is('pass').not(),
        (b) => b.stage.eq(3).and(b.ok.not())),
      r.stepLaw('a RED that is only a load or compile error fails the control unless NEGCTL_ALLOW_LOAD_RED=1',
        (b, a) => a.verdict.is('pass').not(), (b) => b.stage.eq(3).and(b.ok).and(b.load).and(b.allowLoad.not())),
      r.stepLaw('a failed restore or a red run after it fails the control', (b, a) => a.verdict.is('pass').not(),
        (b) => b.stage.eq(4).or(b.stage.eq(5)).and(b.ok.not()).and(b.verdict.is('refused').not())),
    ],
  }
}
