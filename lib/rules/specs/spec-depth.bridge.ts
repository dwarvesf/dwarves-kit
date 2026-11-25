// Bridge: write specs from every Depth form (none, standard, deeper, mixed, malformed, unknown level, vague
// reason), Generated date, spec number, lane, task count and Open questions body; run the real
// lib/spec/spec-depth.sh `size` and `check`, and compare with the rule's decision (spec-depth.ts).
import {writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {specDepth, type Variant} from './spec-depth.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/spec/spec-depth.sh')
// [line, hasLine, lv, malformed, reasonBad]
const DEPTHS: [string, boolean, string, boolean, boolean][] = [
  ['', false, 'empty', false, false],
  ['Depth: standard (reuses the existing parser)', true, 'standard', false, false],
  ['**Depth:** research (repo: how the board lock nests)', true, 'deeper', false, false],
  ['Depth: standard (small) + research (repo: lock order)', true, 'both', false, false],
  ['Depth: research (the lock order)', true, 'empty', true, false],
  ['Depth: deep (unknown thing)', true, 'empty', true, false],
  ['Depth: blind-spot (failure: important critical)', true, 'deeper', false, true],
  ['Depth: standard (it is important)', true, 'standard', false, true],
  ['Depth: research (repo: x api) + bogus (y)', true, 'deeper', true, false],
]
const GENS: [string, boolean, boolean][] = [['', false, false], ['Generated: 2026-01-05', false, true], ['Generated: 2026-10-02', true, false]]
const NUMS: [string, boolean, boolean][] = [['notes.md', false, false], ['SPEC-100-x.md', false, true], ['SPEC-400-x.md', true, false]]
const LANES: [string, boolean][] = [['', false], ['Lane: normal', true], ['**Lane:** full', false]]

export async function bridge(variant: Variant = 'shipped'): Promise<BridgeResult> {
  const f = specDepth(variant)
  const t = tmp('spec-depth')
  let agree = 0
  try {
    const rand = seeded(372)
    const one = (d: number, g: number, n: number, l: number, tasks: number, oq: boolean) => {
      const file = join(t.dir, NUMS[n][0])
      const head = ['# Spec x', LANES[l][0], GENS[g][0], DEPTHS[d][0]].filter(Boolean).join('\n')
      const body = ['', '## Tasks', ...Array.from({length: tasks}, (_, i) => `- [ ] T${i + 1}: task ${i + 1}`), '',
        '## Open questions', '', oq ? 'What about the lock order?' : '(none)', ''].join('\n')
      writeFileSync(file, head + '\n' + body)
      const [, hasLine, lv, malformed, reasonBad] = DEPTHS[d]
      const m = f.run({laneNormal: LANES[l][1], hasLine, lv, malformed, reasonBad, genNew: GENS[g][1], genOld: GENS[g][2],
        numNew: NUMS[n][1], numOld: NUMS[n][2], oq, tasks} as never) as {size: string, fail: boolean, warn: boolean}
      const size = run(['bash', SH, 'size', file]), check = run(['bash', SH, 'check', file])
      const bash = {size: size.code === 0 ? 'small' : 'large', fail: check.code !== 0, warn: check.err.includes('warning:')}
      if (bash.size !== m.size || bash.fail !== m.fail || bash.warn !== m.warn)
        return {depth: DEPTHS[d][0], generated: GENS[g][0], file: NUMS[n][0], lane: LANES[l][0], tasks, oq, bash, rule: m, sizeOut: size.out.trim(), checkOut: check.out.trim()}
      agree++
      return null
    }
    for (let d = 0; d < DEPTHS.length; d++) for (let g = 0; g < GENS.length; g++) for (let n = 0; n < NUMS.length; n++) {
      const x = one(d, g, n, 1, 2, d % 2 === 0); if (x) return {agree, diverge: x}
    }
    for (let i = 0; i < 120; i++) {
      const x = one(rand(DEPTHS.length), rand(GENS.length), rand(NUMS.length), rand(LANES.length), rand(5), rand(2) === 1)
      if (x) return {agree, diverge: x}
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const v = (process.argv[2] ?? 'shipped') as Variant
  console.log(JSON.stringify({variant: v, bridge: await bridge(v)}, null, 1))
}
