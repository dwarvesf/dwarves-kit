// "Which spec is active", as lib/spec/spec-active.sh `spec_active` answers it over three root specs (ls order
// 0, 1, 2), for the two modes callers use:
//   - default (spec-active.sh:53-59 -> spec-find.sh:spec_for_slug:38-55): the first root file matching the glob
//     SPEC-*-<slug>.md, status-blind (a ship flips the spec to SHIPPED before the push).
//   - --live (spec-active.sh:61-99): the open specs (`spec-status.sh live --none live`); the name pick (the first
//     file in ls order matching SPEC-*-<slug>.md) counts only while open; else the one open spec; else the one
//     open spec whose slug has a whole branch token; else `ambiguous` (exit 2); no open spec is `none` (exit 1).
// Per spec: `live` (open), `glob` (its name matches SPEC-*-<slug>.md: the glob spans dashes, so slug `gate`
// matches SPEC-001-ship-gate.md), `exact` (its slug IS <slug>; exact implies glob), `tok` (a branch token is a
// whole token of its slug). `idx` is the picked spec, 3 for none.
import {bool, fun, when} from 'gdp-wired'
import {pick} from './util.ts'

const when3 = (c: any, a: any, b: any) => when(c, a, b)
const count = (cs: any[]) => cs.map(c => when(c, 1, 0)).reduce((a: any, b: any) => a.plus(b))
const same = (a: any, b: any) => a.implies(b).and(b.implies(a))

export const KINDS = ['name', 'live', 'branch', 'ambiguous', 'none'] as const
export type Variant = 'shipped' | 'live-ignores-status' | 'ambiguous-picks-first'
export const VARIANTS: Variant[] = ['live-ignores-status', 'ambiguous-picks-first']

export function specActive(variant: Variant = 'shipped') {
  return fun(variant === 'shipped' ? 'spec-active' : `spec-active/${variant}`)
    .inputs({
      live0: bool, live1: bool, live2: bool,
      glob0: bool, glob1: bool, glob2: bool,
      exact0: bool, exact1: bool, exact2: bool,
      tok0: bool, tok1: bool, tok2: bool,
    })
    .assume(e => e.exact0.implies(e.glob0).and(e.exact1.implies(e.glob1)).and(e.exact2.implies(e.glob2)))
    .returns(e => {
      const live = [e.live0, e.live1, e.live2], glob = [e.glob0, e.glob1, e.glob2], tok = [e.tok0, e.tok1, e.tok2]
      const firstOf = (xs: any[]) => (when3(xs[0], 0, when3(xs[1], 1, when3(xs[2], 2, 3))))
      // default mode: first glob match, status-blind
      const nameIdx = firstOf(glob)
      // --live
      const anyLive = live[0].or(live[1]).or(live[2])
      const nLive = count(live)
      const nameLive = glob[0].and(live[0])
        .or(glob[0].not().and(glob[1]).and(live[1]))
        .or(glob[0].not().and(glob[1].not()).and(glob[2]).and(live[2]))
      const openTok = [0, 1, 2].map(i => tok[i].and(live[i]))
      const oneTok = count(openTok).eq(1)
      const nameOk = variant === 'live-ignores-status' ? glob[0].or(glob[1]).or(glob[2]) : nameLive
      const kind = when3(anyLive.not(), 4, when3(nameOk, 0, when3(nLive.eq(1), 1, when3(oneTok, 2,
        variant === 'ambiguous-picks-first' ? 1 : 3))))
      const liveIdx = when3(anyLive.not(), 3, when3(nameOk, nameIdx, when3(nLive.eq(1), firstOf(live),
        when3(oneTok, firstOf(openTok), variant === 'ambiguous-picks-first' ? firstOf(live) : 3))))
      return {kind: pick(KINDS, kind), idx: liveIdx, nameIdx}
    })
}

export function laws(f: ReturnType<typeof specActive>) {
  const live = (e: any, i: any) => i.eq(0).and(e.live0).or(i.eq(1).and(e.live1)).or(i.eq(2).and(e.live2))
  const nLive = (e: any) => count([e.live0, e.live1, e.live2])
  return {
    laws: [],
    stepLaws: [],
    decisions: [
      f.law('the --live pick is always an open spec', () => [],
        (o, e) => o.kind.is('ambiguous').or(o.kind.is('none')).not().implies(live(e, o.idx))),
      f.law('the --live answer is none only when no spec is open', () => [],
        (o, e) => o.kind.is('none').implies(nLive(e).eq(0))),
      f.law('the --live answer is ambiguous only when two or more specs are open', () => [],
        (o, e) => o.kind.is('ambiguous').implies(nLive(e).atLeast(2))),
      f.law('one open spec is always the --live pick', (e) => nLive(e).eq(1),
        (o, e) => o.kind.is('ambiguous').not().and(o.kind.is('none').not())),
      f.law('several open specs that neither the name nor one branch token settles are ambiguous, never guessed',
        (e) => [nLive(e).atLeast(2),
          e.glob0.and(e.live0).or(e.glob0.not().and(e.glob1).and(e.live1)).or(e.glob0.not().and(e.glob1.not()).and(e.glob2).and(e.live2)).not(),
          count([e.tok0.and(e.live0), e.tok1.and(e.live1), e.tok2.and(e.live2)]).eq(1).not()],
        (o) => o.kind.is('ambiguous')),
      f.law('a branch pick is an open spec that carries a branch token', () => [],
        (o, e) => o.kind.is('branch').implies(o.idx.eq(0).and(e.tok0).or(o.idx.eq(1).and(e.tok1)).or(o.idx.eq(2).and(e.tok2)))),
      f.law('the default (enforcement) pick is a spec whose name matches the slug', () => [],
        (o, e) => o.nameIdx.eq(0).and(e.glob0).or(o.nameIdx.eq(1).and(e.glob1)).or(o.nameIdx.eq(2).and(e.glob2)).or(o.nameIdx.eq(3))),
      f.relate('the default (enforcement) pick never depends on any spec\'s status',
        (a, b) => [same(a.glob0, b.glob0), same(a.glob1, b.glob1), same(a.glob2, b.glob2)],
        (x, y) => x.nameIdx.eq(y.nameIdx)),
    ],
  }
}
// The reviewer's law the faithful rule refutes (unfixed: spec-find.sh documents the root glob and
// tests/test-spec-find.sh row 3 pins it as "the root-glob invariant"): with SPEC-001-ship-gate.md and
// SPEC-002-gate.md both present, slug `gate` picks SPEC-001-ship-gate.md, in both modes.
export function refuted(f: ReturnType<typeof specActive>) {
  return {
    laws: [], stepLaws: [],
    decisions: [
      f.law('when a spec named exactly for the slug exists, the name pick is that spec', (e) => e.exact1.and(e.exact0.not()),
        (o) => o.nameIdx.eq(1)),
    ],
  }
}
