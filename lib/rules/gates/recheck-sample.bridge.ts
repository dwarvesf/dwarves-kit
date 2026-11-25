// Bridge: the real `recheck-sample.sh decide <rid> [N]` over seeded random rids and an N pool (leading zeros,
// non-numeric, empty: then the root config value from KIT_CONFIG_ROOT), compared with the decision: the printed
// verdict, the exit code, and the `recheck: <verdict> key=<rid>` line in the run ledger. The cksum fact is the real
// `cksum` of the rid (the rule treats the hash as opaque).
import {join} from 'node:path'
import {bash, GATE, q, rng, sandbox, write, type BridgeResult} from './harness.ts'
import {recheckSample} from './recheck-sample.ts'

const RS = join(GATE, 'recheck-sample.sh'), LEDGER = join(GATE, 'gate-ledger.sh')
const NS = ['', '0', '1', '2', '3', '5', '7', '08', '09', '010', '012', 'abc', '12', '00']
const fact = (s: string) => ({digits: /^[0-9]+$/.test(s), value: /^[0-9]+$/.test(s) ? Number(s) : 0, lead0: /^0[0-9]/.test(s), octalOk: !/[89]/.test(s)})

export async function bridge(opts: {n?: number, seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 9), run = recheckSample().compiled()
  const n = opts.n ?? Number(process.env.BRIDGE_N ?? 60)
  let agree = 0
  try {
    for (let i = 0; i < n; i++) {
      const rid = `rid-${rand.int(100000)}-${i}`, arg = rand.pick(NS), cfg = rand.pick(NS.filter(x => x !== ''))
      const kr = join(sb.dir, `kr${i}`); write(join(kr, 'kit.toml'), `[execute]\nrecheck_sample = ${/^[0-9]+$/.test(cfg) ? cfg : `"${cfg}"`}\n`)
      const sum = Number(bash(sb, ['-c', `printf '%s' ${q(rid)} | cksum | cut -d' ' -f1`]).out.trim())
      const real = bash(sb, [RS, 'decide', rid, ...(arg ? [arg] : [])], {env: {KIT_CONFIG_ROOT: kr}})
      const a = fact(arg), c = fact(cfg), used = arg ? a : c
      const o = run({given: !!arg, arg: a.value, argDigits: a.digits, cfg: c.value, cfgDigits: c.digits, sum,
        lead0: used.lead0, octalOk: used.octalOk})
      const want = o.decided ? (o.sampled ? 'sampled' : 'skipped') : ''
      const got = real.code === 0 ? real.out.trim() : ''
      const logged = bash(sb, [LEDGER, 'actions', rid, 'recheck:']).out.trim()
      const wantLog = want ? `recheck: ${want} key=${rid}` : ''
      if (got !== want || logged !== wantLog)
        return {agree, diverge: {rid, arg, cfg, sum, model: {verdict: want, log: wantLog}, bash: {code: real.code, out: real.out.trim(), err: real.err.trim(), log: logged}}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
