// Bridge: `bin/wrap deploy-wait` (the real verb) against deploy-wait. Time is the verb's own test clock
// (DEPLOY_WAIT_CLOCK_FILE): a `sleep` stub adds its argument to the clock, and the `gh` stub adds each read's own
// duration (slow) before answering, so wall time is exactly what the sequence says. The stub answers each
// `gh api .../check-runs` from a scripted list: a run that succeeded, failed, is still open, no matching run, a 502
// (transient), a 404 (a real error) or an answer that is not JSON. Past the list it keeps answering "open".
// Timeouts 0, 10, 25 and 40; DEPLOY_POLL_SECS 10 (the default) and 3; with and without --check.
import {join} from 'node:path'
import {bash, KIT, rng, sandbox, stub, type BridgeResult} from './bridge-util.ts'
import {deployWait, EXIT, READS} from './deploy-wait.ts'

export async function bridge(opts: {seed?: number, n?: number} = {}): Promise<BridgeResult> {
  const sb = sandbox('deploy-wait')
  try {
    stub(sb.bin, 'sleep', 'echo $(( $(cat "$DEPLOY_WAIT_CLOCK_FILE") + ${1%.*} )) > "$DEPLOY_WAIT_CLOCK_FILE"')
    stub(sb.bin, 'gh', `
[ "$1" = auth ] && exit 0
n=$(cat "$GHN" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$GHN"
line="$(sed -n "\${n}p" "$GHSEQ")"; [ -n "$line" ] || line="open 0"
kind="\${line% *}"; slow="\${line#* }"
echo $(( $(cat "$DEPLOY_WAIT_CLOCK_FILE") + slow )) > "$DEPLOY_WAIT_CLOCK_FILE"
run() { printf '{"total_count":1,"check_runs":[{"id":%s,"name":"Workers Builds: app","status":"%s","conclusion":%s}]}\\n' "$n" "$1" "$2"; }
case "$kind" in
  success) run completed '"success"' ;;
  failed) run completed '"failure"' ;;
  open) run in_progress null ;;
  missing) printf '{"total_count":0,"check_runs":[]}\\n' ;;
  transient) echo "HTTP 502: Bad Gateway" >&2; exit 1 ;;
  error) echo "HTTP 404: Not Found" >&2; exit 1 ;;
  unreadable) echo "<html>oops</html>" ;;
esac`)
    const rand = rng(opts.seed ?? 21)
    const r = deployWait()
    let agree = 0
    for (let i = 0; i < (opts.n ?? 150); i++) {
      const timeout = rand.pick([0, 10, 25, 40]), poll = rand.pick([10, 3]), check = rand.next() < 0.7
      const len = 1 + rand.int(8)
      const seq = Array.from({length: len}, () => ({read: rand.pick(['open', 'open', 'missing', 'transient', 'success', 'failed', 'error', 'unreadable'] as const), slow: rand.pick([0, 0, 2, 15])}))
      const d = join(sb.dir, `c${i}`)
      const out = bash(`mkdir -p '${d}'; echo 0 > '${d}/clock'; : > '${d}/n'
        printf '%s\\n' ${seq.map((s) => `'${s.read} ${s.slow}'`).join(' ')} > '${d}/seq'
        DEPLOY_POLL_SECS=${poll} DEPLOY_WAIT_CLOCK_FILE='${d}/clock' GHN='${d}/n' GHSEQ='${d}/seq' \\
          bash '${KIT}/bin/wrap' deploy-wait o/r abcdef1 ${check ? '--check Workers' : ''} --timeout ${timeout} >/dev/null 2>&1 </dev/null
        echo "R $? $(cat '${d}/n')"`, sb.env, sb.dir, 60_000)
      const m = /R (\d+) (\d+)/.exec(out.stdout)
      const real = {exit: Number(m?.[1] ?? -1), reads: Number(m?.[2] ?? -1)}
      const it = r.interpreter(), p = r.encodeParams({timeout, poll})
      let st = it.init(p), k = 0
      while ((r.decode(st) as {phase: string}).phase === 'polling' && k < 200) {
        const s = seq[k] ?? {read: 'open', slow: 0}
        st = it.step(p, st, r.encodeInput(s)); k++
      }
      const dec = r.decode(st) as {phase: string, reads: number}
      const want = {exit: EXIT[dec.phase], reads: dec.reads}
      if (real.exit !== want.exit || real.reads !== want.reads) return {agree, diverge: {timeout, poll, check, reads: seq, bash: real, rule: {...want, phase: dec.phase}}}
      agree++
    }
    void READS
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge(), null, 1))
