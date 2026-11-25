// Two conductors on one queue slug (lib/queue/queue.sh cmd_run, lib/queue/watch-board.sh), as an interleaving rule.
//
// A conductor is one `queue.sh run` process. Two can hold the same slug: overlapping watcher ticks (`--max N` plans
// several rows; a tick that is still on row 1 reaches row 2 after a later tick has planned and launched it), or a
// hand `queue run` beside the watcher. The heartbeat file `<slug>.beat` is the in-flight claim.
//   plan    the watcher's re-pick gate: refused while the beat exists (_guard_skip_reason L188-189)
//   launch  cmd_run reaching _launch_once: `_beat` writes the beat (L631). A hand run (`hand`) launches without a
//           plan. As found, nothing between the plan and the launch looked at the beat again, and a hand run never
//           looked at all; the fix claims the beat atomically in cmd_run (noclobber create) and skips the row when
//           the claim fails.
//   finish  the run ends: _beat_clear (L1124)
//   reap    the watcher reaps a beat past QUEUE_BEAT_DEAD_SECS. Assumed only when no conductor is alive: a beat
//           that old means its conductor is gone (the reaper's own premise; see FINDINGS.md "not modelled").
import {oneOf, rule, when, yes} from 'gdp-wired'

export const PCS = ['idle', 'planned', 'running'] as const
export const Pc = oneOf(...PCS)

// 'unclaimed' is cmd_run as it was found (FINDINGS.md F4).
export type Variant = 'shipped' | 'unclaimed'
export const VARIANTS: Variant[] = ['unclaimed']

export function queueConductors(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'queue-conductors' : `queue-conductors/${variant}`)
    .inputs({who: oneOf('c0', 'c1'), op: oneOf('plan', 'launch', 'finish', 'reap'), hand: oneOf('watcher', 'hand')})
    .state({pc0: Pc.from('idle'), pc1: Pc.from('idle'), beat: oneOf('absent', 'present').from('absent')})
    .assume(({op, pc0, pc1}) => op.is('reap').implies(pc0.is('running').not().and(pc1.is('running').not())))
    .flags(({who, op, hand, pc0, pc1, beat}) => {
      const me = who.is('c0')
      const myPc = (c: typeof PCS[number]) => me.and(pc0.is(c)).or(me.not().and(pc1.is(c)))
      const free = beat.is('absent')
      const plans = op.is('plan').and(myPc('idle')).and(free)
      const ready = myPc('planned').or(hand.is('hand').and(myPc('idle')))
      const claimOk = variant === 'unclaimed' ? yes : free
      return {
        me, plans,
        launches: op.is('launch').and(ready).and(claimOk),
        skips: op.is('launch').and(ready).and(claimOk.not()),
        finishes: op.is('finish').and(myPc('running')),
        reaps: op.is('reap').and(beat.is('present')),
      }
    })
    .step(({me, pc0, pc1, beat, plans, launches, skips, finishes, reaps}) => {
      const next = (pc: typeof pc0) => when(plans, pc.of('planned'), when(launches, pc.of('running'), when(skips.or(finishes), pc.of('idle'), pc)))
      return {
        pc0: when(me, next(pc0), pc0),
        pc1: when(me, pc1, next(pc1)),
        beat: when(launches, beat.of('present'), when(finishes.or(reaps), beat.of('absent'), beat)),
      }
    })
}

export type ConductorRule = ReturnType<typeof queueConductors>

export function laws(r: ConductorRule) {
  return {
    laws: [
      r.law('a slug is never run by two conductors at once', ({pc0, pc1}) => pc0.is('running').and(pc1.is('running')).not()),
      r.law('a running conductor holds the heartbeat', ({pc0, pc1, beat}) => pc0.is('running').or(pc1.is('running')).implies(beat.is('present'))),
    ],
    stepLaws: [
      r.stepLaw('a slug with a live heartbeat is never launched again', (b, a) =>
        (b.me.and(a.pc0.is('running')).or(b.me.not().and(a.pc1.is('running')))).not(),
        (b) => b.op.is('launch').and(b.beat.is('present')).and(b.me.and(b.pc0.is('running')).or(b.me.not().and(b.pc1.is('running'))).not())),
    ],
  }
}
