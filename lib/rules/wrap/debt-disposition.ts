// The debt paydown reader (lib/reflect/weekend-batch.sh:_disposition 155-172, _collectible_files 174-194,
// cmd_mark_paid 298-326) over the append-only `| DEBT |` lines of one rid, as written by lib/gate/gate-ledger.sh
// (debt: a FAT line with significance/worthiness/verdict and maybe a response, `wave` normalized to log/accept;
// debt-response: a line with the response, carrying the verdict of the last line that has one, else a THIN
// response-only line).
// The disposition is read off the LAST line only:
//   verdict=not-significant -> not-significant | response engage -> paid | accept -> accepted | defer -> deferred
//   | verdict log -> logged | tap -> pending | else unknown.   Collected: logged, accepted, deferred.
// Requests: fat (a classifier record, verdict v, response r), thin (a human response r), markPaid (weekend-batch
// mark-paid: refused when the rid has no debt line, else debt-response engage).
import {bool, oneOf, rule, when} from 'gdp-wired'

export const VERDICTS = ['log', 'wave', 'tap', 'notsig'] as const
export const RESPONSES = ['none', 'engage', 'accept', 'wave', 'defer'] as const
const V = oneOf('none', 'log', 'tap', 'notsig')
const R = oneOf('none', 'engage', 'accept', 'defer')

export type Variant = 'shipped' | 'engage-ignored'
export const VARIANTS: Variant[] = ['engage-ignored']

export function debtDisposition(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'debt-disposition' : `debt-disposition/${variant}`)
    .inputs({op: oneOf('fat', 'thin', 'markPaid'), v: oneOf(...VERDICTS), r: oneOf(...RESPONSES)})
    .state({has: bool.from(false), lastV: V.from('none'), lastR: R.from('none'), fatV: V.from('none'), paidOnce: bool.from(false)})
    .step(({op, v, r, has, lastV, lastR, fatV, paidOnce}) => {
      const fat = op.is('fat')
      // a thin line must carry a response: `none` is refused by debt-response (exit 64), so it writes nothing
      const thin = op.is('thin').and(r.is('none').not())
      const pay = op.is('markPaid').and(has)
      const writes = fat.or(thin).or(pay)
      // the verdict on the written line: a fat line's own (wave read as log), else the last fat line's (forward-carry)
      const newV = when(fat.and(v.is('wave').or(v.is('log'))), 'log', when(fat.and(v.is('tap')), 'tap', when(fat, 'notsig', fatV)))
      // the response on the written line (wave read as accept); mark-paid writes engage
      const newR = when(pay.or(writes.and(r.is('engage'))), 'engage', when(writes.and(r.is('wave').or(r.is('accept'))), 'accept',
        when(writes.and(r.is('defer')), 'defer', when(writes, 'none', lastR))))
      return {
        has: has.or(writes),
        lastV: when(writes, newV, lastV),
        lastR: newR,
        fatV: when(fat, newV, fatV),
        paidOnce: paidOnce.or(writes.and(newR.is('engage'))),
      }
    })
}

// The disposition of the last line, as the reader computes it.
export function dispositionOf(s: {has: boolean, lastV: string, lastR: string}, variant: Variant = 'shipped') {
  if (!s.has) return 'none'
  if (s.lastV === 'notsig') return 'not-significant'
  if (s.lastR === 'engage' && variant !== 'engage-ignored') return 'paid'
  if (s.lastR === 'accept') return 'accepted'
  if (s.lastR === 'defer') return 'deferred'
  if (s.lastV === 'log') return 'logged'
  if (s.lastV === 'tap') return 'pending'
  return 'unknown'
}

export function laws(r: ReturnType<typeof debtDisposition>, variant: Variant = String((r as {name?: string}).name ?? '').endsWith('/engage-ignored') ? 'engage-ignored' : 'shipped') {
  const collectible = (x: any) => x.has.and(x.lastV.is('notsig').not()).and(
    (variant === 'engage-ignored' ? x.lastR.is('none').or(x.lastR.is('engage')) : x.lastR.is('none')).and(x.lastV.is('log'))
      .or(x.lastR.is('accept')).or(x.lastR.is('defer')))
  return {
    laws: [
      // The header: "response=engage (any verdict) -> PAID, never re-collected". REFUTED: a later classifier line
      // (a re-ship of the same rid) or a later defer/accept response re-opens it, because only the last line counts.
      r.law('a paid item is never collected again', (s) => s.paidOnce.implies(collectible(s).not())),
    ],
    stepLaws: [
      r.stepLaw('mark-paid closes any item that has a debt line', (_b, a) => collectible(a).not(),
        (b) => b.op.is('markPaid').and(b.has)),
      r.stepLaw('mark-paid on a rid with no debt line writes nothing', (b, a) => a.has.implies(b.has),
        (b) => b.op.is('markPaid')),
      r.stepLaw('an open tap is pending, never collected', (_b, a) => collectible(a).not(),
        (b) => b.op.is('fat').and(b.v.is('tap')).and(b.r.is('none'))),
      r.stepLaw('a not-significant verdict is never collected', (_b, a) => collectible(a).not(),
        (b) => b.op.is('fat').and(b.v.is('notsig'))),
      r.stepLaw('a legacy wave verdict reads as log, collected', (_b, a) => collectible(a),
        (b) => b.op.is('fat').and(b.v.is('wave')).and(b.r.is('none'))),
    ],
  }
}
