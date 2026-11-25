// Bridge: seeded random record-batch calls (lane normal) against seeded ledgers (none; a START full, so the batch
// lowers; a START normal whose docs gate was overridden with the reason "same") through the real gate-ledger.sh,
// compared with the decision: refused (exit 64/65) and the ledger byte-identical, or written and exit = check().
import {join} from 'node:path'
import {readFileSync} from 'node:fs'
import {bash, GATE, rng, sandbox, type BridgeResult} from './harness.ts'
import {recordBatch} from './record-batch.ts'

const LEDGER = join(GATE, 'gate-ledger.sh')
const PHASES = ['spec', 'build', 'review', 'ship', 'think', 'grill', 'bogus'] as const
const REQUIRED = ['spec', 'build', 'review', 'ship']

export async function bridge(opts: {n?: number, seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 31), f = recordBatch()
  const n = opts.n ?? Number(process.env.BRIDGE_N ?? 60)
  let agree = 0
  try {
    for (let i = 0; i < n; i++) {
      const rid = `rb-${i}`, pre = rand.pick(['none', 'full', 'normalDocs'] as const)
      if (pre === 'full') bash(sb, [LEDGER, 'start', rid, 'full', 'full', 'spec-feature'])
      if (pre === 'normalDocs') { bash(sb, [LEDGER, 'start', rid, 'normal', 'normal', 'spec-feature']); bash(sb, [LEDGER, 'override', rid, 'docs', 'same']) }
      const items = Array.from({length: 1 + rand.int(4)}, (_, k) => ({
        phase: rand.next() < 0.1 ? 'bogus' : rand.pick(PHASES.filter(p => p !== 'bogus')),
        state: rand.next() < 0.08 ? 'bad' : rand.pick(['ran', 'ran', 'override', 'skipped'] as const),
        ev: rand.next() < 0.1 ? '' : rand.next() < 0.15 ? 'same' : `evidence ${i}-${k}`,
      }))
      const dflt = rand.next() < 0.3 ? (rand.next() < 0.5 ? 'same' : `default ${i}`) : ''
      const args = [LEDGER, 'record-batch', rid, 'normal', ...(dflt ? ['--evidence-default', dflt] : []),
        ...items.map(it => `${it.phase}=${it.state}${it.ev ? ':' + it.ev : ''}`)]
      const file = join(sb.env.KIT_LEDGER_DIR!, 'runs', `${rid}.log`)
      const read = () => { try { return readFileSync(file, 'utf8') } catch { return '' } }
      const before = read()
      const real = bash(sb, args)
      const after = read()
      const evOf = (it: typeof items[number]) => it.ev || dflt
      const seen = new Set<string>()
      const dup = items.some(it => (seen.has(it.phase) ? true : (seen.add(it.phase), false)))
      const ovs = items.filter(it => it.state === 'override')
      const sharedReason = ovs.some((a, x) => ovs.some((b, y) => x !== y && a.phase !== b.phase && evOf(a) === evOf(b) && evOf(a) !== ''))
        || (pre === 'normalDocs' && ovs.some(it => it.phase !== 'docs' && evOf(it) === 'same'))
      const last: Record<string, string> = {}
      for (const it of items) last[it.phase] = it.state
      const facts = {
        unknownPhase: items.some(it => it.phase === 'bogus'), badState: items.some(it => it.state === 'bad'), dup,
        noEvidence: items.some(it => !evOf(it)), sharedReason, grillBad: items.some(it => it.phase === 'grill' && it.state === 'skipped'),
        lowers: pre === 'full', complete: REQUIRED.every(p => last[p] === 'ran' || last[p] === 'override'),
      }
      const o = f.run(facts)
      const ok = o.refused ? (real.code === 64 || real.code === 65) && after === before
        : after !== before && (real.code === 0) === o.exit0 && (real.code === 0 || real.code === 1)
      if (!ok) return {agree, diverge: {args: args.slice(1), pre, facts, model: o, bash: {code: real.code, err: real.err.trim(), changed: after !== before}}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
