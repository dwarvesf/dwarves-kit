// The knowledge-intake dedup gate, as lib/intake/intake.sh `gate` decides it:
//   - the exit (intake.sh:cmd_gate): 0 when any store hit, 1 when none. Each store (url ledger, boards, verdicts,
//     owned inventory, notes, open PRs) is either skipped (key unset, command not on PATH, file missing, no
//     searchable word: a `skipped` row, never fatal) or searched; only a searched store can hit.
//   - a board hit's row_kind (intake.sh:_row_kind): `eval` for a measured evaluation, `skim` for a skim, `other`.
//     The header promises the split "because a skim row must not close an eval". FIX: the eval test was a
//     substring match (`*eval*`), so `retrieval`, `medieval` or `reevaluate` in a skim row read as `eval`
//     (variant 'substring-eval'); it now needs `eval` as a word (`[eval]`, eval, evals, evaluate, evaluation...).
// Row features: `tag` ([eval]), `word` (eval as a word elsewhere), `inner` (eval inside a longer word), `skim`.
import {bool, fun, when} from 'gdp-wired'
import {pick} from './util.ts'

export const STORES = ['url', 'board', 'verdict', 'owned', 'note', 'pr'] as const
export type Variant = 'shipped' | 'substring-eval' | 'skip-hits' | 'skim-first-ignored'
export const VARIANTS: Variant[] = ['substring-eval', 'skip-hits', 'skim-first-ignored']

export function intakeGate(variant: Variant = 'shipped') {
  const ins: Record<string, typeof bool> = {}
  for (const s of STORES) { ins[`${s}On`] = bool; ins[`${s}Match`] = bool }
  return fun(variant === 'shipped' ? 'intake-gate' : `intake-gate/${variant}`)
    .inputs({...ins, tag: bool, word: bool, inner: bool, skim: bool} as Record<string, typeof bool>)
    .returns((e: any) => {
      const hit = (s: string) => (variant === 'skip-hits' ? e[`${s}Match`] : e[`${s}On`].and(e[`${s}Match`]))
      const anyHit = STORES.map(hit).reduce((a: any, b: any) => a.or(b))
      const isEval = variant === 'substring-eval' ? e.tag.or(e.word).or(e.inner) : e.tag.or(e.word)
      const kind = variant === 'skim-first-ignored'
        ? when(isEval.or(e.skim), 0, 2)
        : when(isEval, 0, when(e.skim, 1, 2))
      return {exit: when(anyHit, 0, 1), rowKind: pick(['eval', 'skim', 'other'] as const, kind)}
    })
}

export function laws(f: ReturnType<typeof intakeGate>) {
  const hit = (e: any, s: string) => e[`${s}On`].and(e[`${s}Match`])
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('the gate exits 0 exactly when some searched store holds a match', () => [],
        (o: any, e: any) => o.exit.eq(0).implies(STORES.map(s => hit(e, s)).reduce((a: any, b: any) => a.or(b)))
          .and(STORES.map(s => hit(e, s)).reduce((a: any, b: any) => a.or(b)).implies(o.exit.eq(0)))),
      f.law('a skipped store never makes a hit', (e: any) => STORES.map(s => e[`${s}On`].not().or(e[`${s}Match`].not())).reduce((a: any, b: any) => a.and(b)),
        (o: any) => o.exit.eq(1)),
      f.relate('a missing store only narrows the gate: turning a store on never turns a hit into a miss',
        (a: any, b: any) => STORES.flatMap(s => [a[`${s}Match`].implies(b[`${s}Match`]).and(b[`${s}Match`].implies(a[`${s}Match`])),
          a[`${s}On`].implies(b[`${s}On`])]),
        (x: any, y: any) => x.exit.eq(0).implies(y.exit.eq(0))),
      f.law('a row is labelled eval only when it records an evaluation (an [eval] tag or the word eval)', () => [],
        (o: any, e: any) => o.rowKind.is('eval').implies(e.tag.or(e.word))),
      f.law('a skim row that records no evaluation is labelled skim, so it cannot close an eval',
        (e: any) => [e.skim, e.tag.not(), e.word.not()], (o: any) => o.rowKind.is('skim')),
      f.law('a row tagged [eval] is always labelled eval', (e: any) => e.tag, (o: any) => o.rowKind.is('eval')),
    ],
  }
}
