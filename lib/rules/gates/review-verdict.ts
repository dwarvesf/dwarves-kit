// The review-verdict rule of the ship-gate (lib/gate/ship-rules.sh:ship_rule_review_verdict), as three pieces:
//
//  specVerdict  a rule over the spec's lines: _sr_review_last_verdict's awk (ship-rules.sh), a line machine with a
//               code-fence flag, an "inside a `## Review` section" flag and the last canonical verdict seen.
//  ledgerVerdict a rule over the run ledger's rows: gate-ledger.sh:review_verdict (:627), the last verdict a
//               `GATE | review | ran` row's reason starts with.
//  reviewGate   the decision (ship_rule_review_verdict): block (return 2) or pass, from the spec verdict, the
//               ledger verdict and the switch.
import {bool, fun, oneOf, rule, when} from 'gdp-wired'

export const VERDICTS = ['none', 'SHIP', 'FIX', 'DNS'] as const   // FIX = FIX THEN SHIP, DNS = DO NOT SHIP
export const Verdict = oneOf(...VERDICTS)

// ---- the spec's lines ------------------------------------------------------------------------------------------
// A line, classified the way the awk reads it:
//   fence     a ``` or ~~~ opener/closer with 0-3 leading spaces (toggles the fence)
//   review    `## Review` exactly (enters a review section);  heading  any other `# ` or `## ` heading (leaves it)
//   verdict   a canonical `Verdict:` line (### / ** / up to 3 spaces of indent) with a value word in `word`
//   indented  the same verdict line indented 4+ spaces (indented code: skipped)
//   text      anything else
export const LINES = ['fence', 'review', 'heading', 'verdict', 'indented', 'text'] as const
export const Line = oneOf(...LINES)

export type SpecVariant = 'shipped' | 'no-fence' | 'first-wins' | 'any-section'
export const SPEC_VARIANTS: SpecVariant[] = ['no-fence', 'first-wins', 'any-section']

export function specVerdict(variant: SpecVariant = 'shipped') {
  return rule(variant === 'shipped' ? 'spec-verdict' : `spec-verdict/${variant}`)
    // word: the value after `Verdict:`; none = a non-ship word (SECURE, SOLID)
    .inputs({line: Line, word: Verdict})
    .state({fence: bool.from(false), inrev: bool.from(false), v: Verdict.from('none')})
    .step(({line, word, fence, inrev, v}) => {
      const fenced = variant === 'no-fence' ? fence.and(fence.not()) : fence
      const counts = fenced.not().and(line.is('verdict')).and(variant === 'any-section' ? inrev.or(inrev.not()) : inrev)
        .and(word.is('none').not())
      const take = variant === 'first-wins' ? counts.and(v.is('none')) : counts
      return {
        fence: when(line.is('fence'), fence.not(), fence),
        inrev: fenced.not().and(line.is('review')).or(fenced.or(line.is('heading').not()).and(inrev)),
        v: when(take, word, v),
      }
    })
}

export function specLaws(r: ReturnType<typeof specVerdict>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a verdict line inside a code fence never changes the verdict', (b, a) => a.v.eq(b.v),
        (b) => b.fence.and(b.line.is('fence').not())),
      r.stepLaw('a verdict line outside a ## Review section never changes the verdict', (b, a) => a.v.eq(b.v),
        (b) => b.inrev.not()),
      r.stepLaw('the last canonical verdict in a review section wins', (b, a) => a.v.eq(b.word),
        (b) => b.fence.not().and(b.inrev).and(b.line.is('verdict')).and(b.word.is('none').not())),
      r.stepLaw('a non-ship verdict word (SECURE, SOLID) or an indented code line never clears a verdict',
        (b, a) => a.v.eq(b.v), (b) => b.line.is('indented').or(b.line.is('verdict').and(b.word.is('none')))),
    ],
  }
}

// ---- the run ledger's rows -------------------------------------------------------------------------------------
// row: ran = `GATE | review | ran | <reason>` (battery normalizes to review), other = a review row in another state
// (skipped, rejected, override), phase = a GATE row of another phase, marker = an additive line (ACTION, TOKENS...).
// word: what the reason starts with (none = any other text, `SHIP-clean` included).
export const ROWS = ['ran', 'other', 'phase', 'marker'] as const
export const Row = oneOf(...ROWS)

export type LedgerVariant = 'shipped' | 'any-text-clears' | 'any-state'
export const LEDGER_VARIANTS: LedgerVariant[] = ['any-text-clears', 'any-state']

export function ledgerVerdict(variant: LedgerVariant = 'shipped') {
  return rule(variant === 'shipped' ? 'ledger-verdict' : `ledger-verdict/${variant}`)
    .inputs({row: Row, word: Verdict})
    .state({v: Verdict.from('none')})
    .step(({row, word, v}) => {
      const reads = variant === 'any-state' ? row.is('ran').or(row.is('other')) : row.is('ran')
      const take = variant === 'any-text-clears' ? reads : reads.and(word.is('none').not())
      return {v: when(take, word, v)}
    })
}

export function ledgerLaws(r: ReturnType<typeof ledgerVerdict>) {
  return {
    laws: [],
    stepLaws: [
      r.stepLaw('a review record whose reason starts with anything else never clears an earlier verdict',
        (b, a) => a.v.eq(b.v), (b) => b.word.is('none')),
      r.stepLaw('only a review ran row records a verdict', (b, a) => a.v.eq(b.v), (b) => b.row.is('ran').not()),
      r.stepLaw('the last review ran verdict wins', (b, a) => a.v.eq(b.word), (b) => b.row.is('ran').and(b.word.is('none').not())),
    ],
  }
}

// ---- the decision ----------------------------------------------------------------------------------------------
export type GateVariant = 'shipped' | 'spec-only' | 'ship-softens'
export const GATE_VARIANTS: GateVariant[] = ['spec-only', 'ship-softens']

export function reviewGate(variant: GateVariant = 'shipped') {
  return fun(variant === 'shipped' ? 'review-gate' : `review-gate/${variant}`)
    // readable: a spec path that exists and is readable; on: [gate] review_verdict at the merge base (exit 1 = off);
    // ledger: the run ledger script exists; spec: the spec verdict (at head); rec: the ledger's recorded verdict
    .inputs({readable: bool, on: bool, ledger: bool, spec: Verdict, rec: Verdict})
    .returns(({readable, on, ledger, spec, rec}) => {
      const dns = spec.is('DNS')
      const crossChecks = variant === 'spec-only' ? ledger.and(ledger.not()) : ledger
      const mismatch = crossChecks.and(rec.is('none').not()).and(rec.eq(spec).not())
        .and(variant === 'ship-softens' ? rec.eq(rec) : spec.is('none').not().or(rec.is('SHIP').not()))
      return {block: readable.and(on).and(dns.or(mismatch))}
    })
}

export function gateLaws(f: ReturnType<typeof reviewGate>) {
  const live = (e: any) => [e.readable, e.on]
  return [
    f.law('a spec whose last review verdict is DO NOT SHIP refuses the push while the check is on',
      (e) => [...live(e), e.spec.is('DNS')], (o) => o.block),
    f.law('a recorded DO NOT SHIP refuses the push whatever the spec now says',
      (e) => [...live(e), e.ledger, e.rec.is('DNS')], (o) => o.block),
    f.law('a spec verdict that differs from the recorded one refuses the push',
      (e) => [...live(e), e.ledger, e.rec.is('none').not(), e.spec.is('none').not(), e.spec.eq(e.rec).not()], (o) => o.block),
    f.law('a recorded FIX THEN SHIP refuses a spec with no verdict',
      (e) => [...live(e), e.ledger, e.rec.is('FIX'), e.spec.is('none')], (o) => o.block),
    f.law('a recorded SHIP against a spec with no verdict softens nothing and passes',
      (e) => [e.spec.is('none'), e.rec.is('SHIP')], (o) => o.block.not()),
    f.law('a run with no recorded verdict is checked on the spec alone',
      (e) => [e.rec.is('none')], (o, e) => o.block.implies(e.spec.is('DNS'))),
    f.law('the check never blocks when switched off', (e) => [e.on.not()], (o) => o.block.not()),
    f.law('an unreadable or missing spec passes', (e) => [e.readable.not()], (o) => o.block.not()),
  ]
}
