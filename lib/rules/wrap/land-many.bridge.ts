// Bridge: lib/wrap/wrap-land.sh:cmd_land with several worktrees against land-many. The real cmd_land runs (sourced
// through lib/wrap/wrap.sh); the two things it calls per worktree, _land_many_rebase and _land_one, are replaced by
// shell functions that log the worktree and answer a scripted outcome, so the bridge sees exactly which worktrees
// the bash attempted and in what order. Every outcome list of length 1..4 over {ok, fail, rebaseFail}.
import {join} from 'node:path'
import {bash, KIT, sandbox, sequences, type BridgeResult} from './bridge-util.ts'
import {landMany, OUTCOMES} from './land-many.ts'

export async function bridge(): Promise<BridgeResult> {
  const sb = sandbox('land-many')
  try {
    const cases = sequences(OUTCOMES as readonly string[], 4)
    const wts = [1, 2, 3, 4].map((i) => join(sb.dir, `wt${i}`))
    const out = bash(`
      for w in ${wts.join(' ')}; do git init -q "$w"; done
      source '${KIT}/lib/wrap/wrap.sh' >/dev/null 2>&1
      _land_many_rebase() { local i; i="$(cat "$IDX")"; case "$(sed -n "\${i}p" "$SEQ")" in rebaseFail) return 1 ;; esac; return 0; }
      _land_one() {
        local i; i="$(cat "$IDX")"; echo "$1" >> "$LOG"
        case "$(sed -n "\${i}p" "$SEQ")" in ok) echo "LAND: merged #1 (abc) pull=ok worktree=removed"; echo $((i+1)) > "$IDX"; return 0 ;; esac
        echo "LAND: refused (merge, exit 2)"; return 2
      }
      while IFS= read -r line; do
        printf '%s\\n' $line > "$SEQ"; : > "$LOG"; echo 1 > "$IDX"
        n=$(printf '%s\\n' $line | wc -l | tr -d ' ')
        # a rebase refusal is read for worktree i (> 1) before _land_one; the stub advances IDX only on ok
        set -- ${wts.join(' ')}; args=("\${@:1:$n}")
        cmd_land "\${args[@]}" >/dev/null 2>&1 </dev/null; rc=$?
        echo "$rc|$(wc -l < "$LOG" | tr -d ' ')"
      done <<'ROWS'
${cases.map((c) => c.join(' ')).join('\n')}
ROWS`, {...sb.env, SEQ: join(sb.dir, 'seq'), LOG: join(sb.dir, 'log'), IDX: join(sb.dir, 'idx')}, sb.dir, 300_000)
    const rows = out.stdout.trim().split('\n')
    const r = landMany()
    let agree = 0
    for (let i = 0; i < cases.length; i++) {
      const seq = cases[i]
      const [rc, attempted] = (rows[i] ?? '').split('|')
      // The first worktree is never rebased, so a rebaseFail there is just the land's own outcome: not ok.
      const it = r.interpreter(), p = r.encodeParams({n: seq.length})
      let st = it.init(p)
      for (const o of seq) st = it.step(p, st, r.encodeInput({out: o}))
      const d = r.decode(st) as {next: number, landed: number, stopped: string}
      // _land_one is attempted for every turn except a turn that stopped at its rebase (worktree i > 1).
      const stoppedAtRebase = d.stopped === 'yes' && seq[d.next - 1] === 'rebaseFail' && d.next > 1
      const want = {attempted: d.next - (stoppedAtRebase ? 1 : 0), rc0: d.stopped === 'no'}
      const real = {attempted: Number(attempted), rc0: rc === '0'}
      if (JSON.stringify(real) !== JSON.stringify(want)) return {agree, diverge: {outcomes: seq, bash: {rc, attempted}, rule: {...d, ...want}}}
      agree++
    }
    return {agree, diverge: null}
  } finally { sb.cleanup() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify(await bridge()))
