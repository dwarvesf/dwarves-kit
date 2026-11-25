// The bounded-loop resume (lib/loop/ql-verdict.sh resume) as a gdp-wired rule: each request is one
// [[QL-VERDICT round=N clean=BOOL findings=K]] marker, in file order.
//
//   :38-46  a marker outside the grammar is a loud error (exit 65) and nothing is resumed. Fixed: clean=true with
//           findings > 0 is outside the grammar too (every loop defines clean as no findings left: gauntlet.md,
//           test-plan-review-team.md, ui-design.md's two-sided stop); 'pre-fix' counted it as a clean round.
//   :49-55  next round = 1 + the highest round seen; clean_streak = clean markers since the last dirty one;
//           last_findings = the last marker's K.
// The markers live in a spec or a record on disk, so the laws are proven from any state.
import {bool, nat, rule, when} from 'gdp-wired'

export type Variant = 'shipped' | 'pre-fix' | 'streak-survives-dirty'
export const VARIANTS: Variant[] = ['pre-fix', 'streak-survives-dirty']

export function qlVerdict(v: Variant = 'shipped') {
  return rule(v === 'shipped' ? 'ql-verdict' : `ql-verdict/${v}`)
    .inputs({round: nat, clean: bool, findings: nat})
    .state({max: 0, streak: 0, last: 0, error: bool.from(false), dirtyStreak: 0})
    .flags(({clean, findings}) => ({bad: v === 'pre-fix' ? clean.and(clean.not()) : clean.and(findings.gt(0))}))
    .step(({round, clean, findings, max, streak, last, error, dirtyStreak, bad}) => {
      const ok = bad.not()
      return {
        max: when(ok.and(round.gt(max)), round, max),
        streak: when(ok, when(clean, streak.plus(1), v === 'streak-survives-dirty' ? streak : 0), streak),
        last: when(ok, findings, last),
        error: error.or(bad),
        // how many of the streak's rounds carried findings (the false quiescence the law rules out)
        dirtyStreak: when(ok, when(clean, when(findings.gt(0), dirtyStreak.plus(1), dirtyStreak), 0), dirtyStreak),
      }
    })
}
export const make = qlVerdict

export function laws(r: ReturnType<typeof qlVerdict>) {
  return {
    laws: [
      r.law('no round in the clean streak carried findings', ({dirtyStreak}) => dirtyStreak.eq(0)),
    ],
    stepLaws: [
      r.stepLaw('a dirty round resets the clean streak', (b, a) => a.streak.eq(0), (b) => b.clean.not()),
      r.stepLaw('a clean round with no findings extends the streak by one', (b, a) => a.streak.eq(b.streak.plus(1)), (b) => b.clean.and(b.findings.eq(0))),
      r.stepLaw('the next round is after every round seen', (b, a) => a.max.atLeast(b.max).and(a.error.or(a.max.atLeast(b.round)))),
      r.stepLaw('a clean marker that still has findings is an error, never a clean round',
        (b, a) => a.error.and(a.streak.eq(b.streak)), (b) => b.clean.and(b.findings.gt(0))),
    ],
  }
}
