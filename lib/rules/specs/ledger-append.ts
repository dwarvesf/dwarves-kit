// The kit's one append substrate, lib/ledger/ledger.sh `ledger_append <stream> <text...>`, over one stream file.
// Its header promises: one line per append (newlines in the text collapsed, so a value can never forge extra
// lines), append-only (the source of truth), and every stream under the single ledger root.
// Modelled from the code (ledger.sh:ledger_append):
//   - the text's newlines and CRs become spaces, then `printf '%s\n' >> <root>/<stream>`.
//   - FIX 1: when the file's last byte is not a newline (a write torn by a crash or a full disk, or a hand edit),
//     the append used to land on that torn line, changing a record already written (variant 'joins-torn-line').
//     It now ends the torn line first, so the torn record stays as it was and the new record is a line of its own.
//   - FIX 2: a stream with a `..` component resolved outside the root and was written there
//     (variant 'escapes-root'). It is now refused with exit 64, nothing written. 'pre-fix' is the script before both.
// State: `lines` (complete records), `torn` (the file ends inside a line), `changed` (some record already written
// was altered by a later append), `outside` (records written outside the root). Requests: an append, an append to
// an escaping stream, or a torn write by something else.
import {bool, oneOf, rule, when} from 'gdp-wired'
import {iff} from './util.ts'

export type Variant = 'shipped' | 'joins-torn-line' | 'escapes-root' | 'pre-fix'
export const VARIANTS: Variant[] = ['joins-torn-line', 'escapes-root', 'pre-fix']
export const OPS = ['append', 'appendUp', 'tear'] as const

export function ledgerAppend(variant: Variant = 'shipped') {
  return rule(variant === 'shipped' ? 'ledger-append' : `ledger-append/${variant}`)
    .inputs({op: oneOf(...OPS)})
    .state({lines: 0, torn: bool.from(false), changed: bool.from(false), outside: 0, refused: bool.from(false)})
    .step(({op, lines, torn, changed, outside}) => {
      const up = op.is('appendUp')
      const writesHere = op.is('append')
      const writesOutside = variant === 'escapes-root' || variant === 'pre-fix' ? up : up.and(up.not())
      const joins = variant === 'joins-torn-line' || variant === 'pre-fix' ? writesHere.and(torn) : writesHere.and(torn).and(torn.not())
      // shipped: a torn line is closed first (it becomes a record of its own), then the new line is written.
      const closes = writesHere.and(torn).and(joins.not())
      return {
        lines: when(op.is('tear'), lines, when(writesHere, lines.plus(1).plus(when(closes, 1, 0)), lines)),
        torn: op.is('tear').or(writesHere.not().and(torn)),
        changed: changed.or(joins),
        outside: when(writesOutside, outside.plus(1), outside),
        refused: up.and(writesOutside.not()),
      }
    })
}

export function laws(r: ReturnType<typeof ledgerAppend>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('an append never changes a record already written',
        (b, a) => a.changed.not(), (b) => b.changed.not()),
      r.stepLaw('every append leaves the stream ending on a complete line',
        (b, a) => a.torn.not(), (b) => b.op.is('append')),
      r.stepLaw('an append adds its own record (and keeps a torn one as a record of its own)',
        (b, a) => a.lines.eq(b.lines.plus(when(b.torn, 2, 1))), (b) => b.op.is('append')),
      r.stepLaw('a stream outside the ledger root is refused and nothing is written',
        (b, a) => a.outside.eq(b.outside).and(a.lines.eq(b.lines)).and(a.refused).and(iff(a.torn, b.torn)), (b) => b.op.is('appendUp')),
      r.stepLaw('nothing is ever written outside the ledger root', (b, a) => a.outside.eq(b.outside)),
      r.stepLaw('the record count never goes down', (b, a) => a.lines.atLeast(b.lines)),
    ],
  }
}
