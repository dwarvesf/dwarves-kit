// Bridge: the real overnight queue (lib/queue/queue.sh run, lib/queue/watch-board.sh) against queueGuard().
//
// The environment is the one tests/test-runaway-guards.sh uses: KIT_LEDGER_DIR in a temp dir, the shipped fake mux
// (tests/fixtures/queue/fake-mux) behind MUX_CMD, a board repo with one `#auto` row and a separate run repo, `gh`
// stubbed to fail, and a `date` stub that answers `date +%s` from FAKE_NOW so backoffs and cooldowns can be crossed.
// Each step of a seeded random sequence is one of:
//   plan            watch-board dry-run (no reaping): was ID-001 planned?
//   run v ev        one `queue.sh run` of the slug, made to end with verdict v and progress evidence ev
//                   (model: launch then finish)
//   reap sig delta  a dead conductor's beat (and launch record), then a watcher tick that reaps it
//                   (model: launch, reap, plan)
// After each step the guard file, the journal's last verdict, the beat and the plan are compared with the rule.
import {existsSync, mkdirSync, readFileSync, rmSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {queueGuard, VERDICTS} from './queue-guard.ts'
import {cleanup, git, initRepo, KIT, lib, rng, sh, stub, tmp, type BridgeResult} from './_bridge.ts'

const PARAMS = {maxStalls: 2, npTrip: 2, seTrip: 3, coolSecs: 600, jMin: 5, jSpan: 11}
const SLUG = 'fixboard__ID-001'

export type Scripted = {kind: 'plan' | 'run' | 'reap', dt: number, v?: 'done' | 'gated' | 'stalled' | 'error', ev?: 'none' | 'verified' | 'reported' | 'freeze', sig?: boolean, delta?: boolean}

export async function bridge(opts: {sequences?: number, length?: number, seed?: number, script?: Scripted[]} = {}): Promise<BridgeResult & {final?: any}> {
  const sequences = opts.script ? 1 : opts.sequences ?? 12, length = opts.script ? opts.script.length : opts.length ?? 8
  let final: any = null
  const r = queueGuard(), it = r.interpreter(), P = r.encodeParams(PARAMS)
  const root = tmp('qguard-')
  let agree = 0, diverge: BridgeResult['diverge'] = null
  const seen = new Set<string>()
  try {
    const g = rng(opts.seed ?? 3)
    for (let seq = 0; seq < sequences && !diverge; seq++) {
      const work = join(root, `s${seq}`), qstub = join(work, 'stub'), bin = join(work, 'bin')
      const ledger = join(work, 'ledger'), runDir = join(ledger, 'queue-runs'), journal = join(work, 'journal.tsv')
      mkdirSync(qstub, {recursive: true}); mkdirSync(bin); mkdirSync(runDir, {recursive: true}); writeFileSync(journal, '')
      stub(bin, 'gh', 'exit 1')
      stub(bin, 'date', 'if [ "$*" = "+%s" ] && [ -n "${FAKE_NOW:-}" ]; then echo "$FAKE_NOW"; else exec /bin/date "$@"; fi')
      const mux = stub(work, 'mux', `if [ "\${1:-}" = capture-pane ]; then\n  for a in "$@"; do case "$a" in *:*) s="\${a##*:}" ;; esac; done\n  [ -n "\${s:-}" ] && [ -f "$QSTUB/$s.during" ] && . "$QSTUB/$s.during"\nfi\nexec "${KIT}/tests/fixtures/queue/fake-mux" "$@"`)
      const board = join(work, 'fixboard'), repo = join(work, 'run')
      mkdirSync(join(board, '_meta/megagoals/pilot'), {recursive: true})
      writeFileSync(join(board, '_meta/megagoals/pilot/POINTER_PROMPT.md'), 'pointer body\n')
      writeFileSync(join(board, '_meta/BACKLOG.md'), '# Backlog\n\n| ID | Item | Notes & source | Status |\n|---|---|---|---|\n| ID-001 | auto + pointer | pilot row #auto #queue{repo=fixboard,pointer=_meta/megagoals/pilot/POINTER_PROMPT.md} | queued |\n')
      initRepo(repo); const first = git(repo, 'rev-parse', 'HEAD')
      writeFileSync(join(repo, 'b'), 'b\n'); git(repo, 'add', '-A'); git(repo, 'commit', '-q', '-m', 'two')
      const pointer = join(work, 'p.txt'); writeFileSync(pointer, 'p\n')
      const base = Math.floor(Date.now() / 1000)
      let now = base
      const env = (extra: Record<string, string> = {}) => ({
        KIT_LEDGER_DIR: ledger, QUEUE_JOURNAL: journal, MUX_CMD: mux, TERMINAL_MUX: 'tmux', QSTUB: qstub, QLOG: join(qstub, 'verbs.log'),
        QUEUE_POLL_SECS: '0', QUEUE_TIMEOUT_SECS: '0', QUEUE_RETRY_SLEEP_SECS: '0', QUEUE_STARTUP_SECS: '0', QUEUE_SUBMIT_SETTLE_SECS: '0',
        QUEUE_MAX_STALLS: String(PARAMS.maxStalls), QUEUE_NOPROGRESS_TRIP: String(PARAMS.npTrip), QUEUE_SAMEERROR_TRIP: String(PARAMS.seTrip),
        QUEUE_COOLDOWN_SECS: String(PARAMS.coolSecs), QUEUE_RETRY_JITTER_MIN: String(PARAMS.jMin), QUEUE_RETRY_JITTER_SPAN: String(PARAMS.jSpan),
        QUEUE_BEAT_STALE_SECS: '1000000000000', QUEUE_BEAT_DEAD_SECS: '1000000000000',
        PATH: `${bin}:${process.env.PATH}`, FAKE_NOW: String(now), ...extra,
      })
      const watch = (extra: Record<string, string> = {}) => sh('bash', [lib('queue/watch-board.sh'), '--board', join(board, '_meta/BACKLOG.md'),
        '--repo-root', board, '--repo-name', 'fixboard', '--journal', journal], {env: {...env(extra), WATCH_QUEUE_CMD: 'true'}})
      const guard = () => {
        const f = join(runDir, `${SLUG}.guard`)
        const kv: Record<string, string> = existsSync(f) ? Object.fromEntries(readFileSync(f, 'utf8').split('\n').filter(Boolean).map(l => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)])) : {}
        const num = (k: string) => /^[0-9]+$/.test(kv[k] ?? '') ? Number(kv[k]) : 0
        const has = (k: string) => /^[0-9]+$/.test(kv[k] ?? '')
        return {stalls: num('stalls'), np: num('noprogress'), se: num('sameerror'), retry: has('retry_after') ? num('retry_after') : null, cool: has('cooldown_until') ? num('cooldown_until') : null}
      }
      const lastVerdict = () => {
        const rows = readFileSync(journal, 'utf8').split('\n').filter(l => l.split('\t')[1] === SLUG)
        return rows.length ? rows[rows.length - 1].split('\t')[2] : 'none'
      }
      const bashView = (planned: boolean | null) => ({...guard(), last: lastVerdict(), beat: existsSync(join(runDir, `${SLUG}.beat`)), planned})
      const ruleView = (st: any, planned: boolean) => ({stalls: st.scalars.stalls, np: st.scalars.np, se: st.scalars.se,
        retry: st.scalars.hasRetry ? st.scalars.retry : null, cool: st.scalars.hasCool ? st.scalars.cool : null,
        last: VERDICTS[st.scalars.last], beat: !!st.scalars.beat, planned})
      const input = (q: Record<string, unknown>) => r.encodeInput({op: 'plan', v: 'stalled', ev: 'none', delta: false, sig: false, t: now, j: 0, ...q} as never)
      let st: any = it.init(P)
      const trace: string[] = []
      for (let step = 0; step < length && !diverge; step++) {
        const sc = opts.script?.[step]
        now += sc ? sc.dt : g.pick([0, 120, 700, 1000, 2000])
        const kind = sc ? sc.kind : g.pick(['plan', 'run', 'run', 'reap'] as const)
        let planned: boolean | null = null, label = ''
        const before = guard()
        if (kind === 'plan') {
          const res = watch()
          planned = res.out.includes('[watch] ID-001 ->')
          st = it.step(P, st, input({op: 'plan', t: now}))
          label = `plan @${now - base}`
        } else if (kind === 'run') {
          const v = sc?.v ?? g.pick(['done', 'gated', 'stalled', 'error'] as const)
          const ev = sc?.ev ?? (v === 'done' || v === 'gated' ? g.pick(['none', 'verified'] as const) : g.pick(['none', 'verified', 'reported', 'freeze'] as const))
          for (const f of ['work', 'dead', 'transcript', 'during']) rmSync(join(qstub, `${SLUG}.${f}`), {force: true})
          if (ev === 'verified') writeFileSync(join(qstub, `${SLUG}.work`), '')
          if (v === 'error') writeFileSync(join(qstub, `${SLUG}.dead`), '')
          if (v === 'done') writeFileSync(join(qstub, `${SLUG}.transcript`), '  RUNNER_DONE\n')
          if (v === 'gated') writeFileSync(join(qstub, `${SLUG}.transcript`), '  RUNNER_GATED: needs a human\n')
          const status = ev === 'reported' ? 'EXIT_SIGNAL: false\\nFILES_CHANGED: 1\\n' : ev === 'freeze' ? 'EXIT_SIGNAL: false\\nQUESTION: true\\n' : ''
          if (status) writeFileSync(join(qstub, `${SLUG}.during`), `printf '${status}' > "$KIT_LEDGER_DIR/queue-runs/${SLUG}.status"\n`)
          const tsv = join(work, 'q.tsv'); writeFileSync(tsv, `${SLUG}\t${repo}\t${pointer}\n`)
          sh('bash', [lib('queue/queue.sh'), 'run', tsv], {env: env()})
          const after = guard()
          // _schedule_retry's jitter is $RANDOM: read the draw back off the alarm it wrote.
          const j = after.retry !== null && after.retry !== before.retry ? Math.max(0, (after.retry - now) / 60 - PARAMS.jMin) : 0
          st = it.step(P, st, input({op: 'launch', t: now}))
          st = it.step(P, st, input({op: 'finish', v, ev, delta: ev === 'verified', t: now, j}))
          label = `run ${v} ${ev} @${now - base}`
        } else {
          if (st.scalars.last === VERDICTS.indexOf('done') || st.scalars.last === VERDICTS.indexOf('gated')) { step--; continue }
          const sig = sc?.sig ?? g.next() < 0.5, delta = sc?.delta ?? (sig && g.next() < 0.5)
          writeFileSync(join(runDir, `${SLUG}.beat`), '')
          rmSync(join(runDir, `${SLUG}.status`), {force: true}); rmSync(join(runDir, `${SLUG}.launch`), {force: true})
          if (sig) {
            writeFileSync(join(runDir, `${SLUG}.status`), 'EXIT_SIGNAL: true\n')
            const tips = sh('bash', ['-c', `git -C "${repo}" for-each-ref --format='%(refname) %(objectname)' refs/heads | cksum`]).out.trim()
            writeFileSync(join(runDir, `${SLUG}.launch`), `repo=${repo}\nhead=${delta ? first : git(repo, 'rev-parse', 'HEAD')}\ntips=${tips}\nsince=2999-01-01T00:00:00Z\n`)
          }
          const res = watch({QUEUE_BEAT_STALE_SECS: '0', QUEUE_BEAT_DEAD_SECS: '0'})
          planned = res.out.includes('[watch] ID-001 ->')
          const after = guard()
          const j = after.retry !== null && after.retry !== before.retry ? Math.max(0, (after.retry - now) / 60 - PARAMS.jMin) : 0
          st = it.step(P, st, input({op: 'launch', t: now}))
          st = it.step(P, st, input({op: 'reap', sig, delta, t: now, j}))
          st = it.step(P, st, input({op: 'plan', t: now}))
          label = `reap sig=${sig} delta=${delta} @${now - base}`
        }
        trace.push(label)
        const want = ruleView(st, planned === null ? false : !!st.scalars.planned), got = bashView(planned)
        if (planned === null) { (want as any).planned = null }
        if (JSON.stringify(want) !== JSON.stringify(got)) diverge = {seed: opts.seed ?? 3, sequence: seq, trace, rule: want, bash: got}
        else { final = {rule: want, bash: got, trace}; agree++; seen.add(`${got.last}/s${got.stalls}/np${got.np}/r${got.retry !== null}/c${got.cool !== null}/p${got.planned}`) }
      }
    }
  } finally { cleanup(root) }
  return {agree, diverge, covered: seen.size, final} as never
}

// F3 reproduction: a row whose every run ends `error` with no progress. The breaker cools it down, but the stall
// ladder never moves, so it is never quarantined and the watcher plans it again after every cooldown, forever.
export const UNBOUNDED: Scripted[] = Array.from({length: 6}, () => [{kind: 'run' as const, dt: 700, v: 'error' as const, ev: 'none' as const}, {kind: 'plan' as const, dt: 700}]).flat()

if (import.meta.url === `file://${process.argv[1]}`) {
  const t0 = Date.now()
  const res = await bridge({sequences: Number(process.env.SEQS ?? 12), length: Number(process.env.LEN ?? 8), seed: Number(process.env.SEED ?? 3)})
  console.log(JSON.stringify(res, null, 1), `${Date.now() - t0}ms`)
  process.exit(res.diverge ? 1 : 0)
}
