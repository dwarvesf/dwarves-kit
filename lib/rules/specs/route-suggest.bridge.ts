// Bridge: ablation ledgers (the 12-column TSV) with PASS rows for any subset of fable, an unknown `gpt-5`, haiku,
// opus and sonnet at small token counts (ties likely), a cheaper FAIL row and another task's row as decoys; the
// real route-suggest.sh against the rule (route-suggest.ts).
import {writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {routeSuggest, TIERS, type Variant} from './route-suggest.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/classify/route-suggest.sh')
const MODEL = {fable: 'fable-5', other: 'gpt-5', haiku: 'haiku-4-5', opus: 'opus-4-8', sonnet: 'sonnet-4-6'} as const
const NAME = ['fable', 'gpt-5', 'haiku', 'opus', 'sonnet']

export async function bridge(variant: Variant = 'shipped'): Promise<BridgeResult> {
  const f = routeSuggest(variant)
  const t = tmp('route')
  let agree = 0
  try {
    const rand = seeded(715)
    for (let i = 0; i < 120; i++) {
      const rows: string[] = [], input: Record<string, unknown> = {}
      const keys = ['F', 'O', 'H', 'P', 'S']
      TIERS.forEach((tier, k) => {
        const on = i < 32 ? ((i >> k) & 1) === 1 : rand(2) === 1
        const toks = Array.from({length: 1 + rand(2)}, () => 1 + rand(4))
        input[`p${keys[k]}`] = on; input[`t${keys[k]}`] = on ? Math.min(...toks) : 0
        if (on) for (const tk of toks) rows.push(['t1', `arm-${tier}`, 'pass', tk, 1, 1, 0, 0, 1, '0.1', MODEL[tier], `s${k}`].join('\t'))
        rows.push(['t1', `arm-${tier}-f`, 'fail', 0, 1, 1, 0, 0, 1, '0.1', MODEL[tier], 'sf'].join('\t'))
      })
      rows.push(['t2', 'arm-x', 'pass', 0, 1, 1, 0, 0, 1, '0.1', 'opus-4-8', 'sx'].join('\t'))
      const file = join(t.dir, `l${i}.tsv`); writeFileSync(file, rows.join('\n') + '\n')
      const res = run(['bash', SH, file, 't1'])
      const m = f.run(input as never) as {kind: string, tier: number}
      const kind = res.out.split('\t')[0]
      const tier = kind === 'SUGGEST' ? NAME.indexOf(/model=([^\t]+)/.exec(res.out)![1]) : 5
      if (kind !== m.kind || tier !== m.tier) return {agree, diverge: {input, bash: res.out.trim(), rule: m}}
      agree++
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const v = (process.argv[2] ?? 'shipped') as Variant
  console.log(JSON.stringify({variant: v, bridge: await bridge(v)}, null, 1))
}
