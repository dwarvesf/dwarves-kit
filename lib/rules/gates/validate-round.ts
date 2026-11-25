// The parallel validation round (lib/gate/gate-ledger.sh:validate_round, :1852; _vr_open, _vr_close,
// _vr_incomplete), as a gdp-wired rule. Round state lives in the run ledger as `| ROUND |` lines; the state here is
// what the verbs read back: the last ROUND line's state (`last`), the voids since the last close or incomplete
// (`voids`, the awk at _vr_close), the validate gate's latest row (`val`) and the exit code of the last call (`rc`).
//
// Requests: open | close (verdict APPROVED or NEEDS-REVISION; `drift` = the spec blob, HEAD, the repo snapshot or the
// ledger tail moved since open) | incomplete; `tok` = the token passed is the last ROUND's.
// A crash between `closing` and the terminal line is not modelled (the resume path is checked by the kit's tests).
import {bool, nat, oneOf, rule, when} from 'gdp-wired'

export const LAST = ['none', 'open', 'close', 'void', 'incomplete'] as const
export const VAL = ['none', 'ran', 'rejected', 'skipped'] as const
export const OPS = ['open', 'close', 'incomplete'] as const
export const Last = oneOf(...LAST)
export const Val = oneOf(...VAL)
export const Op = oneOf(...OPS)

export type Variant = 'shipped' | 'drift-closes' | 'unbounded-voids' | 'double-open'
export const VARIANTS: Variant[] = ['drift-closes', 'unbounded-voids', 'double-open']

export function validateRound(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'validate-round' : `validate-round/${variant}`)
    .inputs({op: Op, tok: bool, drift: bool, approved: bool})
    .state({last: Last.from('none'), voids: 0, val: Val.from('none'), rc: 0})
    .flags(({op, tok, drift, last}) => {
      const opensOk = op.is('open').and(variant === 'double-open' ? last.eq(last) : last.is('open').not())
      const closeable = op.is('close').and(last.is('open')).and(tok)
      const drifted = variant === 'drift-closes' ? closeable.and(drift).and(drift.not()) : closeable.and(drift)
      return {
        opensOk,
        voided: drifted,
        closes: closeable.and(drifted.not()),
        stops: op.is('incomplete').and(tok).and(last.is('open').or(last.is('void'))),
      }
    })
    .step(({approved, last, voids, val, opensOk, voided, closes, stops}) => ({
      last: when(opensOk, 'open', when(voided, 'void', when(closes, 'close', when(stops, 'incomplete', last)))),
      voids: when(voided, voids.plus(1), when(closes.or(stops), 0, voids)),
      val: when(closes.and(approved), 'ran', when(closes, 'rejected', when(stops, 'skipped', val))),
      rc: when(voided, when(variant === 'unbounded-voids' ? voids.gt(voids) : voids.atLeast(1), 3, 2),
        when(opensOk.or(closes).or(stops), 0, 1)),
    }))
}

export function laws(r: ReturnType<typeof validateRound>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a round cannot open while another round is open', (b, a) => a.rc.eq(1).and(a.last.eq(b.last)),
        (b) => b.op.is('open').and(b.last.is('open'))),
      r.stepLaw('validate ran is recorded only by an APPROVED close of a round that did not drift',
        (b, a) => a.val.is('ran').implies(b.val.is('ran').or(b.op.is('close').and(b.approved).and(b.drift.not()).and(b.last.is('open')).and(b.tok)))),
      r.stepLaw('a round whose spec, HEAD, snapshot or ledger moved is voided, never closed',
        (b, a) => a.last.is('void').and(a.val.eq(b.val)), (b) => b.op.is('close').and(b.last.is('open')).and(b.tok).and(b.drift)),
      r.stepLaw('one void per validation: a second void since the last close or incomplete exits 3',
        (b, a) => a.rc.eq(3), (b) => b.op.is('close').and(b.last.is('open')).and(b.tok).and(b.drift).and(b.voids.atLeast(1))),
      r.stepLaw('a first void exits 2', (b, a) => a.rc.eq(2), (b) => b.op.is('close').and(b.last.is('open')).and(b.tok).and(b.drift).and(b.voids.eq(0))),
      r.stepLaw('a token that is not the last round\'s changes nothing', (b, a) => a.last.eq(b.last).and(a.val.eq(b.val)).and(a.rc.eq(1)),
        (b) => b.op.is('open').not().and(b.tok.not())),
      r.stepLaw('a NEEDS-REVISION close records validate rejected, which check() never counts',
        (b, a) => a.val.is('rejected'), (b) => b.op.is('close').and(b.last.is('open')).and(b.tok).and(b.drift.not()).and(b.approved.not())),
    ],
  }
}
