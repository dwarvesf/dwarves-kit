// Prove every rule of the specs, board and intake area, refuse every kept broken variant, refute every law listed
// as a finding, and run the bridges (the real bash beside each rule) and the findings' replays.
// Exit 0 only when: each rule's laws are proven AND kernel-checked (step laws from ANY state, no `assumes`: the
// ledgers and files are reloaded from disk), each variant is refused, each finding law is refuted, each bridge
// agrees with no divergence, and each finding's counterexample reproduces on the real bash.
//
//   node prove.ts                  proofs and bridges
//   node prove.ts --no-bridges     proofs only (a few seconds)
//   node prove.ts --only <name>    one rule
//   node prove.ts --json <file>    also write the summary there
// With SUPERCOMPUTER_OUTPUT_DIR set, the summary is also written to $SUPERCOMPUTER_OUTPUT_DIR/specs-prove.json.
import {proveDecision, proveSteps} from 'gdp-wired'
import {spawn} from 'node:child_process'
import {writeFileSync} from 'node:fs'
import {dirname, join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {RULES, type Entry} from './index.ts'

const HERE = dirname(fileURLToPath(import.meta.url))
const args = process.argv.slice(2)
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : null
const bridges = !args.includes('--no-bridges')
let failed = 0
const ok = (msg: string) => console.log(`ok    ${msg}`)
const bad = (msg: string) => { console.log(`FAIL  ${msg}`); failed++ }
const summary: Record<string, any> = {}

function proveAll(e: Entry, r: any, ls: {laws: any[], stepLaws: any[], decisions?: any[]}, search = true) {
  const out: {name: string, proven: boolean, checked: boolean, assumes: unknown, goal?: string, witness?: unknown}[] = []
  if (ls.laws.length || ls.stepLaws.length) {
    const v = proveSteps(r, ls.laws, ls.stepLaws, search ? {from: 'any'} : {from: 'any', search: false})
    out.push({name: `${ls.laws.length + ls.stepLaws.length} laws`, proven: v.proven, checked: v.checked, assumes: v.assumes, goal: v.goal, witness: v.witness})
  }
  for (const d of ls.decisions ?? []) {
    const v = proveDecision(d)
    out.push({name: d.name, proven: v.proven, checked: v.checked, assumes: undefined, goal: v.goal, witness: v.witness})
  }
  return out
}

for (const e of RULES) {
  if (only && e.name !== only) continue
  const s: any = summary[e.name] = {source: e.source, fixed: e.fixed ?? null}
  const r = e.make()
  const ls = e.laws(r)
  const n = ls.laws.length + ls.stepLaws.length + (ls.decisions?.length ?? 0)
  const res = proveAll(e, r, ls)
  const broken = res.filter(x => !(x.proven && x.checked && !x.assumes))
  s.laws = n
  s.lawNames = [...ls.laws, ...ls.stepLaws, ...(ls.decisions ?? [])].map((l: any) => l.name)
  if (!broken.length) ok(`${e.name}: ${n} laws proven and checked${e.kind === 'rule' ? ' from any state' : ''}`)
  else bad(`${e.name}: ${JSON.stringify(broken)}`)
  s.proven = !broken.length
  s.variants = {}
  for (const v of e.variants) {
    const b = e.make(v)
    const bres = proveAll(e, b, e.laws(b), false)
    const refusedAt = bres.find(x => !x.proven)
    s.variants[v] = refusedAt ? refusedAt.goal ?? refusedAt.name : null
    if (refusedAt) ok(`${e.name}/${v}: refused at '${refusedAt.goal ?? refusedAt.name}'`)
    else bad(`${e.name}/${v}: a broken variant was proven`)
  }
  s.findings = []
  if (e.refuted) {
    const fl = e.refuted(r)
    for (const l of [...fl.laws, ...fl.stepLaws, ...(fl.decisions ?? [])]) {
      const one = fl.decisions?.includes(l) ? {laws: [], stepLaws: [], decisions: [l]}
        : fl.laws.includes(l) ? {laws: [l], stepLaws: [], decisions: []} : {laws: [], stepLaws: [l], decisions: []}
      const [v] = proveAll(e, r, one)
      s.findings.push({law: l.name, refuted: !v.proven, witness: v.witness ?? null})
      if (!v.proven) ok(`${e.name}: finding '${l.name}' is refuted (witness ${JSON.stringify(v.witness)})`)
      else bad(`${e.name}: finding '${l.name}' was proven; it is no finding`)
    }
  }
}

function runBridge(file: string): Promise<any> {
  return new Promise(resolve => {
    const p = spawn(process.execPath, [join(HERE, file)], {cwd: HERE, stdio: ['ignore', 'pipe', 'pipe']})
    let out = '', err = ''
    p.stdout.on('data', d => { out += d }); p.stderr.on('data', d => { err += d })
    p.on('close', code => { try { resolve(JSON.parse(out)) } catch { resolve({error: `exit ${code}: ${err.slice(0, 500)}`}) } })
  })
}

if (bridges) {
  const todo = RULES.filter(e => e.bridgeFile && (!only || e.name === only))
  const results: Record<string, any> = {}
  const queue = [...todo]
  const workers = Array.from({length: Math.min(6, queue.length)}, async () => {
    for (let e = queue.shift(); e; e = queue.shift()) results[e.name] = await runBridge(e.bridgeFile!)
  })
  await Promise.all(workers)
  for (const e of todo) {
    const x = results[e.name], s = summary[e.name]
    s.bridge = x.bridge ?? {error: x.error}
    if (x.bridge && x.bridge.diverge === null && x.bridge.agree > 0) ok(`${e.name}: bridge agrees on ${x.bridge.agree} steps`)
    else bad(`${e.name}: bridge ${JSON.stringify(x.bridge ?? x.error)}`)
    for (const c of x.confirm ?? []) {
      const f = s.findings.find((y: any) => y.law === c.law)
      if (f) f.bash = c
      if (c.reproduced) ok(`${e.name}: finding '${c.law}' reproduces on the real bash`)
      else bad(`${e.name}: finding '${c.law}' does not reproduce: ${JSON.stringify(c)}`)
    }
  }
}

if (process.env.SUPERCOMPUTER_OUTPUT_DIR) writeFileSync(join(process.env.SUPERCOMPUTER_OUTPUT_DIR, 'specs-prove.json'), JSON.stringify({failed, summary}, null, 1))
if (args.includes('--json')) writeFileSync(args[args.indexOf('--json') + 1], JSON.stringify({failed, summary}, null, 1))
if (failed) { console.log(`${failed} failed`); process.exit(1) }
console.log('all specs-area rules proven')
