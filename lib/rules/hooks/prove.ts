// Prove every hooks-and-autonomy rule, refute every kept broken variant, keep every refuted promise refuted, and run
// the bridges that hold the real bash to the rules. Exit 0 only when all of that holds.
//
//   node prove.ts                  proofs and bridges
//   node prove.ts --no-bridges     proofs only (seconds)
//   node prove.ts --only <name>    one rule
// A stateful rule's laws are proven from any state the laws allow ({from: 'any'}, no `assumes`): every one of these
// hooks reloads its state from disk (a ledger, a stamp, a cache file, a marker) or from the host (stop_hook_active).
import {mkdirSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {proveDecision, proveSteps} from 'gdp-wired'
import {RULES} from './index.ts'

const args = process.argv.slice(2)
const bridges = !args.includes('--no-bridges')
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : undefined
let failed = 0
const ok = (msg: string) => console.log(`ok    ${msg}`)
const bad = (msg: string) => { console.log(`FAIL  ${msg}`); failed++ }
const report: Record<string, unknown>[] = []

function proveAll(r: any, L: ReturnType<typeof RULES[number]['laws']>, search: boolean) {
  const out: {proven: boolean, goal?: string, detail?: unknown}[] = []
  if (L.laws.length || L.stepLaws.length) {
    const v = proveSteps(r, L.laws, L.stepLaws, search ? {from: 'any'} : {from: 'any', search: false})
    out.push({proven: !!(v.proven && v.checked && !v.assumes), goal: v.goal, detail: {stuck: v.stuck, why: v.why, assumes: v.assumes, witness: v.witness}})
  }
  for (const d of L.decisions ?? []) {
    const v = proveDecision(d)
    out.push({proven: !!(v.proven && v.checked), goal: v.goal ?? (d as any).name, detail: {witness: v.witness}})
  }
  return out
}

for (const e of RULES) {
  if (only && e.name !== only) continue
  const r = e.make()
  const L = e.laws(r)
  const n = L.laws.length + L.stepLaws.length + (L.decisions?.length ?? 0)
  const res = proveAll(r, L, true)
  const failing = res.filter((x) => !x.proven)
  if (!failing.length) ok(`${e.name}: ${n} laws proven and checked${e.kind === 'stateful' ? ' from any state' : ''}`)
  else for (const f of failing) bad(`${e.name}: ${f.goal} ${JSON.stringify(f.detail)}`)
  const entry: Record<string, unknown> = {name: e.name, source: e.source, laws: n, proven: !failing.length, variants: {}, refuted: [] as unknown[]}

  for (const v of e.variants) {
    const rv = e.make(v)
    const bres = proveAll(rv, e.laws(rv), false)
    const hit = bres.find((x) => !x.proven)
    if (hit) ok(`${e.name}/${v}: refused at '${hit.goal}'`)
    else bad(`${e.name}/${v}: a broken variant was proven`)
    ;(entry.variants as Record<string, string>)[v] = hit ? `refuted at '${hit.goal}'` : 'PROVEN (bad)'
  }

  // Promised laws the code-faithful rule refutes: they must stay refuted (a finding fixed later shows up here).
  for (const s of L.refutedSteps ?? []) {
    const v = proveSteps(r, L.laws, [s])
    if (!v.proven) ok(`${e.name}: promise refuted, as recorded: '${s.name}' run=${JSON.stringify((v as any).run ?? v.witness)}`)
    else bad(`${e.name}: recorded refutation now proven: '${s.name}' (update FINDINGS.md)`)
    ;(entry.refuted as unknown[]).push({law: s.name, run: (v as any).run ?? v.witness})
  }
  for (const d of L.refutedDecisions ?? []) {
    const v = proveDecision(d)
    if (!v.proven) ok(`${e.name}: promise refuted, as recorded: '${(d as any).name ?? v.goal}' witness=${JSON.stringify(v.witness)}`)
    else bad(`${e.name}: recorded refutation now proven: '${(d as any).name}' (update FINDINGS.md)`)
    ;(entry.refuted as unknown[]).push({law: (d as any).name ?? v.goal, witness: v.witness})
  }

  if (bridges && e.bridge) {
    const t0 = Date.now()
    const b = await e.bridge()
    const secs = ((Date.now() - t0) / 1000).toFixed(1)
    if (b.diverge === null) ok(`${e.name}: bridge agrees on ${b.agree} runs of the real hook (${secs}s)`)
    else bad(`${e.name}: bridge diverges after ${b.agree} agreements: ${JSON.stringify(b.diverge)}`)
    for (const note of b.notes ?? []) console.log(`      note: ${note}`)
    entry.bridge = {agree: b.agree, diverge: b.diverge, notes: b.notes, seconds: Number(secs)}
  }
  report.push(entry)
}

const out = process.env.SUPERCOMPUTER_OUTPUT_DIR
if (out) { mkdirSync(out, {recursive: true}); writeFileSync(join(out, 'hooks-prove.json'), JSON.stringify(report, null, 2)) }
if (failed) { console.log(`${failed} failed`); process.exit(1) }
console.log('all hooks rules proven, variants refuted, bridges agree')
