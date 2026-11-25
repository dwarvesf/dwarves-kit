// Bridge: lib/config/kit-config.sh (kit_config_get, kit_config_get_root) and lib/config/config.sh (`config get`)
// against config-precedence. Four real registry rows cover the shapes: mega.wave_cap (env WAVE_CAP, one dot),
// lane.normal.phases (two dots), debug.confirm_fix (root-only), data.root (root-only, env KIT_DATA_ROOT). For each,
// every subset of {project, operator, kit-root} sets the key to a value naming its layer, with and without the env
// var. The layer a reader answered is read back off the value. All three files live in a temp dir; the real
// ~/.config and kit root are never read (KIT_CONFIG_OPERATOR, KIT_CONFIG_ROOT, KIT_PROJECT_ROOT point there).
// `source: 'head'` runs the committed config.sh (before the fix), against the 'first-dot-split' variant.
import {mkdirSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {bash, KIT, sandbox, type BridgeResult} from './bridge-util.ts'
import {configPrecedence, type Variant} from './config-precedence.ts'

const KEYS = [
  {key: 'mega.wave_cap', env: 'WAVE_CAP', rootOnly: false},
  {key: 'lane.normal.phases', env: '', rootOnly: false},
  {key: 'debug.confirm_fix', env: '', rootOnly: true},
  {key: 'data.root', env: 'KIT_DATA_ROOT', rootOnly: true},
]
const toml = (dotkey: string, v: string) => {
  const i = dotkey.lastIndexOf('.')
  return `# test layer\n[${dotkey.slice(0, i)}]\n${dotkey.slice(i + 1)} = "${v}"  # inline comment\n`
}
const src = (v: string) => ({P: 3, O: 2, R: 1, E: 4} as Record<string, number>)[v] ?? 0

export async function bridge(opts: {source?: 'work' | 'head'} = {}): Promise<BridgeResult> {
  const variant: Variant = opts.source === 'head' ? 'first-dot-split' : 'shipped'
  const f = configPrecedence(variant)
  const sb = sandbox('config-precedence')
  try {
    const configSh = opts.source === 'head'
      ? (() => { const p = join(KIT, 'lib/config/.config-head.sh'); bash(`git -C '${KIT}' show HEAD:lib/config/config.sh > '${p}'`, sb.env); return p })()
      : join(KIT, 'lib/config/config.sh')
    let agree = 0
    const rows: string[] = []
    const cases: {k: typeof KEYS[number], env: boolean, proj: boolean, op: boolean, root: boolean, dir: string}[] = []
    let n = 0
    for (const k of KEYS) for (const env of k.env ? [false, true] : [false]) for (const proj of [false, true])
      for (const op of [false, true]) for (const root of [false, true]) {
        const dir = join(sb.dir, `c${n++}`)
        for (const [on, sub, v, file] of [[proj, 'p', 'P', '.kit.toml'], [op, 'o', 'O', 'kit.toml'], [root, 'r', 'R', 'kit.toml']] as const) {
          mkdirSync(join(dir, sub), {recursive: true})
          if (on) writeFileSync(join(dir, sub, file), toml(k.key, v))
        }
        cases.push({k, env, proj, op, root, dir})
        rows.push(`${dir}|${k.key}|${env ? k.env : '-'}`)
      }
    const out = bash(`
      source '${KIT}/lib/config/kit-config.sh'
      while IFS='|' read -r d key ev; do
        export KIT_PROJECT_ROOT="$d/p" KIT_CONFIG_OPERATOR="$d/o" KIT_CONFIG_ROOT="$d/r"
        unset WAVE_CAP KIT_DATA_ROOT; [ "$ev" = - ] || export "$ev=E"
        a="$(kit_config_get "$key" D)"; b="$(kit_config_get_root "$key" D)"; c="$(bash '${configSh}' get "$key" 2>&1)"
        echo "$a|$b|$c"
      done <<'ROWS'
${rows.join('\n')}
ROWS`, sb.env, sb.dir, 120_000)
    const got = out.stdout.trim().split('\n')
    for (let i = 0; i < cases.length; i++) {
      const c = cases[i]
      const [a, b, cfg] = (got[i] ?? '').split('|')
      const real = {get: src(a), getRoot: src(b), config: src(cfg)}
      const want = f.run({env: c.env, proj: c.proj, op: c.op, root: c.root, rootOnly: c.k.rootOnly, twoDots: c.k.key.split('.').length > 2})
      if (JSON.stringify(real) !== JSON.stringify(want)) {
        return {agree, diverge: {key: c.k.key, env: c.env, project: c.proj, operator: c.op, kitRoot: c.root, bash: {kit_config_get: a, kit_config_get_root: b, config_get: cfg}, rule: want}}
      }
      agree++
    }
    return {agree, diverge: null}
  } finally {
    sb.cleanup()
    bash(`rm -f '${join(KIT, 'lib/config/.config-head.sh')}'`, {PATH: '/usr/bin:/bin'})
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  console.log(JSON.stringify(await bridge({source: process.argv[2] === 'head' ? 'head' : 'work'})))
}
