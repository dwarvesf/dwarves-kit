// Two sessions claiming at once (lib/goal/goal-registry.sh: reg_claim), as an interleaving rule.
//
// reg_claim is not atomic. It runs in four steps, and another session's steps can fall between any two:
//   gate     _reg_first_collision over the other records (L159); a collision refuses with nothing written
//   begin    `{ ... } > "$dir/$slug.goal"` truncates and starts the record (L170): a reader that sees the file now
//            finds no `touches=` line, and `_reg_overlap` over an empty list is "no overlap"
//   finish   the record's `touches=` line is written: from here a reader sees the full record
//   reread   the last-writer-loud re-read (L183): a collision now removes the record and refuses "(race)"
// A claimed session may `release` (rm, back to idle).
//
// One request is one step of one session (`who`); `p` is the region a session picks at its gate. Regions are the
// four prefixes of goal-registry.ts (0 lib/**, 1 lib/a/**, 2 lib/b/**, 3 docs/**). The two sessions claim different
// slugs (the same-slug case is the takeover rule in goal-registry.ts).
import {nat, oneOf, rule, when, yes} from 'gdp-wired'
import {ovl} from './goal-registry.ts'

export const PCS = ['idle', 'gated', 'partial', 'written', 'claimed'] as const
export const Pc = oneOf(...PCS)

export type Variant = 'shipped' | 'no-reread'
export const VARIANTS: Variant[] = ['no-reread']

export function registryRace(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'registry-race' : `registry-race/${variant}`)
    .inputs({who: oneOf('s0', 's1'), p: nat})
    .assume(({p}) => p.atMost(3))
    .state({pc0: Pc.from('idle'), pc1: Pc.from('idle'), r0: 0, r1: 0})
    .flags(({who, p, pc0, pc1, r0, r1}) => {
      const me = who.is('s0')
      const myPc = (c: typeof PCS[number]) => me.and(pc0.is(c)).or(me.not().and(pc1.is(c)))
      // A reader sees the other record in full once its touches= line is written.
      const otherFull = me.and(pc1.is('written').or(pc1.is('claimed'))).or(me.not().and(pc0.is('written').or(pc0.is('claimed'))))
      const otherReg = when(me, r1, r0), myReg = when(me, r0, r1)
      const gateClear = otherFull.and(ovl(p, otherReg)).not()
      const rereadClear = variant === 'no-reread' ? yes : otherFull.and(ovl(myReg, otherReg)).not()
      return {
        gates: myPc('idle').and(gateClear),
        begins: myPc('gated'),
        finishes: myPc('partial'),
        claims: myPc('written').and(rereadClear),
        backsOut: myPc('written').and(rereadClear.not()),
        releases: myPc('claimed'),
        me,
      }
    })
    .step(({p, pc0, pc1, r0, r1, me, gates, begins, finishes, claims, backsOut, releases}) => {
      const next = (pc: typeof pc0) => when(gates, pc.of('gated'), when(begins, pc.of('partial'), when(finishes, pc.of('written'),
        when(claims, pc.of('claimed'), when(backsOut.or(releases), pc.of('idle'), pc)))))
      return {
        pc0: when(me, next(pc0), pc0),
        pc1: when(me, pc1, next(pc1)),
        r0: when(me.and(gates), p, r0),
        r1: when(me.not().and(gates), p, r1),
      }
    })
}

export type RaceRule = ReturnType<typeof registryRace>

export function laws(r: RaceRule) {
  return {
    laws: [
      r.law('two sessions never both hold overlapping claims', ({pc0, pc1, r0, r1}) =>
        pc0.is('claimed').and(pc1.is('claimed')).and(ovl(r0, r1)).not()),
    ],
    stepLaws: [
      r.stepLaw('a claim lands only after its re-read found no overlapping record',
        (b, a) => (b.me.and(a.pc0.is('claimed')).or(b.me.not().and(a.pc1.is('claimed')))).implies(
          b.me.and(b.pc0.is('claimed').or(b.pc1.is('written').or(b.pc1.is('claimed')).and(ovl(b.r0, b.r1)).not()))
            .or(b.me.not().and(b.pc1.is('claimed').or(b.pc0.is('written').or(b.pc0.is('claimed')).and(ovl(b.r0, b.r1)).not()))))),
    ],
  }
}
