// Prove every goals-area rule, refute every kept broken variant, confirm every recorded finding is still refuted,
// and run the bridges to the real bash. Exit 0 only when all of that holds.
//
//   node goals/prove.ts                     everything (proofs, then bridges)
//   node goals/prove.ts --no-bridges        proofs only
//   node goals/prove.ts --only <name>[,..]  just those rules
// A JSON summary is written to $SUPERCOMPUTER_OUTPUT_DIR/goals-<names>.json when that is set.
//
// Shipped laws are proven with {from: 'any'} and must come back proven && checked && !assumes: the stores these rules
// model (attempt files, the registry, guard sidecars, the journal, ROADMAP boxes) are reloaded from disk.
import {writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {proveDecision, proveSteps} from 'gdp-wired'
import {RULES, type RuleEntry} from './index.ts'

const args = process.argv.slice(2)
const only = args.includes('--only') ? args[args.indexOf('--only') + 1].split(',') : null
const bridges = !args.includes('--no-bridges')
const picked = RULES.filter(e => !only || only.includes(e.name))

let failed = 0
const ok = (msg: string) => console.log(`ok    ${msg}`)
const bad = (msg: string) => { console.log(`FAIL  ${msg}`); failed++ }
const summary: Record<string, unknown>[] = []

function proveShipped(e: RuleEntry) {
  const r = e.make()
  const L = e.laws(r)
  const t0 = Date.now()
  if (e.kind === 'rule') {
    const v = proveSteps(r, L.laws, L.stepLaws, {from: 'any'})
    const good = v.proven && v.checked && !v.assumes
    const n = L.laws.length + L.stepLaws.length
    if (good) ok(`${e.name}: ${n} laws proven and checked from any state (${Date.now() - t0} ms)`)
    else bad(`${e.name}: ${JSON.stringify({proven: v.proven, checked: v.checked, assumes: v.assumes, goal: v.goal, stuck: v.stuck, why: v.why, witness: v.witness})}`)
    return {laws: n, proven: good, names: [...L.laws, ...L.stepLaws].map((l: any) => l.name)}
  }
  const res = (L.decisions ?? []).map((d: any) => ({name: d.name, v: proveDecision(d)}))
  const notProven = res.filter(x => !(x.v.proven && x.v.checked))
  if (!notProven.length) ok(`${e.name}: ${res.length} decision laws proven and checked (${Date.now() - t0} ms)`)
  else for (const x of notProven) bad(`${e.name}: '${x.name}' ${JSON.stringify({proven: x.v.proven, checked: x.v.checked, witness: x.v.witness})}`)
  return {laws: res.length, proven: !notProven.length, names: res.map(x => x.name)}
}

function refutedFindings(e: RuleEntry) {
  if (!e.findings) return []
  const r = e.make()
  const F = e.findings(r)
  const out: Record<string, unknown>[] = []
  for (const d of F.decisions ?? []) {
    const v = proveDecision(d)
    if (!v.proven) ok(`${e.name}: finding still refuted: '${d.name}' (witness ${JSON.stringify(v.witness)})`)
    else bad(`${e.name}: finding '${d.name}' is now PROVEN: update FINDINGS.md and move it into laws()`)
    out.push({law: d.name, refuted: !v.proven, witness: v.witness})
  }
  if (F.laws.length || F.stepLaws.length) {
    const v = proveSteps(r, [...e.laws(r).laws, ...F.laws], F.stepLaws, {from: 'any'})
    if (!v.proven) ok(`${e.name}: finding still refuted at '${v.goal}'`)
    else bad(`${e.name}: a recorded finding is now PROVEN`)
    out.push({law: v.goal, refuted: !v.proven, run: v.run})
  }
  return out
}

function refuteVariants(e: RuleEntry) {
  const out: Record<string, unknown>[] = []
  for (const variant of e.variants) {
    const b = e.make(variant)
    const L = e.laws(b, variant)
    let refused = false, at = ''
    if (e.kind === 'rule') {
      const v = proveSteps(b, L.laws, L.stepLaws, {from: 'any', search: false})
      refused = !v.proven; at = v.goal ?? ''
    } else {
      for (const d of L.decisions ?? []) { const v = proveDecision(d); if (!v.proven) { refused = true; at = d.name; break } }
    }
    const tag = e.fixed?.includes(variant) ? ' (the bash as it was found)' : ''
    if (refused) ok(`${e.name}/${variant}${tag}: refused at '${at}'`)
    else bad(`${e.name}/${variant}: a broken variant was proven`)
    out.push({variant, refused, at, asFound: !!tag})
  }
  return out
}

for (const e of picked) {
  const entry: Record<string, unknown> = {name: e.name, source: e.source}
  entry.shipped = proveShipped(e)
  entry.findings = refutedFindings(e)
  entry.variants = refuteVariants(e)
  summary.push(entry)
}

if (bridges) {
  for (const e of picked) {
    if (!e.bridge) continue
    const t0 = Date.now()
    const res = await e.bridge()
    const row = summary.find(s => s.name === e.name)!
    row.bridge = {...res, ms: Date.now() - t0}
    if (res.diverge) bad(`${e.name} bridge: diverged after ${res.agree} agreements: ${JSON.stringify(res.diverge)}`)
    else ok(`${e.name} bridge: ${res.agree} agreements with the real bash, no divergence (${Date.now() - t0} ms)`)
  }
}

if (process.env.SUPERCOMPUTER_OUTPUT_DIR) {
  writeFileSync(join(process.env.SUPERCOMPUTER_OUTPUT_DIR, `goals-${only ? only.join('+') : 'all'}.json`), JSON.stringify(summary, null, 1))
}
if (failed) { console.log(`${failed} failed`); process.exit(1) }
console.log(`all goals-area rules proven, variants refused, findings recorded${bridges ? ', bridges agree' : ''}`)
