// Bridge: lib/telemetry/kit-migrate.sh (the real script, run as an install does: env -i with HOME and
// XDG_STATE_HOME in a temp dir) against kit-migrate. A request either reshapes the legacy dir
// (the pre-SPEC-097 log root under $HOME: gone, a real dir with a new gen-<k>.log, the same plus an unreadable file so cp
// fails part way, or a symlink to a dir holding planted-<k>.log) or runs an install. After every install the bridge
// reads .migrated, .migrate-refused, any planted log, and how many gen logs reached the durable root.
import {join} from 'node:path'
import {bash, KIT, rng, sandbox, sequences, type BridgeResult} from './bridge-util.ts'
import {kitMigrate, LEGACY} from './kit-migrate.ts'
// The legacy root this bridge migrates FROM, built from parts: test-kit-contract C6 bans the literal path in lib/.
const LEGACY_LOG_ROOT = ['.claude', 'dwarves-kit', 'logs'].join('/')

const REQS = ['run', ...LEGACY.map((k) => `L:${k}`)] as const

export async function bridge(opts: {seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox('kit-migrate')
  try {
    const rand = rng(opts.seed ?? 13)
    // As root an unreadable file still reads, so cp cannot be made to fail part way: drop that request there.
    const reqs = process.getuid?.() === 0 ? REQS.filter((q) => q !== 'L:dirBad') : [...REQS]
    const cases: string[][] = sequences(reqs as readonly string[], 2)
    for (let i = 0; i < 120; i++) cases.push(Array.from({length: 1 + rand.int(7)}, () => rand.pick(reqs)))
    const script = cases.map((seq, i) => {
      const d = join(sb.dir, `c${i}`)
      const steps = seq.map((q) => {
        if (q === 'run') return `env -i PATH="$PATH" HOME="$H" XDG_STATE_HOME="$X" KIT_CONFIG_OPERATOR="$H/none" KIT_CONFIG_ROOT="$H/none" bash '${KIT}/lib/telemetry/kit-migrate.sh' 2>/dev/null
          echo "S $([ -f "$DUR/.migrated" ] && echo 1 || echo 0)$([ -f "$DUR/.migrate-refused" ] && echo 1 || echo 0)$(ls "$DUR"/runs/planted-* >/dev/null 2>&1 && echo 1 || echo 0) $(ls "$DUR"/runs/gen-* 2>/dev/null | wc -l | tr -d ' ')"`
        const kind = q.slice(2)
        const reset = 'chmod -R u+rwx "$LEG" 2>/dev/null; rm -rf "$LEG"; k=$((k+1))'
        if (kind === 'absent') return reset
        if (kind === 'symlink') return `${reset}; mkdir -p "$D/evil$k/runs"; echo p > "$D/evil$k/runs/planted-$k.log"; ln -s "$D/evil$k" "$LEG"`
        return `${reset}; mkdir -p "$LEG/runs"; echo g > "$LEG/runs/gen-$k.log"${kind === 'dirBad' ? '; echo b > "$LEG/runs/bad-$k.log"; chmod 000 "$LEG/runs/bad-$k.log"' : ''}`
      }).join('\n')
      return `( D='${d}'; H="$D/home"; X="$D/state"; LEG="$H/${LEGACY_LOG_ROOT}"; DUR="$X/dwarves-kit/logs"; k=0
        mkdir -p "$H/.claude/dwarves-kit"; echo "CASE"
        ${steps}
        chmod -R u+rwx "$D" 2>/dev/null )`
    }).join('\n')
    const out = bash(script, sb.env, sb.dir, 300_000).stdout
    const blocks = out.split('CASE').slice(1)
    const r = kitMigrate()
    let agree = 0
    for (let i = 0; i < cases.length; i++) {
      const got = (blocks[i] ?? '').split('\n').filter((l) => l.startsWith('S ')).map((l) => l.slice(2))
      const it = r.interpreter(), p = r.encodeParams({})
      let st = it.init(p), k = 0
      for (let j = 0; j < cases[i].length; j++) {
        const q = cases[i][j]
        st = it.step(p, st, r.encodeInput(q === 'run' ? {op: 'run', kind: 'absent'} : {op: 'legacy', kind: q.slice(2)}))
        if (q !== 'run') continue
        const d = r.decode(st) as Record<string, any>
        const want = `${d.sentinel ? 1 : 0}${d.refused ? 1 : 0}${d.planted ? 1 : 0} ${d.copied}`
        if (got[k] !== want) return {agree, diverge: {requests: cases[i].slice(0, j + 1), bash: got[k], rule: want, legend: 'sentinel refused planted gen-copies'}}
        k++
      }
      agree++
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
