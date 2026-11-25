// Bridge: lib/reflect/hook-util.sh:hu_throttled (sourced, real) against throttle. Time is made deterministic: a
// `date` stub answers `+%s` from a clock file the bridge advances, and a `touch` stub stamps a file with that clock,
// so the stamp's age is exactly the ticks the sequence sent. Intervals -1 and 0 (off), 1, 2, 5; every sequence of
// length 1..3 over {call, tick 1, tick 2, tick 5}, plus 60 seeded random ones of length up to 10.
import {join} from 'node:path'
import {bash, KIT, rng, sandbox, sequences, stub, type BridgeResult} from './bridge-util.ts'
import {throttle} from './throttle.ts'

const STEPS = ['call', 't1', 't2', 't5'] as const

export async function bridge(opts: {seed?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox('throttle')
  try {
    stub(sb.bin, 'date', 'if [ "${1:-}" = "+%s" ]; then cat "$CLOCK"; else exec /bin/date "$@"; fi')
    stub(sb.bin, 'touch', 't="$(cat "$CLOCK")"; perl -e \'$t=shift; utime $t, $t, @ARGV\' "$t" "$@"')
    const rand = rng(opts.seed ?? 9)
    const cases: string[][] = sequences(STEPS as readonly string[], 3)
    for (let i = 0; i < 60; i++) cases.push(Array.from({length: 1 + rand.int(10)}, () => rand.pick(STEPS)))
    const intervals = [-1, 0, 1, 2, 5]
    const r = throttle()
    let agree = 0
    for (const interval of intervals) {
      const script = `source '${KIT}/lib/reflect/hook-util.sh'
        while IFS= read -r line; do
          rm -rf "$SD"; echo 1800000000 > "$CLOCK"; out=""
          for s in $line; do
            case "$s" in
              call) hu_throttled "$SD" stamp ${interval}; out="$out $?" ;;
              t*) echo $(( $(cat "$CLOCK") + \${s#t} )) > "$CLOCK"; out="$out ." ;;
            esac
          done
          echo "R$out"
        done <<'ROWS'
${cases.map((c) => c.join(' ')).join('\n')}
ROWS`
      const out = bash(script, {...sb.env, CLOCK: join(sb.dir, 'clock'), SD: join(sb.dir, 'state')}, sb.dir, 300_000)
      const rows = out.stdout.trim().split('\n')
      for (let i = 0; i < cases.length; i++) {
        const it = r.interpreter(), p = r.encodeParams({on: interval > 0, interval: Math.max(interval, 0)})
        let st = it.init(p)
        const want: string[] = []
        for (const s of cases[i]) {
          st = it.step(p, st, r.encodeInput(s === 'call' ? {op: 'call', dt: 0} : {op: 'tick', dt: Number(s.slice(1))}))
          want.push(s === 'call' ? ((r.decode(st) as {skipped: boolean}).skipped ? '0' : '1') : '.')
        }
        const real = (rows[i] ?? '').replace(/^R ?/, '')
        if (real !== want.join(' ')) return {agree, diverge: {interval, sequence: cases[i], bash: real, rule: want.join(' ')}}
        agree++
      }
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
