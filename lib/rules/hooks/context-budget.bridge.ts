// Bridge: hold hooks/context-budget.sh to the context-budget rules. Each run is one session: a transcript whose last
// main-chain assistant turn carries the usage, rewritten before every prompt; KIT_CTX_WINDOW and the two percentages
// are drawn per run. The band is computed by the proven band function and the machine is stepped beside the hook.
import {writeFileSync} from 'node:fs'
import {contextBand, contextBudget} from './context-budget.ts'
import {machine, rng, runHook, sandbox, Tally, join, type BridgeResult} from './_bridge.ts'

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const g = rng(31)
  const band = contextBand()
  for (let run = 0; run < 16; run++) {
    const s = sandbox()
    const window = g.pick([1000, 200000]), warn = g.pick([50, 65]), strong = g.pick([70, 90])
    const env = {...s.env, KIT_CTX_WINDOW: String(window), KIT_CTX_WARN_PCT: String(warn), KIT_CTX_STRONG_PCT: String(strong)}
    const tr = join(s.home, 'session.jsonl')
    const m = machine(contextBudget())
    for (let k = 0; k < 8; k++) {
      const pct = g.pick([10, 49, 50, 64, 65, 69, 70, 89, 90, 99])
      const ctx = Math.floor((window * pct) / 100)
      writeFileSync(tr, [
        JSON.stringify({type: 'user', message: {content: 'hi'}}),
        JSON.stringify({type: 'assistant', isSidechain: false, message: {model: 'claude-x', usage: {input_tokens: ctx - 10, cache_read_input_tokens: 10}}}),
        JSON.stringify({type: 'assistant', isSidechain: true, message: {model: 'claude-x', usage: {input_tokens: 1}}}),
      ].join('\n') + '\n')
      const b = band.run({ctx, window, warn, strong}).band
      const fired = m.step({band: b}).fired
      const r = runHook('context-budget.sh', {hook_event_name: 'UserPromptSubmit', session_id: `s${run}`, transcript_path: tr, prompt: 'x'}, {env})
      const hook = r.stdout.includes('Context ceiling') ? 2 : r.stdout.includes('Context budget') ? 1 : 0
      t.check(r.code === 0 && hook === fired, () => ({run, step: k, window, warn, strong, ctx, band: b, rule: fired, hook}))
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
