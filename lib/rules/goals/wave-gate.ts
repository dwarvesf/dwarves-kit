// The wavefront admission gate (lib/queue/orchestrate.sh _wave_gate, L654-735), as a gdp-wired rule.
//
// _wave_gate walks the ready set in ROADMAP order and admits greedily. One request is one line of that walk:
//   seed   a still-running wave member passed as a trailing id (rolling admission, L677-681): with a goal file it
//          takes a slot and every candidate must prove disjoint from it; with none it fills the cap
//   cand   a sub-goal of the ROADMAP, in order. `ready` = unchecked with every `depends SG-NN` checked (_ready_set);
//          a sub-goal that is not ready prints nothing. `running` = one of the seeded ids (skipped, L686).
//          `held` = its depends names a member that has not converged (_WAVE_GATE_HOLD, L689-695).
// Touch-sets: `p` is 0..3, a provable directory prefix of goal-registry.ts's universe (lib, lib/a, lib/b, docs);
// 4 = a `## Touches` whose globs dispatch-gate cannot prove (`?`-marked: admitted only alone, overlaps everything);
// 5 = no `## Touches` section (never admitted). `gf` = the sub-goal has a goals/NN-*.md file.
// The decision of the last request is `dec` (none = printed nothing).
import {bool, type Cond, lit, nat, oneOf, rule, when, yes} from 'gdp-wired'
import {ovl} from './goal-registry.ts'

export const Policy = oneOf('auto', 'gate', 'gate!')
export const DEC = ['none', 'run', 'defer'] as const
export const Dec = oneOf(...DEC)
const sel = (c: Cond, a: Cond, b: Cond) => c.and(a).or(c.not().and(b))

export type Variant = 'shipped' | 'no-self-touches' | 'gate-admitted' | 'no-disjoint'
export const VARIANTS: Variant[] = ['no-self-touches', 'gate-admitted', 'no-disjoint']

export function waveGate(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'wave-gate' : `wave-gate/${variant}`)
    .params({cap: nat})
    .inputs({op: oneOf('seed', 'cand'), p: nat, gf: bool, pol: Policy, ready: bool, running: bool, held: bool})
    .assume(({p}) => p.atMost(5))
    .state({o0: bool.from(false), o1: bool.from(false), o2: bool.from(false), o3: bool.from(false),
      opaque: bool.from(false), n: 0, dec: Dec.from('none')})
    .flags(({op, p, gf, pol, ready, running, held, cap, o0, o1, o2, o3, opaque, n}) => {
      const seeds = op.is('seed')
      const listed = op.is('cand').and(ready).and(running.not())
      // (a) its own Touches (L703: a goal file whose `touches` prints something), (b) room, (c) disjoint from all.
      const ownTouches = variant === 'no-self-touches' ? yes : gf.and(p.lt(5))
      const clash = (k: number, o: Cond) => o.and(ovl(p, lit(k)))
      const disjoint = variant === 'no-disjoint' ? yes
        : opaque.not().and(p.eq(4).implies(n.eq(0))).and(clash(0, o0).or(clash(1, o1)).or(clash(2, o2)).or(clash(3, o3)).not())
      const autoOnly = variant === 'gate-admitted' ? yes : pol.is('auto')
      const admits = listed.and(held.not()).and(autoOnly).and(ownTouches).and(n.lt(cap)).and(disjoint)
      return {seeds, listed, admits, seedOpaque: seeds.and(gf).and(p.atLeast(4))}
    })
    .step(({p, gf, cap, o0, o1, o2, o3, opaque, n, dec, seeds, listed, admits, seedOpaque}) => {
      const takes = admits.or(seeds.and(gf))
      const occ = (k: number, o: Cond) => sel(takes.and(p.eq(k)), yes, o)
      return {
        o0: occ(0, o0), o1: occ(1, o1), o2: occ(2, o2), o3: occ(3, o3),
        opaque: sel(seedOpaque.or(admits.and(p.eq(4))), yes, opaque),
        n: when(seeds.and(gf.not()), cap, when(takes, n.plus(1), n)),
        dec: when(seeds.or(listed.not()), dec.of('none'), when(admits, dec.of('run'), dec.of('defer'))),
      }
    })
}

export type WaveGateRule = ReturnType<typeof waveGate>

export function laws(r: WaveGateRule) {
  const ran = (a: any) => a.dec.is('run')
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a sub-goal is admitted only into a free slot under WAVE_CAP', (b, a) => ran(a).implies(b.n.lt(b.cap))),
      r.stepLaw('a sub-goal is admitted only when provably disjoint from every member already in the wave', (b, a) => ran(a).implies(
        b.opaque.not().and(b.p.lt(4).or(b.n.eq(0)))
          .and(b.o0.and(ovl(b.p, lit(0))).not()).and(b.o1.and(ovl(b.p, lit(1))).not())
          .and(b.o2.and(ovl(b.p, lit(2))).not()).and(b.o3.and(ovl(b.p, lit(3))).not()))),
      r.stepLaw('a gate or gate! sub-goal is never admitted to a wave', (b, a) => ran(a).not(), (b) => b.pol.is('auto').not()),
      r.stepLaw('a checked or dep-blocked sub-goal is never admitted', (b, a) => ran(a).not(), (b) => b.ready.not()),
      r.stepLaw('a sub-goal without its own ## Touches is never admitted', (b, a) => ran(a).not(), (b) => b.gf.not().or(b.p.eq(5))),
      r.stepLaw('a sub-goal whose dependency has not converged is never admitted', (b, a) => ran(a).not(), (b) => b.held),
      r.stepLaw('a running member is never admitted again', (b, a) => ran(a).not(), (b) => b.running),
    ],
  }
}
