// Bridge: a second conductor against a slug another conductor holds, real bash against queueConductors().
// Conductor c0 is "running" the way the real one is seen from outside: its heartbeat file exists. Conductor c1 is a
// real process: either a watcher tick that planned the slug before c0 launched and then runs `queue.sh run` on its
// plan (`watcher`), or a hand `queue.sh run` (`hand`). Whether c1 opened a window for the slug (fake mux `new-window`)
// is compared with whether the rule lets c1 reach `running`.
import {rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {queueConductors, PCS, type Variant} from './queue-conductors.ts'
import {queueEnv, SLUG} from './_queue-env.ts'
import {cleanup, tmp, type BridgeResult} from './_bridge.ts'

export async function bridge(opts: {variant?: Variant} = {}): Promise<BridgeResult> {
  const r = queueConductors(opts.variant ?? 'shipped'), it = r.interpreter()
  const root = tmp('qcond-')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    let n = 0
    for (const mode of ['watcher', 'hand'] as const) for (const busy of [false, true]) for (const outcome of ['stalled', 'done'] as const) {
      if (diverge) break
      const q = queueEnv(join(root, `case${n++}`))
      if (outcome === 'done') { writeFileSync(join(q.qstub, `${SLUG}.transcript`), '  RUNNER_DONE\n'); writeFileSync(join(q.qstub, `${SLUG}.work`), '') }
      // --- the rule: c1 plans first (watcher), c0 launches if busy, then c1 launches
      const step = (st: any, who: 'c0' | 'c1', op: 'plan' | 'launch' | 'finish', hand: 'watcher' | 'hand' = 'watcher') => it.step({}, st, r.encodeInput({who, op, hand}))
      let st: any = it.init({})
      if (mode === 'watcher') st = step(st, 'c1', 'plan')
      if (busy) st = step(st, 'c0', 'launch', 'hand')
      st = step(st, 'c1', 'launch', mode)
      const want = PCS[st.scalars.pc1] === 'running'
      // --- the real scripts
      let planned = true
      if (mode === 'watcher') planned = q.watch().out.includes('[watch] ID-001 ->')
      if (busy) writeFileSync(join(q.runDir, `${SLUG}.beat`), '')
      if (planned) q.run([[SLUG, q.repo, q.pointer]])
      const got = q.windows().includes(SLUG)
      if (want !== got) diverge = {c1: mode, c0_running: busy, run_outcome: outcome, rule_c1_launches: want, bash_c1_opened_window: got, journal: q.journalRows(SLUG)}
      else agree++
      // the beat c0 holds must survive c1's attempt (only c0's own finish clears it)
      if (busy && !diverge && !q.beat()) diverge = {c1: mode, c0_running: busy, run_outcome: outcome, problem: "c0's heartbeat was cleared by c1"}
      rmSync(join(q.runDir, `${SLUG}.beat`), {force: true})
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const res = await bridge({variant: (process.env.VARIANT as Variant) ?? 'shipped'})
  console.log(JSON.stringify(res, null, 1))
  process.exit(res.diverge ? 1 : 0)
}
