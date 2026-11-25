// Bridge: one real `queue.sh run` over a generated plan of rows, against queueNight().
// Each row is a distinct slug made to meet cmd_run as one request kind: `terminal` (a done row already journaled),
// `skip` (its repo is missing), `held` (another conductor's heartbeat exists), or `run` with a verdict (fake-mux
// transcript / dead window / EXIT_SIGNAL status) and a self-reported TOOL_CALLS count. --max-megas and the queue-wide
// tool-call ceiling are drawn too. Which rows opened a window and each slug's journal verdict are compared with the rule.
import {writeFileSync, appendFileSync} from 'node:fs'
import {join} from 'node:path'
import {queueNight} from './queue-night.ts'
import {queueEnv} from './_queue-env.ts'
import {cleanup, rng, tmp, type BridgeResult} from './_bridge.ts'

type Row = {kind: 'terminal' | 'skip' | 'held' | 'run', v: 'done' | 'gated' | 'stalled' | 'error', calls: number}

export async function bridge(opts: {nights?: number, seed?: number} = {}): Promise<BridgeResult> {
  const nights = opts.nights ?? 25
  const r = queueNight(), it = r.interpreter()
  const g = rng(opts.seed ?? 5)
  const root = tmp('qnight-')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  try {
    for (let n = 0; n < nights && !diverge; n++) {
      const q = queueEnv(join(root, `n${n}`))
      const max = g.pick([0, 0, 2, 3]), maxTotal = g.pick([0, 0, 5])
      const rows: Row[] = Array.from({length: 3 + g.int(4)}, () => ({
        kind: g.pick(['terminal', 'skip', 'held', 'run', 'run', 'run'] as const),
        v: g.pick(['done', 'gated', 'stalled', 'error'] as const), calls: g.pick([0, 3]),
      }))
      const plan = rows.map((row, i) => {
        const slug = `r${i}`
        if (row.kind === 'terminal') appendFileSync(q.journal, `2026-01-01T00:00:00Z\t${slug}\tdone\t\n`)
        if (row.kind === 'held') writeFileSync(join(q.runDir, `${slug}.beat`), '')
        if (row.kind === 'run') {
          const st = (row.v === 'done' ? 'EXIT_SIGNAL: true' : row.v === 'gated' ? 'EXIT_SIGNAL: true\\nREASON: needs a human' : 'EXIT_SIGNAL: false') + `\\nTOOL_CALLS: ${row.calls}\\n`
          writeFileSync(join(q.qstub, `${slug}.during`), `printf '${st}' > "$KIT_LEDGER_DIR/queue-runs/${slug}.status"\n`)
          if (row.v === 'done') writeFileSync(join(q.qstub, `${slug}.work`), '')
          if (row.v === 'error') writeFileSync(join(q.qstub, `${slug}.dead`), '')
        }
        return [slug, row.kind === 'skip' ? join(q.repo, 'missing') : q.repo, q.pointer]
      })
      q.run(plan, {QUEUE_MAX_TOTAL_TOOL_CALLS: String(maxTotal)}, max ? ['--max-megas', String(max)] : [])
      // --- the rule
      const P = r.encodeParams({max, maxTotal})
      let st: any = it.init(P)
      const want: string[] = []
      for (const row of rows) {
        st = it.step(P, st, r.encodeInput({row: row.kind, v: row.v, calls: row.calls}))
        const launched = !!st.scalars.launched
        want.push(row.kind === 'terminal' ? 'done' : row.kind === 'skip' && !st.scalars.stopped ? 'skipped' : launched ? row.v : '-')
      }
      // A skip row after the night stopped is never reached: the rule leaves it untouched, as cmd_run does.
      for (let i = 0; i < rows.length; i++) if (rows[i].kind === 'skip') {
        const before = it.init(P); let s2: any = before
        for (let k = 0; k < i; k++) s2 = it.step(P, s2, r.encodeInput({row: rows[k].kind, v: rows[k].v, calls: rows[k].calls}))
        want[i] = s2.scalars.stopped ? '-' : 'skipped'
      }
      const opened = q.windows()
      const got = rows.map((row, i) => {
        const j = q.journalRows(`r${i}`)
        const v = j.length ? j[j.length - 1][2] : '-'
        return row.kind === 'run' && v !== '-' && !opened.includes(`r${i}`) ? `${v}(no window)` : v
      })
      if (JSON.stringify(want) !== JSON.stringify(got)) diverge = {night: n, max, maxTotal, rows, rule: want, bash: got}
      else agree++
    }
  } finally { cleanup(root) }
  return {agree, diverge}
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({nights: Number(process.env.NIGHTS ?? 25), seed: Number(process.env.SEED ?? 5)})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
