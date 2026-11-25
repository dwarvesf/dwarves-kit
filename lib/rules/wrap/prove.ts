// Prove every wrap-area rule, refute every kept broken variant, confirm each refuted promised law (a finding left
// unfixed) with a real run, and run the bridges against the real bash. Exit 0 only when all of that holds.
//   node wrap/prove.ts                  proofs, variants and bridges
//   node wrap/prove.ts --no-bridges     proofs and variants only
//   node wrap/prove.ts --only <name>    one rule
// Every law is proven from ANY state the laws allow ({from: 'any'}), never with an assumption about reachability:
// the bash reloads its state from disk (sentinel files, ledgers, worktree lists) on every call.
import {proveDecision, proveLeadsTo, proveSteps} from 'gdp-wired'
import {search} from 'gdp-wired/machine'
import {RULES} from './index.ts'

const args = process.argv.slice(2)
const only = args.includes('--only') ? args[args.indexOf('--only') + 1] : undefined
const bridges = !args.includes('--no-bridges')
let failed = 0
const ok = (msg: string) => console.log(`ok    ${msg}`)
const bad = (msg: string) => { console.log(`FAIL  ${msg}`); failed++ }

function proveAll(r: any, l: ReturnType<typeof RULES[number]['laws']>, refutes: string[], search_: boolean) {
  if (l.decisions?.length) {
    for (const d of l.decisions) {
      const v = proveDecision(d)
      if (!(v.proven && v.checked)) return {proven: false, goal: v.goal ?? (d as any).name, witness: v.witness}
    }
    return {proven: true, n: l.decisions.length}
  }
  const keep = l.laws.filter((x: any) => !refutes.includes(x.name))
  const v = proveSteps(r, keep, l.stepLaws, {from: 'any', ...(search_ ? {} : {search: false})})
  return {proven: v.proven && v.checked && !v.assumes, goal: v.goal, stuck: v.stuck, witness: v.witness, assumes: v.assumes, n: keep.length + l.stepLaws.length}
}

for (const e of RULES) {
  if (only && e.name !== only) continue
  const t = Date.now()
  const r = e.make()
  const l = e.laws(r)
  const refutes = e.refutes ?? []
  const v = proveAll(r, l, refutes, true)
  if (v.proven) ok(`${e.name}: ${v.n} laws proven and kernel-checked${l.decisions?.length ? '' : ' from any state'} (${Date.now() - t} ms)`)
  else bad(`${e.name}: ${JSON.stringify(v)}`)

  for (const live of e.liveness?.(r) ?? []) {
    const lv = proveLeadsTo(r, l.laws, live)
    if (lv.proven && lv.checked) ok(`${e.name}: liveness '${(live as any).name ?? 'leads-to'}' proven`)
    else bad(`${e.name}: liveness ${JSON.stringify({goal: lv.goal, stuck: lv.stuck, why: lv.why})}`)
  }

  for (const name of refutes) {
    const law = l.laws.find((x: any) => x.name === name)
    if (!law) { bad(`${e.name}: refuted law '${name}' not found`); continue }
    const run = search(r.machine, law)
    if (run) ok(`${e.name}: promised law REFUTED (finding) '${name}': run ${JSON.stringify(run)}`)
    else bad(`${e.name}: expected '${name}' refuted, no run found`)
  }

  for (const variant of e.variants) {
    const b = e.make(variant)
    const bv = proveAll(b, e.laws(b), refutes, false)
    if (!bv.proven) ok(`${e.name}/${variant}: refused at '${bv.goal}'`)
    else bad(`${e.name}/${variant}: a broken variant was proven`)
  }
}

if (bridges) {
  for (const e of RULES) {
    if (only && e.name !== only) continue
    if (!e.bridge) continue
    const t = Date.now()
    try {
      const b = await e.bridge()
      if (b.diverge) bad(`bridge ${e.name}: ${b.agree} agreed, then diverged: ${JSON.stringify(b.diverge)}`)
      else ok(`bridge ${e.name}: ${b.agree} agreed${b.notes ? ` (${b.notes.join(', ')})` : ''} (${Math.round((Date.now() - t) / 1000)} s)`)
    } catch (err) {
      bad(`bridge ${e.name}: threw ${(err as Error).stack}`)
    }
  }
}

if (failed) { console.log(`${failed} failed`); process.exit(1) }
console.log('all wrap-area rules proven, variants refused, bridges agree')
