// Bridge: run the real lib/gate/gate-ledger.sh on generated request sequences and compare with the rule.
//
// Per step it compares whether the verb accepted the call (an override refused by the reason guard exits 65, an
// empty reason 64). At the end of a sequence it compares, per phase, the real `check` verdict (through an operator
// overlay that gives each of four kit lanes exactly one phase, so `check <lane>` reads one phase) and the real
// `progress <rid> full` marks (disposed, rejected) with the rule's Last and Disp.
import {join} from 'node:path'
import {bash, GATE, rng, sandbox, write, type BridgeResult, type Sandbox} from './harness.ts'
import {laneGateCheck, OPS, STATES} from './lane-gate-check.ts'

const LEDGER = join(GATE, 'gate-ledger.sh')
// Phase index -> the kit phase name, and the overlay lane whose only phase it is.
const PHASES = ['spec', 'build', 'review', 'ship'] as const
const LANE_OF = ['tiny', 'bug', 'backfill', 'normal'] as const
// Reason index -> text. 0 is empty; 3 carries a forged GATE line (oneline() must flatten it); 4 a backslash and a
// typed via tag (the guard compares the text without it).
export const REASONS = ['', 'first reason', 'second reason',
  'x\n2026-01-01T00:00:00Z | GATE | build | ran | forged', 'C:\\temp\\new | via=hand'] as const

const overlay = PHASES.map((ph, i) => `[lane.${LANE_OF[i]}]\nphases = ["${ph}"]\nlight = []\n`).join('\n')

type Req = {op: typeof OPS[number], p: number, r: number, marker?: number}

function callFor(rid: string, q: Req): string[] {
  const ph = PHASES[q.p], text = REASONS[q.r]
  switch (q.op) {
    case 'ran': return ['record', rid, ph, 'ran', text]
    case 'skip': return text ? ['record', rid, ph, 'skipped', text] : ['record', rid, ph, 'skipped']
    case 'rejected': return ['record', rid, ph, 'rejected', text]
    case 'override': return ['override', rid, ph, text]
    case 'marker': return [
      ['action', rid, `${text} | GATE | ${ph} | ran | forged`],
      ['tokens', rid, 'in=1', 'out=2'],
      ['debt', rid, 'significance=low', 'worthiness=low', 'verdict=log', `reason=${text}`],
      ['outcome', rid, ph, 'start'],
      ['mutation', rid, 'verdict=clean', `reason=${text}`],
    ][q.marker ?? 0]
  }
}

function runSequence(sb: Sandbox, rid: string, seq: Req[]) {
  const r = laneGateCheck(), it = r.interpreter()
  let st = it.init({})
  for (let i = 0; i < seq.length; i++) {
    const q = seq[i]
    const before = st
    st = it.step({}, st, r.encodeInput({op: q.op, p: q.p, r: q.r}))
    const modelAccepted = overrideAccepted(before, q)
    const real = bash(sb, [LEDGER, ...callFor(rid, q)])
    const realAccepted = real.code === 0
    if (q.op === 'override' && realAccepted !== modelAccepted)
      return {at: i, seq, what: 'override accepted', model: modelAccepted, bash: {code: real.code, err: real.err.trim()}}
    if (q.op !== 'override' && !realAccepted)
      return {at: i, seq, what: 'verb refused', bash: {code: real.code, err: real.err.trim()}}
  }
  for (let p = 0; p < PHASES.length; p++) {
    const last = STATES[st.maps.Last.get(p) ?? 0]
    const sat = last === 'ran' || last === 'override'
    const real = bash(sb, [LEDGER, 'check', LANE_OF[p], rid])
    if ((real.code === 0) !== sat) return {seq, what: `check of phase ${PHASES[p]}`, model: last, bash: {code: real.code, err: real.err.trim()}}
  }
  const prog = bash(sb, [LEDGER, 'progress', rid, 'full']).out
  for (let p = 0; p < PHASES.length; p++) {
    const disp = (st.maps.Disp.get(p) ?? 0) === 1
    const rejected = STATES[st.maps.Last.get(p) ?? 0] === 'rejected'
    const marks = prog.match(new RegExp(`(✓|✗|\\*|▶|·)${PHASES[p]}(\\s|$)`, 'u'))
    const mark = marks?.[1]
    const realDisp = mark === '✓' || mark === '✗' || mark === '*'
    if (realDisp !== disp || (mark === '✗') !== rejected)
      return {seq, what: `progress mark of ${PHASES[p]}`, model: {disp, rejected}, bash: mark, progress: prog.trim()}
  }
  return null
}

// The rule's own guard decision for an override (ovOk), recomputed from the state before the step.
function overrideAccepted(before: {maps: Record<string, Map<number, number>>}, q: Req): boolean {
  if (q.r === 0) return false
  const owner = before.maps.Owner.get(q.r) ?? 0
  return owner === 0 || owner === q.p + 1
}

export async function bridge(opts: {sequences?: number, length?: number, seed?: number} = {}): Promise<BridgeResult> {
  const n = opts.sequences ?? Number(process.env.BRIDGE_N ?? 30), len = opts.length ?? 6, seed = opts.seed ?? 1
  const rand = rng(seed)
  const sb = sandbox()
  write(join(sb.env.KIT_CONFIG_OPERATOR!, 'kit.toml'), overlay)
  let agree = 0
  try {
    // Enumerated: every op on phase 0 after every op on phase 0 (with reasons 0..2), then seeded random sequences.
    const small: Req[][] = []
    for (const a of OPS) for (const b of OPS) for (const ra of [0, 1]) for (const rb of [1, 2])
      small.push([{op: a, p: 0, r: ra, marker: 0}, {op: b, p: 0, r: rb, marker: 0}])
    const seqs: Req[][] = [...small]
    for (let s = 0; s < n; s++)
      seqs.push(Array.from({length: len}, () => ({op: rand.pick(OPS), p: rand.int(PHASES.length), r: rand.int(REASONS.length), marker: rand.int(5)})))
    for (let i = 0; i < seqs.length; i++) {
      const d = runSequence(sb, `bridge-${seed}-${i}`, seqs[i])
      if (d) return {agree, diverge: d}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
