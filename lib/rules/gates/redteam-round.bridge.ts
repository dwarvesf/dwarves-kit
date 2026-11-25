// Bridge: every (verdict, cost shape, rid given) through the real `redteam-gate.sh round`, then the run ledger read
// back: refused calls must leave no line; accepted ones exactly one OUTCOME end with the caught value, one TOKENS row
// with cost=, and one `GATE | redteam | ran` row.
import {join} from 'node:path'
import {bash, GATE, product, sandbox, type BridgeResult} from './harness.ts'
import {COSTS, redteamRound, VERDICTS} from './redteam-round.ts'

const RG = join(GATE, 'redteam-gate.sh'), LEDGER = join(GATE, 'gate-ledger.sh')
const COST: Record<string, string[]> = {decimal: ['cost=0.42', 'cost=3'], missing: [], malformed: ['cost=1.2.3', 'cost=abc', 'cost=']}
const WORD: Record<string, string> = {secure: 'secure', findings: 'findings', capped: 'capped', other: 'SECURE'}

export async function bridge(): Promise<BridgeResult> {
  const sb = sandbox(), f = redteamRound()
  let agree = 0, k = 0
  try {
    for (const c of product({verdict: VERDICTS, cost: COSTS, rid: [true, false]})) {
      for (const costArg of COST[c.cost].length ? COST[c.cost] : [null]) {
        const rid = `rt-${k++}`
        const real = bash(sb, [RG, 'round', c.rid ? rid : '', WORD[c.verdict], ...(costArg ? [costArg] : []), 'round=1', 'reason=bridge'])
        const log = bash(sb, [LEDGER, 'show', rid]).out
        const o = f.run(c as any)
        const gate = (log.match(/\| GATE \| redteam \| ran \|/g) ?? []).length
        const tokens = (log.match(/\| TOKENS \|.*cost=/g) ?? []).length
        const outcome = log.match(/\| OUTCOME \| redteam \| end \|.*caught=(true|false)/)
        const ok = o.accepted
          ? real.code === 0 && gate === 1 && tokens === 1 && outcome?.[1] === String(o.caught)
          : real.code !== 0 && log.trim() === ''
        if (!ok) return {agree, diverge: {facts: c, costArg, model: o, bash: {code: real.code, err: real.err.trim(), log}}}
        agree++
      }
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
