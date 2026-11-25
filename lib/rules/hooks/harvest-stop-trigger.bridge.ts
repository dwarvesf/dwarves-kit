// Bridge: hold hooks/harvest.sh --stop-trigger to the rule. Stop payloads carry no transcript_path, so a fire ends
// right after the decision (no detached harvest, no model call); a skip prints "stop-trigger skip".
import {harvestStopTrigger} from './harvest-stop-trigger.ts'
import {machine, rng, runHook, sandbox, Tally, join, type BridgeResult} from './_bridge.ts'

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const g = rng(67)
  for (let run = 0; run < 8; run++) {
    const s = sandbox()
    const on = g.next() < 0.8, n = g.pick([1, 2, 3, 5])
    const env: Record<string, string> = {...s.env, HARVEST_STATE_DIR: join(s.home, 'h'), HARVEST_STOP_N: String(n)}
    if (on) env.HARVEST_STOP_TRIGGER = '1'
    const m = machine(harvestStopTrigger(), {on, n})
    for (let k = 0; k < 7; k++) {
      const want = m.step({}).fired
      const r = runHook('harvest.sh', {hook_event_name: 'Stop', session_id: `st-${run}`}, {env, args: ['--stop-trigger']})
      const skipped = r.stderr.includes('stop-trigger skip')
      const fired = on && r.code === 0 && !skipped
      t.check(r.code === 0 && fired === want, () => ({run, turn: k, on, n, rule: want, hook: {code: r.code, stderr: r.stderr.trim()}}))
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
