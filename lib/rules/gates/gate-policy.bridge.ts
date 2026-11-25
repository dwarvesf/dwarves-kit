// Bridge: every combination of (key, operator value, kit-root value, project value, --at, tracked-and-clean)
// through the real `gate-policy.sh enabled`, compared with the decision. 16 temp repos (project value x read mode),
// 4 operator dirs and 4 kit-root dirs; one bash process per repo runs its 48 calls.
import {join} from 'node:path'
import {bash, GATE, product, q, sandbox, sh, write, type BridgeResult} from './harness.ts'
import {gatePolicy, VALUES} from './gate-policy.ts'

const POLICY = join(GATE, 'gate-policy.sh')
const KEYS = [{key: 'lane_gates', known: true, defOn: false}, {key: 'review_verdict', known: true, defOn: true},
  {key: 'bogus_key', known: false, defOn: false}] as const
const line = (key: string, v: string) => (v === 'absent' ? '[gate]\n' : `[gate]\n${key} = ${v === 'other' ? '"yes"' : v}\n`)

export async function bridge(): Promise<BridgeResult> {
  const f = gatePolicy(), sb = sandbox()
  let agree = 0
  try {
    for (const pv of VALUES) for (const at of [false, true]) for (const clean of [true, false]) {
      const root = join(sb.dir, `r-${pv}-${at}-${clean}`)
      const cfg = KEYS.map(k => line(k.key, pv).replace('[gate]\n', '')).join('')
      // at: the base commit holds pv, the head commit and the tree hold the opposite; else HEAD holds pv.
      const flip = cfg.replace(/= true/g, '= TMP').replace(/= false/g, '= true').replace(/= TMP/g, '= false')
      const steps = [`git init -q -b main ${q(root)}`, `cd ${q(root)}`, `printf '%s' ${q('[gate]\n' + cfg)} > .kit.toml`,
        'git add -A', 'git commit -q -m base', 'git tag base']
      if (at) steps.push(`printf '%s' ${q('[gate]\n' + flip)} > .kit.toml`, 'git commit -q --allow-empty -am head')
      if (!clean) steps.push(`printf '# edited\\n' >> .kit.toml`)
      const r = sh(sb, steps.join(' && '))
      if (r.code !== 0) throw new Error(r.err)
      const combos = [...product({k: KEYS, op: VALUES, rt: VALUES})]
      const calls = combos.map(c => {
        const op = join(sb.dir, `op-${c.op}`), kr = join(sb.dir, `kr-${c.rt}`)
        write(join(op, 'kit.toml'), KEYS.map(k => line(k.key, c.op)).join('')); write(join(kr, 'kit.toml'), KEYS.map(k => line(k.key, c.rt)).join(''))
        return `KIT_CONFIG_OPERATOR=${q(op)} KIT_CONFIG_ROOT=${q(kr)} bash ${q(POLICY)} enabled ${c.k.key} ${q(root)}${at ? ' --at base' : ''} 2>/dev/null; echo $?`
      })
      const got = bash(sb, ['-c', calls.join('\n')], {cwd: root}).out.trim().split('\n')
      for (let i = 0; i < combos.length; i++) {
        const c = combos[i]
        const want = f.run({known: c.k.known, defOn: c.k.defOn, op: c.op, root: c.rt, pv, at, clean}).on
        if ((got[i] === '0') !== want) return {agree, diverge: {key: c.k.key, op: c.op, root: c.rt, pv, at, clean, model: want ? 'on' : 'off', bash: got[i]}}
        agree++
      }
    }
  } finally { sb.done() }
  return {agree, diverge: null}
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
