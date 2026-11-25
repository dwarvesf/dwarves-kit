// Bridge: lib/config/hook-module.sh (the real script and the real lib/config/modules.tsv) and kit_config_get against
// module-switch. Hooks: context-readiness.sh (session, opt-in), backlog-stage.sh (board, core), safety-gate.sh
// (spine), nope.sh (no row). Each layer file gets up to two `<module> = <v>` lines under [modules], written in the
// shapes the reader strips (padding, double quotes, inline comments, another section around it); `other` is a value
// that is neither true nor false (`yes`, `1`, `off`). Seeded random cases plus every single-layer case.
import {mkdirSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {bash, KIT, rng, sandbox, type BridgeResult} from './bridge-util.ts'
import {moduleSwitch, VALS} from './module-switch.ts'

const HOOKS = [
  {hook: 'context-readiness.sh', module: 'session', kind: 'module', core: 'opt-in'},
  {hook: 'backlog-stage.sh', module: 'board', kind: 'module', core: 'core'},
  {hook: 'safety-gate.sh', module: 'spine', kind: 'spine', core: 'core'},
  {hook: 'nope.sh', module: 'session', kind: 'unknown', core: 'core'},
] as const

type V = typeof VALS[number]

function line(rand: ReturnType<typeof rng>, mod: string, v: V) {
  const val = v === 'true' ? rand.pick(['true', '"true"']) : v === 'false' ? rand.pick(['false', '"false"']) : rand.pick(['yes', '1', 'off', '"on"'])
  return `${rand.pick(['', '  '])}${mod}${rand.pick(['=', ' = ', '  ='])}${val}${rand.pick(['', '  # note'])}`
}

function file(rand: ReturnType<typeof rng>, mod: string, a: V, b: V) {
  if (a === 'absent' && b === 'absent') return rand.pick(['', '[wrap]\ndistill = false\n'])
  const lines = ['# layer', rand.pick(['', '[gate]\nproof_of_done = true']), rand.pick(['[modules]', '[ modules ]  # the toggles'])]
  if (rand.next() < 0.3) lines.push(`cosmetic = true`)
  if (a !== 'absent') lines.push(line(rand, mod, a))
  if (b !== 'absent') lines.push(line(rand, mod, b))
  lines.push(rand.pick(['', '[other]\n' + `${mod} = false`]))
  return lines.join('\n') + '\n'
}

export async function bridge(opts: {seed?: number, n?: number} = {}): Promise<BridgeResult> {
  const rand = rng(opts.seed ?? 11)
  const f = moduleSwitch()
  const sb = sandbox('module-switch')
  try {
    type Case = {h: typeof HOOKS[number], v: V[], dir: string}
    const cases: Case[] = []
    const add = (h: typeof HOOKS[number], v: V[]) => {
      const dir = join(sb.dir, `c${cases.length}`)
      ;[['p', '.kit.toml'], ['o', 'kit.toml'], ['r', 'kit.toml']].forEach(([sub, name], i) => {
        mkdirSync(join(dir, sub), {recursive: true})
        const body = file(rand, h.module, v[2 * i], v[2 * i + 1])
        if (body !== '' || rand.next() < 0.5) writeFileSync(join(dir, sub, name), body)
      })
      cases.push({h, v, dir})
    }
    for (const h of HOOKS) for (let layer = 0; layer < 3; layer++) for (const val of VALS) {
      const v: V[] = Array(6).fill('absent'); v[2 * layer] = val; add(h, v)
    }
    for (let i = 0; i < (opts.n ?? 900); i++) add(rand.pick(HOOKS), Array.from({length: 6}, () => rand.pick(VALS)))
    const out = bash(`
      source '${KIT}/lib/config/kit-config.sh'
      while IFS='|' read -r d hook mod; do
        export KIT_PROJECT_ROOT="$d/p" KIT_CONFIG_OPERATOR="$d/o" KIT_CONFIG_ROOT="$d/r"
        bash '${KIT}/lib/config/hook-module.sh' off "$hook"; rc=$?
        echo "$rc|$(kit_config_get "modules.$mod")"
      done <<'ROWS'
${cases.map((c) => `${c.dir}|${c.h.hook}|${c.h.module}`).join('\n')}
ROWS`, sb.env, sb.dir, 300_000)
    const rows = out.stdout.trim().split('\n')
    let agree = 0
    for (let i = 0; i < cases.length; i++) {
      const c = cases[i]
      const [rc, kcgRaw] = (rows[i] ?? '').split('|')
      const want = f.run({kind: c.h.kind, core: c.h.core, p1: c.v[0], p2: c.v[1], o1: c.v[2], o2: c.v[3], r1: c.v[4], r2: c.v[5]})
      const kcgVal = kcgRaw === 'true' ? 1 : kcgRaw === 'false' ? 2 : kcgRaw === '' ? 0 : 3
      const real = {off: rc === '0', kcg: kcgVal}
      if (real.off !== want.off || real.kcg !== want.kcg) {
        return {agree, diverge: {hook: c.h.hook, lines: {project: c.v.slice(0, 2), operator: c.v.slice(2, 4), kitRoot: c.v.slice(4)}, bash: {offExit: rc, kit_config_get: kcgRaw}, rule: want, dir: c.dir}}
      }
      agree++
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
