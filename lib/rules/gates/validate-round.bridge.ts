// Bridge: seeded random sequences of `gate-ledger.sh validate-round open|close|incomplete` on a temp repo whose
// branch slug is the rid and whose spec is the ship-gate pick, with drift made real (the spec edited between open
// and close) and wrong tokens made real (a well-formed token that is not the last round's). Compared per step: the
// exit code; at the end: the last ROUND state and the validate gate's latest row.
import {join} from 'node:path'
import {appendFileSync} from 'node:fs'
import {bash, GATE, gitRepo, rng, sandbox, sh, write, type BridgeResult} from './harness.ts'
import {OPS, validateRound} from './validate-round.ts'

const LEDGER = join(GATE, 'gate-ledger.sh')
const FAKE = `${'a'.repeat(40)}.1.1`

export async function bridge(opts: {n?: number, seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox(), rand = rng(opts.seed ?? 41), r = validateRound(), it = r.interpreter()
  const n = opts.n ?? Number(process.env.BRIDGE_N ?? 25)
  let agree = 0
  try {
    for (let i = 0; i < n; i++) {
      const slug = `vr${i}`, root = gitRepo(sb, `vr${i}`), spec = join(root, `docs/specs/SPEC-001-${slug}.md`)
      write(spec, `# Spec: ${slug}\nStatus: DRAFT\nLane: full\n`)
      sh(sb, `git switch -qc feat/${slug} && git add -A && git commit -qm spec`, root)
      let token = '', st = it.init({})
      const steps: unknown[] = []
      for (let k = 0; k < 2 + rand.int(5); k++) {
        const op = rand.pick(OPS), tok = rand.next() < 0.85, drift = rand.next() < 0.35, approved = rand.next() < 0.6
        const useTok = tok && token ? token : FAKE
        let args: string[]
        if (op === 'open') args = ['validate-round', 'open', slug, spec]
        else if (op === 'close') {
          if (drift) appendFileSync(spec, `drift ${k}\n`)
          args = ['validate-round', 'close', slug, useTok, `verdict=${approved ? 'APPROVED' : 'NEEDS-REVISION'}`, `critical=${approved ? 0 : 1}`,
            'warnings=0', 'agents=2', 'r6=design-bearing=no pass', 'summary=bridge']
        } else args = ['validate-round', 'incomplete', slug, useTok, `stopped ${k}`]
        const real = bash(sb, [LEDGER, ...args], {cwd: root})
        const effTok = tok && !!token
        st = it.step({}, st, r.encodeInput({op, tok: effTok, drift: op === 'close' && drift, approved} as any))
        const m = r.decode(st) as any
        steps.push({op, tok: effTok, drift: op === 'close' && drift, approved, rc: real.code})
        if (op === 'open' && real.code === 0) token = real.out.trim().split('\n').pop()!
        if (real.code !== m.rc) return {agree, diverge: {seq: steps, model: m, bash: {code: real.code, err: real.err.trim().slice(0, 400)}}}
      }
      const log = bash(sb, [LEDGER, 'show', slug]).out
      const rounds = [...log.matchAll(/\| ROUND \| ([a-z]+) \|/g)].map(x => x[1]).filter(s => s !== 'closing')
      const vals = [...log.matchAll(/\| GATE \| validate \| ([a-z]+) \|/g)].map(x => x[1])
      const m = r.decode(st) as any
      const lastReal = rounds.pop() ?? 'none', valReal = vals.pop() ?? 'none'
      if (lastReal !== m.last || valReal !== m.val) return {agree, diverge: {seq: steps, model: m, bash: {last: lastReal, val: valReal}}}
      agree++
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
