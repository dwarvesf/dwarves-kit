// Prove every kit rule: the verification loop here, then each area's rules (gates, goals, specs, wrap, hooks).
// Exit 0 only when every law is proven AND kernel-checked (stateful rules from any state, with no reachability
// assumption), every kept broken variant is refused, and every recorded finding is still refuted.
//
//   node prove.ts              proofs only (about a minute): what tests/test-rules.sh runs
//   node prove.ts --bridges    also run every bridge: each rule beside the real bash it mirrors (minutes; spawns
//                              thousands of bash runs in temp sandboxes, so run it through supercomputer)
import {spawnSync} from 'node:child_process'
import {dirname, join} from 'node:path'
import {fileURLToPath} from 'node:url'
import {proveSteps} from 'gdp-wired'
import {laws as verifyLaws, verifyLoop, type Variant} from './verify-loop.ts'

const here = dirname(fileURLToPath(import.meta.url))
const bridges = process.argv.includes('--bridges')
let failed = 0
const ok = (msg: string) => console.log(`ok    ${msg}`)
const bad = (msg: string) => { console.log(`FAIL  ${msg}`); failed++ }

// The verification pipeline's retry loop (commands/execute.md, run by bin/verify-loop).
{
  const r = verifyLoop()
  const {laws, stepLaws} = verifyLaws(r)
  const v = proveSteps(r, laws, stepLaws, {from: 'any'})
  if (v.proven && v.checked && !v.assumes) ok(`verify-loop: ${laws.length + stepLaws.length} laws proven and checked from any state`)
  else bad(`verify-loop: ${JSON.stringify({proven: v.proven, checked: v.checked, assumes: v.assumes, goal: v.goal, stuck: v.stuck, why: v.why, witness: v.witness})}`)
  for (const variant of ['uncapped', 'known-spends', 'escalate-retried'] as Variant[]) {
    const broken = verifyLoop(variant)
    const bl = verifyLaws(broken)
    const bv = proveSteps(broken, bl.laws, bl.stepLaws, {from: 'any', search: false})
    if (!bv.proven) ok(`verify-loop/${variant}: refused at '${bv.goal}'`)
    else bad(`verify-loop/${variant}: a broken variant was proven`)
  }
}

// Each area owns its prover (rules, kept variants, recorded findings, and its bridges).
for (const area of ['gates', 'goals', 'specs', 'wrap', 'hooks']) {
  const t = Date.now()
  const run = spawnSync(process.execPath, [join(here, area, 'prove.ts'), ...(bridges ? [] : ['--no-bridges'])],
    {cwd: here, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024})
  const out = `${run.stdout ?? ''}${run.stderr ?? ''}`
  const last = out.trim().split('\n').at(-1) ?? ''
  if (run.status === 0) ok(`${area}: ${last} (${((Date.now() - t) / 1000).toFixed(0)} s)`)
  else { bad(`${area}: exit ${run.status}`); console.log(out.split('\n').filter((l) => /FAIL|Error|error/.test(l)).slice(0, 40).join('\n')) }
}

if (failed) { console.log(`${failed} failed`); process.exit(1) }
console.log(`all kit rules proven${bridges ? ', every bridge agrees with the real bash' : ''}`)
