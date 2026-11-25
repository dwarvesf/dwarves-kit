// The end-verifier recheck sampler (lib/gate/recheck-sample.sh:decide), as a gdp-wired decision.
//
// Facts: the N argument (`given`, its digits `arg`, whether it is all digits `argDigits`), the root-only config
// value (`cfg`, `cfgDigits`) read when no N is given, the rid's cksum (`sum`, opaque: the bridge feeds the real one),
// and `lead0`: the digits start with a 0 (08, 010). The result is `sampled` (else skipped); `n` is the N in force.
// Before the fix the digits went into $(( )) as written, so a leading 0 read as octal: 010 was 8 and 08 an
// arithmetic error that printed no decision and exited 1.
import {bool, fn, fun, nat, when} from 'gdp-wired'

export type Variant = 'shipped' | 'octal'
export const VARIANTS: Variant[] = ['octal']

// sum mod n, n > 1 here; oct(d) = the value bash's $(( )) gives digits with a leading 0, unknown to the kernel.
const mod = fn(2, (a: number, b: number) => (b === 0 ? 0 : a % b))
const oct = fn(1, (d: number) => parseInt(String(d), 8) || 0)

export function recheckSample(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'recheck-sample' : `recheck-sample/${variant}`)
    .fns({mod, oct})
    .inputs({given: bool, arg: nat, argDigits: bool, cfg: nat, cfgDigits: bool, sum: nat, lead0: bool, octalOk: bool})
    .returns(({given, arg, argDigits, cfg, cfgDigits, sum, lead0, octalOk, mod, oct}) => {
      const digits = when(given, when(argDigits, arg, 5), when(cfgDigits, cfg, 5))
      const isDigits = when(given, when(argDigits, 1, 0), when(cfgDigits, 1, 0)).eq(1)
      // the octal variant: a leading-zero N is oct(N); octalOk = the digits are valid octal (no 8 or 9)
      const octal = variant === 'octal' ? isDigits.and(lead0) : isDigits.and(isDigits.not())
      const n = when(octal, oct(digits), digits)
      const sampled = n.eq(1).or(n.gt(1).and(mod(sum, n).eq(0)))
      return {decided: octal.and(octalOk.not()).not(), sampled, n}
    })
}

export function laws(f: ReturnType<typeof recheckSample>) {
  return [
    f.law('N=0 never samples', (e) => [e.given, e.argDigits, e.arg.eq(0)], (o) => o.sampled.not()),
    f.law('N=1 samples every run', (e) => [e.given, e.argDigits, e.arg.eq(1)], (o) => o.sampled),
    f.law('a non-numeric N falls back to 5', (e) => [e.given, e.argDigits.not()], (o) => o.n.eq(5)),
    f.law('with no N the root config value decides', (e) => [e.given.not(), e.cfgDigits], (o, e) => o.n.eq(e.cfg)),
    f.law('the N in force is the digits read as decimal, a leading 0 included', (e) => [e.given, e.argDigits],
      (o, e) => o.n.eq(e.arg)),
    f.law('every call with a rid prints a decision and exits 0', () => [], (o) => o.decided),
  ]
}
