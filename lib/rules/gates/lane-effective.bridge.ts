// Bridge: drive the real `gate-ledger.sh start`, `start --amend [--lower --reason]` and `override <rid> lane-lower`
// on generated sequences, then read the real `gate-ledger.sh lane <rid> --spec <spec>` for every spec header, and
// compare each verb's accept/refuse and the reader's columns (ledger lane, source, check lane) with the rule.
import {join} from 'node:path'
import {bash, GATE, rng, sandbox, write, type BridgeResult, type Sandbox} from './harness.ts'
import {laneColumns, laneEffective, LANES, OPS} from './lane-effective.ts'

const LEDGER = join(GATE, 'gate-ledger.sh')
const NAME = (l: string) => (l === 'other' ? 'mega' : l)
type Req = {op: typeof OPS[number], lane: typeof LANES[number], lower: boolean, reason: boolean, arrow: boolean}

function call(rid: string, q: Req, n: number): string[] {
  const lane = NAME(q.lane)
  if (q.op === 'start') return ['start', rid, lane, lane, 'spec-feature', 'x', 'repo']
  if (q.op === 'override_ll') return ['override', rid, 'lane-lower', `full -> ${lane}: forged by hand ${n}`]
  const flags = [...(q.lower ? ['--lower'] : []), ...(q.reason ? ['--reason', q.arrow ? `scope a -> b shrank ${n}` : `scope shrank ${n}`] : [])]
  return ['start', '--amend', ...flags, rid, lane, lane, 'spec-feature', 'x', 'repo']
}

function lanesOf(r: ReturnType<typeof laneEffective>, st: any) { return r.decode(st) as Record<string, any> }

function runSequence(sb: Sandbox, rid: string, seq: Req[], specs: Record<string, string>) {
  const r = laneEffective(), it = r.interpreter()
  let st = it.init({hdr: 0})
  for (let i = 0; i < seq.length; i++) {
    const q = seq[i]
    st = it.step({hdr: 0}, st, r.encodeInput(q))
    const want = !!lanesOf(r, st).ok
    const real = bash(sb, [LEDGER, ...call(rid, q, i)])
    if ((real.code === 0) !== want) return {at: i, seq, what: 'verb accepted', model: want, bash: {code: real.code, err: real.err.trim()}}
  }
  const s = lanesOf(r, st)
  for (const hdr of LANES) {
    const exp = expected(s, hdr)
    const real = bash(sb, [LEDGER, 'lane', rid, '--spec', specs[hdr]])
    const cols = real.out.trim().split('\t')
    const got = real.code === 0 ? {lane: cols[0], src: cols[1], chk: cols[3]} : null
    if (JSON.stringify(got) !== JSON.stringify(exp)) return {seq, hdr, what: 'lane columns', model: exp, bash: got ?? real.err.trim()}
  }
  return null
}

// lane_effective's columns for the decoded state and a header, from the rule's own column terms (laneColumns).
export function expected(s: Record<string, any>, hdr: string) {
  const c = laneColumns.run({hdr, a: s.a, first: s.first, low: !!s.low}) as any
  if (c.lane === 'none') return null
  return {lane: NAME(c.lane), src: c.fromAmend ? 'amend' : c.fromStart ? 'start' : 'spec', chk: NAME(c.chk)}
}

export async function bridge(opts: {sequences?: number, length?: number, seed?: number} = {}): Promise<BridgeResult> {
  const n = opts.sequences ?? Number(process.env.BRIDGE_N ?? 40), len = opts.length ?? 4, seed = opts.seed ?? 7
  const rand = rng(seed), sb = sandbox()
  const specs: Record<string, string> = {}
  for (const h of LANES) { specs[h] = join(sb.dir, `spec-${h}.md`); write(specs[h], `# Spec\nStatus: DRAFT\n${h === 'none' ? '' : `Lane: ${NAME(h)}\n`}`) }
  const real = LANES.filter(l => l !== 'none')
  let agree = 0
  try {
    // Enumerated: the two counterexamples the prover found for the pre-fix code, then every pair of (START lane,
    // amend lane) with and without --lower, then seeded random sequences.
    const seqs: Req[][] = [
      [{op: 'override_ll', lane: 'tiny', lower: false, reason: false, arrow: false}, {op: 'amend', lane: 'tiny', lower: false, reason: false, arrow: false}],
      [{op: 'start', lane: 'normal', lower: false, reason: false, arrow: false}, {op: 'amend', lane: 'tiny', lower: true, reason: true, arrow: true}],
    ]
    for (const s1 of real) for (const s2 of real) for (const lower of [false, true])
      seqs.push([{op: 'start', lane: s1, lower: false, reason: false, arrow: false}, {op: 'amend', lane: s2, lower, reason: lower, arrow: false}])
    for (let k = 0; k < n; k++)
      seqs.push(Array.from({length: len}, () => {
        const reason = rand.next() < 0.7
        return {op: rand.pick(OPS), lane: rand.pick(real), lower: rand.next() < 0.5, reason, arrow: reason && rand.next() < 0.5}
      }))
    for (let i = 0; i < seqs.length; i++) {
      const d = runSequence(sb, `le-${seed}-${i}`, seqs[i], specs)
      if (d) return {agree, diverge: d}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
