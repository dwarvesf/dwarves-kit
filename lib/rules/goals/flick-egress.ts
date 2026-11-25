// flick's egress decision for one question (lib/decide/flick.sh main L651-701: the config gates, guard_ok L206-231,
// word_gate_apply L246-292), as a gdp-wired decision: does this question's candidate leave the host?
// Inputs:
//   backendOn   [decide] backend is jev or clef (none fails the whole call; openai is unsupported)
//   pointOn     the point (wrap-7b) is listed in [decide] points
//   denySet     [decide] deny_words names at least one word (an empty list sends nothing)
//   candShape   the candidate is a slug ^[a-z0-9-]{3,40}$;  hitShape: the hit is ^[A-Za-z0-9._-]{1,64}$
//   denyHit     a deny word is a (case-folded) substring of the candidate
//   hitPublic   the hit is a kit-public name (bin/, commands/, agents/, skills/, or allow_names), whole-name equal
//   gateOn      [decide] word_gate is not exactly "off";  dictOk: the dictionary is an absolute, readable file < 16 MB
//   n           the candidate's hyphen segments (0 for "---"); s1..s3 the class of each (only the first n count):
//               dev (a built-in dev word) or pub (a kit-public name) pass outright; word = a dictionary word of 3+
//               letters; short = an unknown segment under 3 letters (never looked up, so never passes); none = unknown
import {bool, type Cond, fun, nat, no, oneOf, when, yes} from 'gdp-wired'

export const SEG = ['dev', 'pub', 'word', 'short', 'none'] as const
export const Seg = oneOf(...SEG)

export type Variant = 'shipped' | 'short-passes' | 'no-dict-open' | 'deny-unchecked'
export const VARIANTS: Variant[] = ['short-passes', 'no-dict-open', 'deny-unchecked']

export function flickEgress(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'flick-egress' : `flick-egress/${variant}`)
    .inputs({backendOn: bool, pointOn: bool, denySet: bool, candShape: bool, hitShape: bool, denyHit: bool, hitPublic: bool,
      gateOn: bool, dictOk: bool, n: nat, s1: Seg, s2: Seg, s3: Seg})
    .returns(({backendOn, pointOn, denySet, candShape, hitShape, denyHit, hitPublic, gateOn, dictOk, n, s1, s2, s3}) => {
      const deny = variant === 'deny-unchecked' ? no : denyHit
      const guard = candShape.and(hitShape).and(deny.not()).and(hitPublic)
      const segOk = (s: typeof s1) => s.is('dev').or(s.is('pub')).or(s.is('word')).or(variant === 'short-passes' ? s.is('short') : no)
      const words: Cond = n.atLeast(1).and(n.atMost(3))
        .and(n.atLeast(1).implies(segOk(s1))).and(n.atLeast(2).implies(segOk(s2))).and(n.atLeast(3).implies(segOk(s3)))
      const dict = variant === 'no-dict-open' ? yes : dictOk
      const wordGate = gateOn.not().or(dict.and(words))
      const sends = backendOn.and(pointOn).and(denySet).and(guard).and(wordGate)
      return {sends: when(sends, 1, 0)}
    })
}

export type EgressFun = ReturnType<typeof flickEgress>

export function laws(f: EgressFun) {
  const none = ({sends}: {sends: any}) => sends.eq(0)
  return [
    f.law('nothing leaves the host with no backend', ({backendOn}) => [backendOn.not()], none),
    f.law('nothing leaves the host for a point not enabled', ({pointOn}) => [pointOn.not()], none),
    f.law('nothing leaves the host while the deny list is empty', ({denySet}) => [denySet.not()], none),
    f.law('a candidate holding a deny word never leaves the host', ({denyHit}) => [denyHit], none),
    f.law('a candidate that is not a plain slug never leaves the host', ({candShape}) => [candShape.not()], none),
    f.law('a question whose hit is not a kit-public name never leaves the host', ({hitPublic}) => [hitPublic.not()], none),
    f.law('with the word gate on and no usable dictionary nothing leaves the host', ({gateOn, dictOk}) => [gateOn, dictOk.not()], none),
    f.law('with the word gate on a candidate leaves only if every segment is a dev word, a kit-public name or a dictionary word',
      ({gateOn}) => [gateOn], ({sends}, {n, s1, s2, s3}) => {
        const ok = (s: any) => s.is('dev').or(s.is('pub')).or(s.is('word'))
        return sends.eq(1).implies(n.atLeast(1).and(ok(s1)).and(n.atLeast(2).implies(ok(s2))).and(n.atLeast(3).implies(ok(s3))))
      }),
  ]
}
