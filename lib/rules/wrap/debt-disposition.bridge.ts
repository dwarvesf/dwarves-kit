// Bridge: lib/reflect/weekend-batch.sh (list, mark-paid) over lines written by the real lib/gate/gate-ledger.sh
// (debt, debt-response) against debt-disposition. 80 rids, each with a seeded sequence of up to 5 requests; after
// every round one `weekend-batch.sh list --all-repos --days 30` reads which rids are collected and with which
// disposition. DWARVES_KIT_LOG_DIR points the ledger at a temp dir.
import {join} from 'node:path'
import {bash, KIT, rng, sandbox, type BridgeResult} from './bridge-util.ts'
import {debtDisposition, dispositionOf, VERDICTS, RESPONSES} from './debt-disposition.ts'

type Req = {op: 'fat' | 'thin' | 'markPaid', v: typeof VERDICTS[number], r: typeof RESPONSES[number]}

export async function bridge(opts: {seed?: number, rids?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox('debt')
  try {
    const rand = rng(opts.seed ?? 17)
    const n = opts.rids ?? 80, ROUNDS = 5
    const plans: Req[][] = Array.from({length: n}, () => Array.from({length: 1 + rand.int(ROUNDS)}, () => ({
      op: rand.pick(['fat', 'fat', 'thin', 'markPaid'] as const), v: rand.pick(VERDICTS), r: rand.pick(RESPONSES)})))
    const env = {...sb.env, DWARVES_KIT_LOG_DIR: join(sb.dir, 'logs')}
    delete (env as Record<string, string>).KIT_LEDGER_DIR
    const G = `${KIT}/lib/gate/gate-ledger.sh`, W = `${KIT}/lib/reflect/weekend-batch.sh`
    const r = debtDisposition(), it = r.interpreter(), p = r.encodeParams({})
    const states = plans.map(() => it.init(p))
    let agree = 0
    for (let k = 0; k < ROUNDS; k++) {
      const cmds: string[] = []
      plans.forEach((plan, i) => {
        const q = plan[k]
        if (!q) return
        const v = q.v === 'notsig' ? 'not-significant' : q.v
        if (q.op === 'fat') cmds.push(`bash '${G}' debt rid${i} significance=high worthiness=low verdict=${v}${q.r === 'none' ? '' : ` response=${q.r}`} reason=r${k}`)
        else if (q.op === 'thin') cmds.push(`bash '${G}' debt-response rid${i} ${q.r === 'none' ? '' : q.r} because`)
        else cmds.push(`bash '${W}' mark-paid rid${i}`)
        states[i] = it.step(p, states[i], r.encodeInput(q))
      })
      const out = bash(`${cmds.map((c) => `${c} >/dev/null 2>&1 </dev/null`).join('\n')}\nbash '${W}' list --all-repos --days 30 2>/dev/null`, env, sb.dir, 300_000)
      const listed = new Map(out.stdout.trim().split('\n').filter(Boolean).map((l) => { const [rid, disp] = l.split('\t'); return [rid, disp] }))
      for (let i = 0; i < n; i++) {
        if (!plans[i][k]) continue
        const d = dispositionOf(r.decode(states[i]) as any)
        const want = ['logged', 'accepted', 'deferred'].includes(d) ? d : 'not collected'
        const real = listed.get(`rid${i}`) ?? 'not collected'
        if (real !== want) return {agree, diverge: {rid: `rid${i}`, requests: plans[i].slice(0, k + 1), bash: real, rule: want, ledger: bash(`cat '${join(sb.dir, 'logs', 'runs', `rid${i}.log`)}'`, env).stdout}}
        agree++
      }
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge(), null, 1))
