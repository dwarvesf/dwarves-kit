// Bridge: lib/goal/goal-registry.sh (claim, release) against goalRegistry().interpreter().
// Sessions are separate git checkouts (the script records `worktree=` from the caller's toplevel); the registry is a
// temp GOAL_REGISTRY_DIR. Every sequence of three requests over a small alphabet is enumerated, then seeded random
// sequences. After each request the registry files are read back: a `<slug>.goal` file is an active claim, its
// `touches=` names the region, its `worktree=` the owner.
import {existsSync, readFileSync, readdirSync, rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {GLOBS, goalRegistry, type Variant} from './goal-registry.ts'
import {cell, cleanup, initRepo, lib, rng, sh, tmp, type BridgeResult} from './_bridge.ts'

type Req = {op: 'claim' | 'release', s: number, p: number, sess: number}
const SCRIPT = lib('goal/goal-registry.sh')
const SLUGS = 3, SESSIONS = 2

export async function bridge(opts: {depth?: number, random?: number, length?: number, seed?: number, variant?: Variant} = {}): Promise<BridgeResult> {
  const depth = opts.depth ?? 3, random = opts.random ?? 30, length = opts.length ?? 10
  const r = goalRegistry(opts.variant ?? 'shipped'), it = r.interpreter()
  const root = tmp('registry-'), reg = join(root, 'reg')
  const repos = Array.from({length: SESSIONS}, (_, i) => join(root, `wt${i}`))
  repos.forEach(initRepo)
  const real = repos.map(d => sh('git', ['-C', d, 'rev-parse', '--show-toplevel']).out.trim())
  const view = () => {
    const out: string[] = []
    for (let s = 0; s < SLUGS; s++) {
      const f = join(reg, `s${s}.goal`)
      if (!existsSync(f)) { out.push('-'); continue }
      const kv = Object.fromEntries(readFileSync(f, 'utf8').split('\n').filter(Boolean).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]))
      out.push(`${GLOBS.indexOf(kv.touches)}@${real.indexOf(kv.worktree)}`)
    }
    return out.join(' ')
  }
  const ruleView = (st: any) => Array.from({length: SLUGS}, (_, s) => cell(st, 'Active', s) ? `${cell(st, 'Reg', s)}@${cell(st, 'Owner', s)}` : '-').join(' ')
  const argv = (q: Req) => q.op === 'claim' ? ['claim', `s${q.s}`, 'normal', GLOBS[q.p]] : ['release', `s${q.s}`]
  let agree = 0, diverge: BridgeResult['diverge'] = null
  const run = (st: any, q: Req, trace: Req[]) => {
    const res = sh('bash', [SCRIPT, ...argv(q)], {cwd: repos[q.sess], env: {GOAL_REGISTRY_DIR: reg}})
    const next = it.step({}, st, r.encodeInput(q))
    const want = ruleView(next), got = view()
    if (want !== got) diverge = {trace: [...trace, q].map(x => `[session ${x.sess}] goal-registry.sh ${argv(x).join(' ')}`), rule: want, bash: got, exit: res.code, stderr: res.err.trim()}
    else agree++
    return next
  }
  const snap = () => existsSync(reg) ? Object.fromEntries(readdirSync(reg).map(f => [f, readFileSync(join(reg, f), 'utf8')])) : {}
  const restore = (s: Record<string, string>) => { rmSync(reg, {recursive: true, force: true}); sh('mkdir', ['-p', reg]); for (const [f, c] of Object.entries(s)) writeFileSync(join(reg, f), c) }
  const alphabet: Req[] = []
  for (let s = 0; s < 2; s++) for (const p of [0, 1, 2]) for (let sess = 0; sess < SESSIONS; sess++) alphabet.push({op: 'claim', s, p, sess})
  alphabet.push({op: 'release', s: 0, p: 0, sess: 0}, {op: 'release', s: 1, p: 0, sess: 1}, {op: 'claim', s: 2, p: 3, sess: 1})
  try {
    const dfs = (st: any, trace: Req[]) => {
      if (diverge || trace.length === depth) return
      const saved = snap()
      for (const q of alphabet) { if (diverge) return; restore(saved); dfs(run(st, q, trace), [...trace, q]) }
      restore(saved)
    }
    dfs(it.init({}), [])
    const g = rng(opts.seed ?? 11)
    for (let i = 0; i < random && !diverge; i++) {
      restore({}); let st = it.init({}); const trace: Req[] = []
      for (let j = 0; j < length && !diverge; j++) {
        const q: Req = {op: g.next() < 0.75 ? 'claim' : 'release', s: g.int(SLUGS), p: g.int(4), sess: g.int(SESSIONS)}
        st = run(st, q, trace); trace.push(q)
      }
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({depth: Number(process.env.DEPTH ?? 3), random: Number(process.env.RANDOM_SEQS ?? 30), variant: (process.env.VARIANT as Variant) ?? 'shipped'})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
