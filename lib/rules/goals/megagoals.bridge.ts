// Bridge: `lib/goal/megagoals.sh list` against megagoals(). Seeded random ROADMAP.md files are built from line kinds
// (section headings, other `##`/`#`/`###` headings, done/open/parked boxes, prose) under `_meta/megagoals/<slug>/` of a
// temp repo; `list --all --limit 0` prints `<slug>  done/total ...` per mega-goal and a plain `list` shows which are
// visible. The counts, the (parked) marker and the visibility are compared with the rule run over the same lines.
import {mkdirSync, rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {LINES, megagoals, type Variant} from './megagoals.ts'
import {cleanup, lib, rng, sh, tmp, type BridgeResult} from './_bridge.ts'

const TEXT: Record<typeof LINES[number], string[]> = {
  sec: ['## Sub-goals', '## Status (source of truth)'], h2: ['## Imported history', '## Notes'], h1: ['# Appendix'], h3: ['### Wave 1'],
  done: ['- [x] SG-01 shipped , auto , PR #1', '| 01 | thing | - [X] done |'], open: ['- [ ] SG-02 next , auto'], parked: ['- [~] 09-rehomed (repo), moved', '- [-] SG-07 dropped'],
  text: ['Some prose.', ''],
}

export async function bridge(opts: {cases?: number, seed?: number, variant?: Variant} = {}): Promise<BridgeResult> {
  const cases = opts.cases ?? 40
  const variant = opts.variant ?? 'shipped'
  const g = rng(opts.seed ?? 19)
  const r = megagoals(variant), it = r.interpreter()
  const root = tmp('megagoals-')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    for (let c = 0; c < cases && !diverge; c++) {
      const repo = join(root, `r${c}`)
      rmSync(repo, {recursive: true, force: true})
      const megas = Array.from({length: 3}, (_, i) => {
        const kinds = Array.from({length: 4 + g.int(8)}, () => g.pick(LINES))
        const lines = kinds.map(k => g.pick(TEXT[k]))
        const dir = join(repo, '_meta/megagoals', `m${i}`); mkdirSync(dir, {recursive: true})
        writeFileSync(join(dir, 'ROADMAP.md'), `# Mega m${i}\n${lines.join('\n')}\n`)
        return {slug: `m${i}`, kinds: ['h1' as const, ...kinds]}
      })
      const all = sh('bash', [lib('goal/megagoals.sh'), 'list', '--repo', repo, '--all', '--limit', '0']).out
      const vis = sh('bash', [lib('goal/megagoals.sh'), 'list', '--repo', repo, '--limit', '0']).out
      const got = megas.map(m => {
        const row = all.split('\n').find(l => l.startsWith(`${m.slug} `)) ?? ''
        const counts = /\s(\d+)\/(\d+)\s/.exec(row)
        return `${counts ? `${counts[1]}/${counts[2]}` : '?'}${row.endsWith('(parked)') ? ' parked' : ''}${vis.split('\n').some(l => l.startsWith(`${m.slug} `)) ? ' shown' : ''}`
      })
      const want = megas.map(m => {
        const P = r.encodeParams({all: false})
        let st: any = it.init(P)
        for (const k of m.kinds) st = it.step(P, st, r.encodeInput({line: k}))
        const s = st.scalars
        const parkedMark = s.total > 0 && s.active === 0 && s.parked > 0
        const isShown = s.total > 0 && (s.active > 0 || (variant !== 'parked-hidden' && s.parked > 0))
        return `${s.done}/${s.total}${parkedMark ? ' parked' : ''}${isShown ? ' shown' : ''}`
      })
      if (JSON.stringify(want) !== JSON.stringify(got)) diverge = {megas: megas.map(m => ({slug: m.slug, lines: m.kinds})), rule: want, bash: got}
      else agree += megas.length
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}


if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({cases: Number(process.env.CASES ?? 40), seed: Number(process.env.SEED ?? 19), variant: (process.env.VARIANT as Variant) ?? 'shipped'})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
