// Bridge: hold hooks/batch-debt-warn.sh to the batch-debt-warn rule over seeded runs of Bash commands in a temp ledger
// (KIT_LEDGER_DIR), two sessions interleaved, lane START lines dropped into runs/*.log before or after the first merge.
import {appendFileSync, mkdirSync} from 'node:fs'
import {batchDebtWarn} from './batch-debt-warn.ts'
import {machine, rng, runHook, sandbox, Tally, join, type BridgeResult} from './_bridge.ts'

const CMDS: [string, boolean][] = [['gh pr merge 41 --squash', true], ['cd repo && gh pr merge --auto', true], ['gh pr merge', true],
  ['gh pr view 41', false], ['echo gh pr merge', false], ['git status', false], ['ls\ngh pr merge 3', false]]

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const g = rng(23)
  for (let run = 0; run < 12; run++) {
    const s = sandbox()
    const ledger = s.env.KIT_LEDGER_DIR
    const ms = {a: machine(batchDebtWarn()), b: machine(batchDebtWarn())}
    const firstMerge: Record<string, boolean> = {a: false, b: false}
    let started = false // a START stamped after every session's first merge (2099), or before all (2000)
    for (let k = 0; k < 10; k++) {
      if (g.next() < 0.15) {
        const future = g.bool()
        mkdirSync(join(ledger, 'runs'), {recursive: true})
        appendFileSync(join(ledger, 'runs', 'r.log'), `${future ? '2099-01-01T00:00:00Z' : '2000-01-01T00:00:00Z'} | START | lane\n`)
        if (future) started = true
      }
      const sid = g.pick(['a', 'b'] as const)
      const [cmd, merge] = g.pick(CMDS)
      const want = ms[sid].step({merge, ledger: true, started}).last
      if (merge) firstMerge[sid] = true
      const r = runHook('batch-debt-warn.sh', {tool_name: 'Bash', session_id: `sess-${sid}`, tool_input: {command: cmd}}, {env: s.env})
      const warned = r.stdout.includes('Batch-debt warning')
      t.check(r.code === 0 && warned === want, () => ({run, step: k, sid, cmd, started, rule: want, hook: {code: r.code, warned}}))
    }
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
