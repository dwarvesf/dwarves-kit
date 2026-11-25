// Bridge: descriptions built from phrases that fire one signal each (a full-risk subject for lane-classify,
// design-bearing, new public surface, and the five worthiness triggers), an impl-notes file with or without an
// entry, and SIGNIFICANCE_WORTHINESS_MIN 0..3; the real significance-classify.sh `classify` against the rule.
import {writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {significance} from './significance.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/classify/significance-classify.sh')
const WORTH = ['building block', 'costly to reverse', 'greenfield', 'blast radius', 'design decision']

export async function bridge(): Promise<BridgeResult> {
  const f = significance()
  const t = tmp('significance')
  let agree = 0
  try {
    const notesYes = join(t.dir, 'yes.md'), notesNo = join(t.dir, 'no.md')
    writeFileSync(notesYes, '# notes\n\n## 2026-11-25 chose X over Y\n'); writeFileSync(notesNo, '# notes\n')
    const env = {KIT_CONFIG_OPERATOR: join(t.dir, 'none'), KIT_PROJECT_ROOT: t.dir, KIT_LEDGER_DIR: join(t.dir, 'ledger'), HOME: t.dir}
    const rand = seeded(123), b = () => rand(2) === 1
    for (let i = 0; i < 90; i++) {
      const riskFull = i < 8 ? (i & 1) > 0 : b(), design = i < 8 ? (i & 2) > 0 : b(), surface = i < 8 ? (i & 4) > 0 : b()
      const worth = WORTH.filter(() => rand(3) === 0), notes = rand(3) === 0, min = rand(4)
      const desc = [riskFull && 'rotate the jwt', design && 'add a new module', surface && 'add a new cli', ...worth, 'for the widget'].filter(Boolean).join(' and ')
      const res = run(['bash', SH, 'classify', '--impl-notes', notes ? notesYes : notesNo, desc], {cwd: t.dir, env: {...env, SIGNIFICANCE_WORTHINESS_MIN: String(min)}})
      const m = f.run({riskFull, design, surface, n: worth.length + (notes ? 1 : 0), min} as never) as {verdict: string}
      if (res.out.trim() !== m.verdict) return {agree, diverge: {desc, notes, min, bash: res.out.trim(), rule: m.verdict, stderr: res.err.trim()}}
      agree++
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge()}, null, 1))
