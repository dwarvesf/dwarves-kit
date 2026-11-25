// Bridge: repeated `board run BK-1 --dir <fixed>` (the real lib/board/board-run.sh, never --exec) against a temp
// board whose BK-1 row is readable, missing, duplicated or item-less, open or terminal, with Notes naming the run;
// some scaffold files exist before the first run (sentinel content). After each run: which files exist, which
// run's Notes the pointer and goal files carry (or the sentinel), the WARN line, the exit, and that the board's
// bytes never changed; compared with the rule's compiled step (board-run.ts).
import {existsSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {FILES, boardRun} from './board-run.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/board/board-run.sh')
const ROWS = ['ok', 'missing', 'dup', 'noItem'] as const
const PATHS: Record<(typeof FILES)[number], string> = {roadmap: 'ROADMAP.md', pointer: 'POINTER_PROMPT.md', goal: 'goals/01-widget-parser.md', handoff: 'HANDOFF.md', decisions: 'DECISIONS.md'}

function board(row: (typeof ROWS)[number], terminal: boolean, req: number) {
  const r = `| BK-1 | ${row === 'noItem' ? '' : 'widget parser'} | notes run-${req} end | ${terminal ? 'shipped [PR #1]' : 'queued'} |`
  const rows = row === 'missing' ? [] : row === 'dup' ? [r, r] : [r]
  return ['# Backlog', '', '| ID | Item | Notes | Status |', '|---|---|---|---|', ...rows, '| BK-2 | other | x | queued |', ''].join('\n')
}

export async function bridge(): Promise<BridgeResult> {
  const r = boardRun()
  const step = r.compiled().step
  const t = tmp('board-run')
  let agree = 0
  try {
    const rand = seeded(902)
    for (let i = 0; i < 25; i++) {
      const base = join(t.dir, `c${i}`), dir = join(base, 'mg', 'bk-1'), bl = join(base, '_meta', 'BACKLOG.md')
      mkdirSync(join(base, '_meta'), {recursive: true}); mkdirSync(join(dir, 'goals'), {recursive: true})
      const init: any = {scalars: {warned: 0, refused: 0, boardWrites: 0}, maps: {}}
      for (const f of FILES) {
        const pre = rand(3) === 0
        if (pre) writeFileSync(join(dir, PATHS[f]), 'pre-existing sentinel\n')
        init.scalars[f] = pre ? 1 : 0; init.scalars[`${f}V`] = 0
      }
      let st = init
      const trail: string[] = []
      for (let req = 1; req <= 1 + rand(3); req++) {
        const row = ROWS[rand(5) < 2 ? 0 : rand(4)], terminal = rand(3) === 0
        const text = board(row, terminal, req); writeFileSync(bl, text)
        const res = run(['bash', SH, 'BK-1', '--backlog-file', bl, '--dir', dir], {cwd: base, env: {HOME: base}})
        st = step({}, st, r.encodeInput({row, terminal, req}))
        const m = r.decode(st) as Record<string, any>
        const bash: Record<string, unknown> = {refused: res.code !== 0, warned: res.err.includes('WARN row'), boardSame: readFileSync(bl, 'utf8') === text}
        const want: Record<string, unknown> = {refused: m.refused, warned: m.warned, boardSame: true}
        for (const f of FILES) {
          const p = join(dir, PATHS[f]), here = existsSync(p), body = here ? readFileSync(p, 'utf8') : ''
          const v = body.startsWith('pre-existing sentinel') ? 0 : (f === 'pointer' || f === 'goal') ? Number(/run-(\d+)/.exec(body)?.[1] ?? -1) : 'made'
          bash[f] = here ? v : 'absent'
          want[f] = m[f] ? (m[`${f}V`] === 0 ? 0 : (f === 'pointer' || f === 'goal') ? m[`${f}V`] : 'made') : 'absent'
        }
        trail.push(`${row}${terminal ? '/shipped' : ''}`)
        if (JSON.stringify(bash) !== JSON.stringify(want)) return {agree, diverge: {runs: trail, bash, rule: want, stderr: res.err.trim()}}
        agree++
      }
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge()}, null, 1))
