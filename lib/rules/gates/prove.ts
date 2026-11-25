// Prove every rule of the gates area, assert every kept broken variant is refused and every recorded finding is
// still refuted, then run the bridges against the real bash. Exit 0 only when all of that holds.
//
//   node gates/prove.ts                     proofs + bridges (the bridges spawn bash: minutes; run them through
//                                           supercomputer, see FINDINGS.md "Reproducing")
//   node gates/prove.ts --no-bridges        proofs only
//   node gates/prove.ts --only a,b          only the named entries (a bridge runs with the entry that carries it)
//   node gates/prove.ts --bridges-only      bridges only
// With $SUPERCOMPUTER_OUTPUT_DIR (or --json <file>) the results are also written as JSON.
import {writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {proveDecision, proveSteps} from 'gdp-wired'
import {RULES, type Entry, type Laws} from './index.ts'

const argv = process.argv.slice(2)
const flag = (f: string) => argv.includes(f)
const opt = (f: string) => { const i = argv.indexOf(f); return i >= 0 ? argv[i + 1] : undefined }
const only = opt('--only')?.split(',')
const doProofs = !flag('--bridges-only'), doBridges = !flag('--no-bridges')

let failed = 0
const ok = (m: string) => console.log(`ok    ${m}`)
const bad = (m: string) => { console.log(`FAIL  ${m}`); failed++ }
const results: Record<string, any> = {}

function proveAll(e: Entry, r: any, l: Laws, opts: {from?: 'any', search?: false}) {
  if (e.kind === 'fun') {
    const vs = (l.decisions ?? []).map((d: any) => ({name: d.name, v: proveDecision(d)}))
    return {proven: vs.every(x => x.v.proven && x.v.checked), count: vs.length,
      failing: vs.filter(x => !(x.v.proven && x.v.checked)).map(x => ({goal: x.name, witness: x.v.witness}))}
  }
  const v = proveSteps(r, l.laws, l.stepLaws, opts)
  return {proven: v.proven && v.checked && !v.assumes, count: l.laws.length + l.stepLaws.length,
    failing: v.proven ? [] : [{goal: v.goal, stuck: v.stuck, witness: v.witness}], assumes: v.assumes}
}

for (const e of RULES) {
  if (only && !only.includes(e.name) && !(e.bridgeOf && only.includes(e.bridgeOf))) continue
  const res: any = (results[e.name] = {source: e.source})
  if (doProofs) {
    const r = e.make(), l = e.laws(r)
    const v = proveAll(e, r, l, {from: 'any'})
    res.laws = v.count; res.proven = v.proven
    if (v.proven) ok(`${e.name}: ${v.count} laws proven and checked${e.kind === 'rule' ? ' from any state' : ''}`)
    else bad(`${e.name}: ${JSON.stringify(v.failing)}`)
    res.variants = {}
    for (const variant of e.variants) {
      const b = e.make(variant), bl = e.laws(b)
      const bv = proveAll(e, b, bl, {from: 'any', search: false})
      res.variants[variant] = bv.proven ? 'PROVEN (bad)' : `refused at '${bv.failing[0]?.goal}'`
      if (!bv.proven) ok(`${e.name}/${variant}: refused at '${bv.failing[0]?.goal}'`)
      else bad(`${e.name}/${variant}: a broken variant was proven`)
    }
    if (e.refuted) {
      const rl = e.refuted(r)
      res.refuted = []
      for (const d of rl.decisions ?? []) {
        const v2 = proveDecision(d)
        res.refuted.push({law: d.name, refuted: !v2.proven, counterexample: v2.witness})
        if (!v2.proven) ok(`${e.name}: finding still refuted: '${d.name}' at ${JSON.stringify(v2.witness)}`)
        else bad(`${e.name}: recorded finding '${d.name}' is now proven: update FINDINGS.md`)
      }
      for (const s of rl.stepLaws) {
        const v2 = proveSteps(r, rl.laws, [s], {search: false})
        const run = v2.run ?? v2.witness
        res.refuted.push({law: s.name, refuted: !v2.proven, counterexample: run ?? v2.witness})
        if (!v2.proven) ok(`${e.name}: finding still refuted: '${s.name}' run ${JSON.stringify(run)}`)
        else bad(`${e.name}: recorded finding '${s.name}' is now proven: update FINDINGS.md`)
      }
    }
  }
  if (doBridges && e.bridge) {
    const t = Date.now()
    const b = await e.bridge()
    res.bridge = {...b, seconds: Math.round((Date.now() - t) / 1000)}
    if (!b.diverge) ok(`${e.name}: bridge agrees with the real bash on ${b.agree} cases (${res.bridge.seconds}s)`)
    else bad(`${e.name}: bridge diverges after ${b.agree} agreements: ${JSON.stringify(b.diverge)}`)
  }
}

const out = opt('--json') ?? (process.env.SUPERCOMPUTER_OUTPUT_DIR ? join(process.env.SUPERCOMPUTER_OUTPUT_DIR, `gates-${only?.join('+') ?? 'all'}.json`) : undefined)
if (out) writeFileSync(out, JSON.stringify({failed, results}, null, 2))
if (failed) { console.log(`${failed} failed`); process.exit(1) }
console.log('all gates rules proven, variants refused, findings refuted, bridges agree')
