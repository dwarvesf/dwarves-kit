// What one cycle of the mega-goal driver does next (lib/queue/orchestrate.sh cmd_run's loop body, L3166-3330), as a
// gdp-wired decision. The inputs are what the cycle reads off the ROADMAP, the goal files and `gh`:
//   cap2        WAVE_CAP >= 2 (the wave block runs at all)
//   bang        a ready `gate!` sub-goal exists (L3194); bangHeld: its PR is already open
//   admitted    how many ready sub-goals _wave_gate admits (0, 1, or 2 meaning two or more)
//   pol         the serial pick's policy: the first unchecked sub-goal (_next), whatever its deps
//   pickReady   the pick is in the ready set (every `depends` checked)
//   pickHeld    the pick is a gate/gate! whose PR is already open (_sg_pr_url), i.e. it waits on a human merge
// The answer `act` is one of ACT. `dispatch-other` is the first ready auto sub-goal _wave_gate admitted.
import {bool, fun, nat, no, oneOf, type Cond, when} from 'gdp-wired'

export const ACT = ['wave', 'dispatch-pick', 'dispatch-bang', 'dispatch-other', 'halt', 'stop'] as const
const A = (a: typeof ACT[number]) => ACT.indexOf(a)
export const Pol = oneOf('auto', 'gate', 'gate!')

// 'redispatch' is cmd_run as it was found: a held gate was dispatched again on every re-run, and a held chain-stop
// gate picked first left a ready independent sub-goal waiting behind it (FINDINGS.md F5).
export type Variant = 'shipped' | 'redispatch' | 'gate-in-wave'
export const VARIANTS: Variant[] = ['redispatch', 'gate-in-wave']

export function orchestratePick(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'orchestrate-pick' : `orchestrate-pick/${variant}`)
    .inputs({cap2: bool, bang: bool, bangHeld: bool, admitted: nat, pol: Pol, pickReady: bool, pickHeld: bool, any: bool})
    .returns(({cap2, bang, bangHeld, admitted, pol, pickReady, pickHeld, any}) => {
      const fixed = variant !== 'redispatch'
      const pickIsGate = pol.is('auto').not()
      // The wave never carries a gate: the bug kept as a variant lets one in.
      const waveOk = variant === 'gate-in-wave' ? admitted.atLeast(1) : admitted.atLeast(2)
      const heldStop = (held: Cond) => fixed ? held : no
      return {
        act: when(any.not(), A('stop'),
          when(cap2.and(bang), when(heldStop(bangHeld), A('stop'), A('dispatch-bang')),
            when(cap2.and(waveOk), A('wave'),
              when(cap2.and(pickReady.not()), A('halt'),
                when(heldStop(pickIsGate.and(pickHeld)),
                  // a held chain-stop gate: an independent ready auto sub-goal runs instead; a held gate! stops all
                  when(cap2.and(pol.is('gate')).and(admitted.atLeast(1)), A('dispatch-other'), A('stop')),
                  A('dispatch-pick')))))),
        // the wave gate never admits a gate, so a wave of `admitted` members carries only auto sub-goals
        waveHasGate: when(variant === 'gate-in-wave' ? cap2.and(admitted.eq(1)).and(bang.not()) : no, 1, 0),
      }
    })
}

export type PickFun = ReturnType<typeof orchestratePick>

export function laws(f: PickFun) {
  return [
    f.law('a held gate sub-goal is never dispatched again while its PR waits for the human merge',
      ({pol, pickHeld, cap2, bang, admitted, pickReady}) => [pol.is('auto').not(), pickHeld, cap2.and(bang).not(), cap2.and(admitted.atLeast(2)).not(), cap2.not().or(pickReady)],
      ({act}) => act.eq(A('dispatch-pick')).not()),
    f.law('a held gate! sub-goal is never dispatched again while its PR waits for the human merge',
      ({cap2, bang, bangHeld}) => [cap2, bang, bangHeld], ({act}) => act.eq(A('dispatch-bang')).not()),
    f.law('a held chain-stop gate never blocks a ready independent sub-goal',
      ({pol, pickHeld, cap2, bang, admitted, pickReady, any}) => [any, pol.is('gate'), pickHeld, cap2, bang.not(), admitted.atLeast(1), pickReady],
      ({act}) => act.eq(A('dispatch-other')).or(act.eq(A('wave')))),
    f.law('a ready gate! halts everything else: nothing is dispatched or waved beside it',
      ({cap2, bang, any}) => [any, cap2, bang], ({act}) => act.eq(A('dispatch-bang')).or(act.eq(A('stop')))),
    f.law('a dep-blocked pick is never dispatched on the wave path', ({cap2, pickReady, bang, admitted, any}) => [any, cap2, pickReady.not(), bang.not(), admitted.lt(2)],
      ({act}) => act.eq(A('halt'))),
    f.law('a wave never carries a gate sub-goal', () => [], ({waveHasGate}) => waveHasGate.eq(0)),
  ]
}
