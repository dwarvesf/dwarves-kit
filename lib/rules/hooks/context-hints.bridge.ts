// Bridge: hold hooks/context-hints.sh's temporal line to the context-hints rule: seeded prompt times through
// CONTEXT_HINTS_NOW (forward, repeated, backwards, past six hours), a temp state dir, the line switched off sometimes.
import {contextHints} from './context-hints.ts'
import {machine, rng, runHook, sandbox, Tally, join, type BridgeResult} from './_bridge.ts'

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const g = rng(8)
  for (let run = 0; run < 14; run++) {
    const s = sandbox()
    const off = g.next() < 0.2
    const m = machine(contextHints(), {off})
    let now = 1_800_000_000
    for (let k = 0; k < 7; k++) {
      now += g.pick([0, 5, 90, 4000, 30000, -50])
      const want = m.step({now})
      const env: Record<string, string> = {...s.env, CONTEXT_HINTS_STATE: join(s.home, 'hints'), CONTEXT_HINTS_NOW: String(now), CONTEXT_HINTS_SKILLMAP: '/dev/null'}
      if (off) env.CONTEXT_HINTS_TEMPORAL = '0'
      const r = runHook('context-hints.sh', {session_id: `s-${run}`, prompt: 'hello'}, {env})
      const hook = {line: r.stdout.includes('Session time:'), nudge: r.stdout.includes('cache-hygiene')}
      t.check(r.code === 0 && hook.line === want.line && hook.nudge === want.nudge, () => ({run, step: k, now, off, rule: want, hook, out: r.stdout}))
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
