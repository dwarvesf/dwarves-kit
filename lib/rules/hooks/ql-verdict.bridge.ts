// Bridge: hold lib/loop/ql-verdict.sh resume to the ql-verdict rule over seeded marker files (rounds in and out of
// order, clean and dirty, a few clean markers that still report findings). The machine's state after the last marker
// is compared with the `round= clean_streak= last_findings=` line, or with exit 65 when any marker was an error.
import {spawnSync} from 'node:child_process'
import {qlVerdict} from './ql-verdict.ts'
import {KIT, machine, rng, Tally, tmp, write, join, type BridgeResult} from './_bridge.ts'

export async function bridge(): Promise<BridgeResult> {
  const t = new Tally()
  const g = rng(61)
  for (let i = 0; i < 80; i++) {
    const n = g.int(6)
    const m = machine(qlVerdict())
    const lines: string[] = []
    let st: any = m.state
    for (let k = 0; k < n; k++) {
      const round = g.pick([k + 1, k + 1, k + 1, 9, 0])
      const findings = g.pick([0, 0, 1, 3])
      const clean = g.next() < 0.1 ? true : findings === 0 ? g.next() < 0.8 : false
      lines.push(`${g.bool() ? '`' : ''}[[QL-VERDICT round=${round} clean=${clean} findings=${findings}]]`.replace(/^`(.*)$/, '`$1`'))
      st = m.step({round, clean, findings})
    }
    const dir = tmp('kit-ql'); write(dir, {'spec.md': ['# Spec', ...lines, 'end'].join('\n') + '\n'})
    const r = spawnSync('bash', [process.env.BRIDGE_QL_VERDICT ?? join(KIT, 'lib/loop/ql-verdict.sh'), 'resume', join(dir, 'spec.md')], {encoding: 'utf8'})
    const want = st.error ? 'exit 65' : `round=${st.max + 1} clean_streak=${st.streak} last_findings=${n ? st.last : '-'}`
    const got = r.status === 65 ? 'exit 65' : r.stdout.trim()
    t.check(got === want, () => ({case: i, lines, rule: want, hook: got}))
  }
  return t.result()
}

if (import.meta.main) console.log(JSON.stringify(await bridge(), null, 2))
