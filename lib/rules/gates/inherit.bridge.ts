// Bridge: seeded random parent ledgers (per phase a history whose LAST row has the drawn state; earlier rows drawn
// too, so "last" is what is tested) written as ledger files in the format the verbs write, then the real
// `gate-ledger.sh inherit` run on a child, optionally after the child already inherited from this parent (a re-run)
// or from another all-ran parent (a reused slug). Compared: the exit code and which phases gained a line.
import {join} from 'node:path'
import {readFileSync} from 'node:fs'
import {bash, GATE, rng, sandbox, write, type BridgeResult} from './harness.ts'
import {inherit, PHASES, STATES} from './inherit.ts'

const LEDGER = join(GATE, 'gate-ledger.sh')
const TS = '2026-01-01T00:00:00Z'
function row(ph: string, st: string, k: number): string {
  switch (st) {
    case 'ran': return `${TS} | GATE | ${ph} | ran | ok ${k}`
    case 'ranBadTs': return `2026-1-1 | GATE | ${ph} | ran | ok ${k}`
    case 'skipped': return `${TS} | GATE | ${ph} | skipped | why ${k}`
    case 'rejected': return `${TS} | GATE | ${ph} | rejected | NEEDS-REVISION ${k}`
    case 'override': return `${TS} | GATE | ${ph} | override | reason ${ph} ${k} | via=hand`
    case 'inherited': return `${TS} | GATE | ${ph} | override | inherited from gp: ${ph} ran there at ${TS} | via=inherit`
    default: return ''
  }
}

export async function bridge(opts: {n?: number, seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 17), f = inherit()
  const n = opts.n ?? Number(process.env.BRIDGE_N ?? 60)
  const runs = join(sb.env.KIT_LEDGER_DIR!, 'runs')
  let agree = 0
  try {
    write(join(runs, 'other-parent.log'), PHASES.map(ph => row(ph, 'ran', 0)).join('\n') + '\n')
    for (let i = 0; i < n; i++) {
      const parent = `par-${i}`, child = `kid-${i}`
      const states = PHASES.map(() => (rand.next() < 0.75 ? 'ran' : rand.pick(STATES)))
      const parentLedger = rand.next() < 0.95, mode = rand.pick(['fresh', 'fresh', 'rerun', 'conflict'] as const)
      const full = rand.next() < 0.95, distinct = rand.next() < 0.95
      if (parentLedger) write(join(runs, `${parent}.log`), PHASES.flatMap((ph, k) => [
        // a phase whose last state is none has no row at all; any other gets an optional earlier row first
        ...(states[k] !== 'none' && rand.next() < 0.4 ? [row(ph, rand.pick(STATES.filter(s => s !== 'none')), 100 + k)] : []), row(ph, states[k], k)]).filter(Boolean).join('\n') + '\n')
      let had = PHASES.map(() => false), conflict = false
      if (mode === 'rerun' && parentLedger && states.every(s => s === 'ran')) {
        bash(sb, [LEDGER, 'inherit', child, 'full', '--from', parent]); had = PHASES.map(() => true)
      }
      if (mode === 'conflict') { bash(sb, [LEDGER, 'inherit', child, 'full', '--from', 'other-parent']); conflict = true }
      const before = (() => { try { return readFileSync(join(runs, `${child}.log`), 'utf8') } catch { return '' } })()
      const real = bash(sb, [LEDGER, 'inherit', child, full ? 'full' : 'normal', '--from', distinct ? parent : child])
      const after = (() => { try { return readFileSync(join(runs, `${child}.log`), 'utf8') } catch { return '' } })()
      const added = after.slice(before.length)
      const facts: Record<string, unknown> = {full, distinct, parentLedger, conflict}
      PHASES.forEach((_, k) => { facts[`p${k}`] = parentLedger ? states[k] : 'none'; facts[`had${k}`] = had[k] })
      const o = f.run(facts as any) as any
      const wrote = PHASES.map(ph => added.includes(`| GATE | ${ph} | override | inherited from ${parent}: `))
      const extra = added.split('\n').filter(Boolean).filter(l => !PHASES.some(ph => l.includes(`| GATE | ${ph} | override | inherited from ${parent}: `)))
      const ok = real.code === o.rc && PHASES.every((_, k) => wrote[k] === o[`w${k}`]) && extra.length === 0
      if (!ok) return {agree, diverge: {facts, model: o, bash: {code: real.code, err: real.err.trim(), added}}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
