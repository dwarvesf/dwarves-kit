// Bridge: hold hooks/output-offload.sh to the rule with generated PostToolUse payloads (string, {content}, {stdout},
// arrays) of sizes around the budget, a large tool_input with a small output, and an unwritable cache.
import {chmodSync, mkdirSync} from 'node:fs'
import {outputOffload} from './output-offload.ts'
import {rng, runHook, sandbox, Tally, join, type BridgeResult} from './_bridge.ts'

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const f = outputOffload()
  const g = rng(41)
  for (let i = 0; i < 60; i++) {
    const s = sandbox()
    const max = 50, budget = max * 4
    const n = g.pick([10, 150, 199, 200, 201, 400, 2000])
    const text = 'y'.repeat(n)
    const shape = g.pick(['string', 'content', 'stdout', 'array'])
    const resp = shape === 'string' ? text : shape === 'content' ? {content: [{type: 'text', text}]} : shape === 'stdout' ? {stdout: text, stderr: ''} : [{text}]
    const bigInput = g.next() < 0.25
    const payload = {tool_name: 'Read', tool_input: {file_path: bigInput ? 'p'.repeat(500) : 'x'}, tool_response: resp}
    // {stdout} joins its fields with newlines, but $(...) strips the trailing ones: the text is what is measured.
    const flat = text
    const writable = g.next() < 0.85
    const cache = join(s.home, 'cache')
    mkdirSync(cache, {recursive: true})
    if (!writable) chmodSync(cache, 0o500)
    const env = {...s.env, OFFLOAD_MAX_TOKENS: String(max), XDG_CACHE_HOME: cache}
    const raw = JSON.stringify(payload).length
    const facts = {payloadOver: raw > budget, responseOver: raw > budget && flat.length > budget, writable}
    const out = f.run(facts)
    const r = runHook('output-offload.sh', payload, {env})
    const hook = r.stdout.includes('output was large')
    t.check(r.code === 0 && hook === out.offload, () => ({case: i, n, shape, bigInput, facts, rule: out, hook: {code: r.code, offloaded: hook}}))
    chmodSync(cache, 0o700)
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
