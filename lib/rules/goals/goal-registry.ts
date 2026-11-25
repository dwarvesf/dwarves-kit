// The cross-session running-goal registry (lib/goal/goal-registry.sh: reg_claim, reg_release), as gdp-wired rules.
//
// goalRegistry: the verbs as the operator sees them, one call at a time. A claim is refused when its globs overlap
// any OTHER active record (_reg_first_collision skips its own slug); otherwise it writes the slug's record, whoever
// wrote it before. A release removes the record.
//
// Touch-sets are abstracted to four directory prefixes whose overlap is the dispatch-gate prefix rule (equal, or one
// an ancestor of the other on segment boundaries):  0 = lib/**, 1 = lib/a/**, 2 = lib/b/**, 3 = docs/**.
// lib overlaps lib/a and lib/b; lib/a and lib/b are disjoint; docs overlaps only itself.
//
// `Owner[s]` is the session (worktree) whose claim wrote the record: the script stores it as `worktree=`.
import {bool, everyKey, forall, nat, oneOf, rule, type Term, when, yes} from 'gdp-wired'

export const GLOBS = ['lib/**', 'lib/a/**', 'lib/b/**', 'docs/**'] as const
export const ovl = (p: Term, q: Term) => p.eq(q).or(p.eq(0).and(q.atLeast(1)).and(q.atMost(2))).or(q.eq(0).and(p.atLeast(1)).and(p.atMost(2)))

// 'shipped' is reg_claim as fixed (a claim on a slug another worktree holds is REFUSED, goal-registry.sh L147-156).
// 'takeover' is the script as it was found: _reg_first_collision skips the slug's own record, so a second session's
// claim on a running slug overwrote that session's record (FINDINGS.md, F1). 'no-gate' is the bug the disjointness
// gate rules out.
export type Variant = 'shipped' | 'takeover' | 'no-gate'
export const VARIANTS: Variant[] = ['takeover', 'no-gate']
export function goalRegistry(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'goal-registry' : `goal-registry/${variant}`)
    .inputs({op: oneOf('claim', 'release'), s: nat, p: nat, sess: nat})
    .assume(({p}) => p.atMost(3))
    .maps({Active: bool.from(false), Reg: 0, Owner: 0})
    .flags(({op, s, p, sess, Active, Reg, Owner}) => {
      const clear = variant === 'no-gate' ? yes
        : everyKey(k => k.eq(s).or(Active.at(k).not()).or(ovl(Reg.at(k), p).not()))
      // The fix: a record another worktree wrote is that session's, so a claim on its slug is refused.
      const mine = variant === 'takeover' ? yes : Active.at(s).not().or(Owner.at(s).eq(sess))
      return {claims: op.is('claim').and(clear).and(mine), releases: op.is('release')}
    })
    .step(({s, p, sess, Active, Reg, Owner, claims, releases}) => ({
      Active: Active.set(s, when(claims, Active.at(s).or(claims), when(releases, Active.at(s).and(releases.not()), Active.at(s)))),
      Reg: Reg.set(s, when(claims, p, Reg.at(s))),
      Owner: Owner.set(s, when(claims, sess, Owner.at(s))),
    }))
}

export type RegistryRule = ReturnType<typeof goalRegistry>

export function laws(r: RegistryRule) {
  return {
    laws: [
      r.law('no two running goals have overlapping touch-sets', ({Active, Reg}) =>
        forall((j, k) => j.eq(k).not().and(Active.at(j)).and(Active.at(k)).implies(ovl(Reg.at(j), Reg.at(k)).not()))),
    ],
    stepLaws: [
      r.stepLaw("a claim never takes over another session's running goal",
        (b, a) => a.Owner.at(b.s).eq(b.Owner.at(b.s)).and(a.Reg.at(b.s).eq(b.Reg.at(b.s))),
        (b) => b.op.is('claim').and(b.Active.at(b.s)).and(b.Owner.at(b.s).eq(b.sess).not())),
      r.stepLaw('a refused claim writes nothing',
        (b, a) => a.Active.at(b.s).iff(b.Active.at(b.s)).and(a.Reg.at(b.s).eq(b.Reg.at(b.s))),
        (b) => b.claims.not().and(b.op.is('claim'))),
      r.stepLaw('a release ends the goal', (b, a) => a.Active.at(b.s).not(), (b) => b.op.is('release')),
    ],
  }
}
