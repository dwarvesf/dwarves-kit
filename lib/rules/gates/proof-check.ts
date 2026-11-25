// The proof-of-done gate's verdict (lib/gate/proof-ledger.sh:check, :600), as a gdp-wired decision over the facts
// check() reads from the branch: the diff's class (classify), whether a NEGATIVE CONTROL is owed
// (_negctl_required), the markers in the one fresh proof file (_fresh_proof_files), whether an override is logged for
// this repo and slug (is_overridden) and whether the diff changes source files outside a sanctioned deploy/ path.
// One flat proof file is modelled (the per-file pass); the set-wise group pass is the same test on a union of files.
// [proof] visual is off (the image rule is dead code then).
//
// File facts, as check() greps them:
//   out      captured output under an Output: slot (or a committed image)          _has_captured_output
//   green    a green marker: Exit: 0, a last Verdict: PASS, a PASS table cell        _green_marks
//   negctl   the text NEGATIVE CONTROL;  lastBad  the last Verdict: line is FAIL or INCONCLUSIVE
//   rollback the text rollback or [UNAVAILABLE;  unavail  the text [UNAVAILABLE;  cmd  a Command: or Exit: line
import {bool, fun, oneOf} from 'gdp-wired'

export const CLASSES = ['inert', 'behavioral', 'stateful'] as const
export const Cls = oneOf(...CLASSES)

export type Variant = 'shipped' | 'override-first' | 'override-excuses-source' | 'verdict-ignored'
export const VARIANTS: Variant[] = ['override-first', 'override-excuses-source', 'verdict-ignored']

export function proofCheck(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'proof-check' : `proof-check/${variant}`)
    .inputs({reachable: bool, cls: Cls, negReq: bool, proof: bool, out: bool, green: bool, negctl: bool, lastBad: bool,
      rollback: bool, unavail: bool, cmd: bool, overridden: bool, src: bool})
    .returns(({reachable, cls, negReq, proof, out, green, negctl, lastBad, rollback, unavail, cmd, overridden, src}) => {
      const lastOk = variant === 'verdict-ignored' ? lastBad.or(lastBad.not()) : lastBad.not()
      const behavOk = cls.is('behavioral').and(proof).and(negReq.not().or(negctl)).and(out).and(green).and(lastOk)
      const statefulOk = cls.is('stateful').and(proof).and(rollback.or(unavail)).and(out.or(unavail)).and(cmd)
      const proved = behavOk.or(statefulOk)
      const excused = variant === 'override-excuses-source' ? overridden : overridden.and(src.not())
      const pass = variant === 'override-first'
        ? reachable.not().or(cls.is('inert')).or(overridden.and(excused)).or(overridden.not().and(proved))
        : reachable.not().or(cls.is('inert')).or(proved).or(excused)
      return {pass}
    })
}

export function laws(f: ReturnType<typeof proofCheck>) {
  return [
    f.law('an inert diff always passes', (e) => [e.cls.is('inert')], (o) => o.pass),
    f.law('a base that is not a commit fails open', (e) => [e.reachable.not()], (o) => o.pass),
    f.law('a real proof always wins over an override', (e) => [e.reachable, e.cls.is('behavioral'), e.proof, e.out, e.green,
      e.negctl, e.lastBad.not()], (o) => o.pass),
    f.law('an override never passes a source change that has no proof of done',
      (e) => [e.reachable, e.cls.is('inert').not(), e.proof.not(), e.src], (o) => o.pass.not()),
    f.law('a behavioral change passes only with a green run whose output was captured, unless an override excuses it',
      (e) => [e.reachable, e.cls.is('behavioral'), e.overridden.not()], (o, e) => o.pass.implies(e.proof.and(e.out).and(e.green))),
    f.law('a behavioral change passes only with a NEGATIVE CONTROL when one is owed',
      (e) => [e.reachable, e.cls.is('behavioral'), e.negReq, e.overridden.not()], (o, e) => o.pass.implies(e.negctl)),
    f.law('a last Verdict of FAIL or INCONCLUSIVE never satisfies a behavioral proof',
      (e) => [e.reachable, e.cls.is('behavioral'), e.lastBad, e.overridden.not()], (o) => o.pass.not()),
    f.law('a stateful change passes only with a rollback note or [UNAVAILABLE]',
      (e) => [e.reachable, e.cls.is('stateful'), e.overridden.not()], (o, e) => o.pass.implies(e.rollback.or(e.unavail))),
  ]
}

// Laws the docs promise or a reviewer asks that the code-faithful rule refutes (FINDINGS.md): kept, and asserted
// refuted with their counterexample, never weakened.
export function refutedLaws(f: ReturnType<typeof proofCheck>) {
  return [
    f.law('a stateful proof that records [UNAVAILABLE: reason] passes (docs/verification/README.md "Honest passes")',
      (e) => [e.reachable, e.cls.is('stateful'), e.proof, e.unavail], (o) => o.pass),
    f.law('a stateful change never ships on a run whose last Verdict is FAIL',
      (e) => [e.reachable, e.cls.is('stateful'), e.lastBad, e.overridden.not()], (o) => o.pass.not()),
  ]
}
