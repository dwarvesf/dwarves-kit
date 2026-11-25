// The model-tier suggester, lib/classify/route-suggest.sh, over the PASS rows of one task: each model string maps
// to a tier (tier_of), each tier keeps its cheapest total_tokens; fewer than two tiers ABSTAIN (thin data); else
// SUGGEST the cheapest, ties to the alphabetically-first tier (sorted iteration with a strict `<`).
// The script says the tier list and lib/queue/orchestrate.sh's _ROUTE_MODEL_ALLOWLIST (opus sonnet haiku fable)
// "have to move together", because an unmapped model "becomes its OWN tier", inflating the >=2-tiers check and
// emitting "a suggestion the orchestrator's allowlist then rejects". FIX: tier_of passed an unknown model through
// as its own tier (variant 'unknown-is-a-tier'); an unknown model's rows are now skipped like a malformed row.
// Tiers in sorted order, with an unknown model `gpt-5` among them: fable, gpt-5 (other), haiku, opus, sonnet.
// `pX` says tier X has a PASS row, `tX` its cheapest total_tokens.
import {bool, fun, nat, when} from 'gdp-wired'
import {pick} from './util.ts'

export const TIERS = ['fable', 'other', 'haiku', 'opus', 'sonnet'] as const
export const ALLOWED = ['fable', 'haiku', 'opus', 'sonnet'] as const
export type Variant = 'shipped' | 'unknown-is-a-tier' | 'suggests-on-one' | 'last-wins-ties'
export const VARIANTS: Variant[] = ['unknown-is-a-tier', 'suggests-on-one', 'last-wins-ties']

export function routeSuggest(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'route-suggest' : `route-suggest/${variant}`)
    .inputs({pF: bool, tF: nat, pO: bool, tO: nat, pH: bool, tH: nat, pP: bool, tP: nat, pS: bool, tS: nat})
    .returns(e => {
      const counted = (t: string) => t !== 'other' || variant === 'unknown-is-a-tier'
      const p: any[] = [e.pF, e.pO, e.pH, e.pP, e.pS].map((x, i) => counted(TIERS[i]) ? x : x.and(x.not()))
      const tok = [e.tF, e.tO, e.tH, e.tP, e.tS]
      const n = p.map(x => when(x, 1, 0)).reduce((a: any, b: any) => a.plus(b))
      // the sorted scan: best stays unless a later tier is strictly cheaper (or, broken, not dearer)
      let best: any = 5, bestTok: any = 0
      for (let i = 0; i < 5; i++) {
        const better = variant === 'last-wins-ties' ? tok[i].atMost(bestTok) : tok[i].lt(bestTok)
        const take = p[i].and(best === 5 ? p[i] : (best as any).eq(5).or(better))
        best = when(take, i, best); bestTok = when(take, tok[i], bestTok)
      }
      const suggest = variant === 'suggests-on-one' ? n.atLeast(1) : n.atLeast(2)
      return {kind: pick(['SUGGEST', 'ABSTAIN'] as const, when(suggest, 0, 1)), tier: when(suggest, best, 5)}
    })
}

export function laws(f: ReturnType<typeof routeSuggest>) {
  const passed = (e: any, i: any) => [e.pF, e.pO, e.pH, e.pP, e.pS].map((x, k) => i.eq(k).and(x)).reduce((a, b) => a.or(b))
  const tokAt = (e: any, i: any) => [e.tF, e.tO, e.tH, e.tP, e.tS].reduce((acc: any, t: any, k: number) => when(i.eq(k), t, acc), 0)
  const allowedN = (e: any) => [e.pF, e.pH, e.pP, e.pS].map(x => when(x, 1, 0)).reduce((a: any, b: any) => a.plus(b))
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('a suggestion names a tier the orchestrator allowlist accepts', () => [],
        (o) => o.kind.is('SUGGEST').implies(o.tier.eq(1).not().and(o.tier.lt(5)))),
      f.law('a suggestion needs at least two allowlisted tiers measured at parity', () => [],
        (o, e) => o.kind.is('SUGGEST').implies(allowedN(e).atLeast(2))),
      f.law('two or more allowlisted tiers that passed always give a suggestion', (e) => allowedN(e).atLeast(2),
        (o) => o.kind.is('SUGGEST')),
      f.law('the suggested tier passed', () => [], (o, e) => o.kind.is('SUGGEST').implies(passed(e, o.tier))),
      f.law('the suggested tier is the cheapest allowlisted tier that passed', () => [],
        (o, e) => o.kind.is('SUGGEST').implies([[e.pF, e.tF], [e.pH, e.tH], [e.pP, e.tP], [e.pS, e.tS]]
          .map(([pp, tt]: any) => pp.implies(tokAt(e, o.tier).atMost(tt))).reduce((a: any, b: any) => a.and(b)))),
      f.law('a tie goes to the alphabetically-first tier', () => [],
        (o, e) => o.kind.is('SUGGEST').implies([[0, e.pF, e.tF], [2, e.pH, e.tH], [3, e.pP, e.tP], [4, e.pS, e.tS]]
          .map(([k, pp, tt]: any) => pp.and(tt.eq(tokAt(e, o.tier))).implies(o.tier.atMost(k))).reduce((a: any, b: any) => a.and(b)))),
    ],
  }
}
