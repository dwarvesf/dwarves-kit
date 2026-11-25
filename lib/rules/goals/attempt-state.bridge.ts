// Bridge: lib/goal/attempt-state.sh against attemptState().interpreter().
// Each request is run as the real script (ATTEMPT_REGISTRY_DIR in a temp dir, ATTEMPT_NOW pinning the clock), then the
// stored `<task>.task` file is read back and compared with the rule's state after the same request. Every sequence of
// three requests over a small alphabet is enumerated (depth-first, the store snapshotted between branches), then
// seeded random sequences of twelve.
import {existsSync, readFileSync, rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {attemptState} from './attempt-state.ts'
import {cell, cleanup, lib, rng, sh, tmp, type BridgeResult} from './_bridge.ts'
import {ATT, TASK as TASKS} from './attempt-state.ts'

type Req = {op: 'dispatch' | 'disconnect' | 'resume' | 'lose' | 'commit' | 'abandon', a: number, w: number, g: number, t: number}
const TASK = 'T1'
const SCRIPT = lib('goal/attempt-state.sh')

function argv(q: Req): string[] {
  const aid = `a${q.a + 1}`
  switch (q.op) {
    case 'dispatch': return ['dispatch', TASK, `w${q.w}`]
    case 'disconnect': return ['mark-disconnected', TASK, aid, '--grace', String(q.g)]
    case 'resume': return ['resume', TASK, aid]
    case 'lose': return ['lose-attempt', TASK, aid]
    case 'commit': return ['commit-result', TASK, aid, `ref-${q.a}`]
    case 'abandon': return ['abandon', TASK, 'no worker left']
  }
}

type View = {task: string, n: number, winner: number, atts: string[], excl: string}

function fromStore(dir: string): View {
  const f = join(dir, `${TASK}.task`)
  if (!existsSync(f)) return {task: 'queued', n: 0, winner: 0, atts: [], excl: ''}
  let task = 'queued', winner = 0, excl = ''
  const atts: string[] = []
  for (const line of readFileSync(f, 'utf8').split('\n')) {
    if (line.startsWith('state=')) task = line.slice(6)
    else if (line.startsWith('winner=')) winner = line.length > 7 ? Number(line.slice(8)) : 0
    else if (line.startsWith('excluded=')) excl = line.slice(9).split(' ').filter(Boolean).map(w => w.slice(1)).sort().join(',')
    else if (line.startsWith('attempt|')) {
      const [, , worker, st, until] = line.split('|')
      atts.push(`${st}/${worker.slice(1)}/${until}`)
    }
  }
  return {task, n: atts.length, winner, atts, excl}
}

function fromRule(st: any): View {
  const n = st.scalars.n as number
  const atts: string[] = []
  for (let k = 0; k < n; k++) {
    const until = cell(st, 'HasUntil', k) ? String(cell(st, 'Until', k)) : ''
    atts.push(`${ATT[cell(st, 'Att', k)]}/${cell(st, 'Wk', k)}/${until}`)
  }
  const ex = st.maps.Excl as Map<number, number>
  const excl = [...ex.entries()].filter(([, v]) => v).map(([k]) => String(k)).sort().join(',')
  return {task: TASKS[st.scalars.task], n, winner: st.scalars.winner, atts, excl}
}

const ALPHABET: Req[] = [
  {op: 'dispatch', a: 0, w: 0, g: 0, t: 0}, {op: 'dispatch', a: 0, w: 1, g: 0, t: 0},
  {op: 'disconnect', a: 0, w: 0, g: 2, t: 1}, {op: 'disconnect', a: 1, w: 0, g: 0, t: 1},
  {op: 'resume', a: 0, w: 0, g: 0, t: 0}, {op: 'resume', a: 1, w: 0, g: 0, t: 0},
  {op: 'lose', a: 0, w: 0, g: 0, t: 2}, {op: 'lose', a: 0, w: 0, g: 0, t: 5}, {op: 'lose', a: 1, w: 0, g: 0, t: 2},
  {op: 'commit', a: 0, w: 0, g: 0, t: 0}, {op: 'commit', a: 1, w: 0, g: 0, t: 0},
  {op: 'abandon', a: 0, w: 0, g: 0, t: 0},
]

export async function bridge(opts: {depth?: number, random?: number, length?: number, seed?: number} = {}): Promise<BridgeResult> {
  const depth = opts.depth ?? 3, random = opts.random ?? 40, length = opts.length ?? 12
  const r = attemptState(), it = r.interpreter()
  const dir = tmp('attempt-')
  const file = join(dir, `${TASK}.task`)
  let agree = 0
  let diverge: BridgeResult['diverge'] = null
  const run = (st: any, q: Req, trace: Req[]) => {
    const res = sh('bash', [SCRIPT, ...argv(q)], {env: {ATTEMPT_REGISTRY_DIR: dir, ATTEMPT_NOW: String(q.t)}})
    const next = it.step({}, st, r.encodeInput(q))
    const want = fromRule(next), got = fromStore(dir)
    if (JSON.stringify(want) !== JSON.stringify(got)) {
      diverge = {trace: [...trace, q].map(x => argv(x).join(' ') + ` @t=${x.t}`), rule: want, bash: got, exit: res.code, stderr: res.err.trim()}
    } else agree++
    return next
  }
  const snap = () => existsSync(file) ? readFileSync(file, 'utf8') : null
  const restore = (s: string | null) => { if (s === null) rmSync(file, {force: true}); else writeFileSync(file, s) }
  try {
    // Exhaustive: every sequence of `depth` requests from the alphabet.
    const dfs = (st: any, trace: Req[]) => {
      if (diverge || trace.length === depth) return
      const saved = snap()
      for (const q of ALPHABET) {
        if (diverge) return
        restore(saved)
        const next = run(st, q, trace)
        dfs(next, [...trace, q])
      }
      restore(saved)
    }
    dfs(it.init({}), [])
    // Seeded random sequences over a wider domain.
    const g = rng(opts.seed ?? 7)
    for (let i = 0; i < random && !diverge; i++) {
      restore(null)
      let st = it.init({})
      const trace: Req[] = []
      for (let j = 0; j < length && !diverge; j++) {
        const q: Req = {op: g.pick(['dispatch', 'disconnect', 'resume', 'lose', 'commit', 'abandon'] as const), a: g.int(3), w: g.int(3), g: g.int(3), t: g.int(8)}
        st = run(st, q, trace)
        trace.push(q)
      }
    }
  } finally { cleanup(dir) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({depth: Number(process.env.DEPTH ?? 3), random: Number(process.env.RANDOM_SEQS ?? 40)})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
