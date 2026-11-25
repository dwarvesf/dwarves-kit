// Bridge: a temp BACKLOG.md with the row BK-1 (one row, two rows, or none; any declared state or an undeclared
// one) beside a decoy BK-10, then the real lib/board/backlog.sh `set` (under its own board lock) for every target
// and seeded sequences. The row's leading keyword, its row count, the notice and the exit are compared with the
// rule's compiled step (board-set.ts).
import {readFileSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {STATES, boardSet} from './board-set.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/board/backlog.sh')
const TARGETS = [...STATES, 'bogus'] as const

function board(state: string, rows: number) {
  const row = `| BK-1 | row one | some notes | ${state} [earlier note] |`
  return ['# Backlog', '', '## Active queue', '', '| ID | Title | Notes | Status |', '|---|---|---|---|',
    ...Array.from({length: rows}, () => row), '| BK-10 | decoy | n | queued |', ''].join('\n')
}

function read(file: string) {
  const lines = readFileSync(file, 'utf8').split('\n').filter(l => /^\| *BK-1 *\|/.test(l))
  const cells = (lines[0] ?? '').split('|')
  const lead = (cells[cells.length - 2] ?? '').trim().split(/[ [(]/)[0]
  return {rows: lines.length, st: (STATES as readonly string[]).includes(lead) ? lead : 'other'}
}

export async function bridge(): Promise<BridgeResult> {
  const r = boardSet()
  const step = r.compiled().step
  const t = tmp('board-set')
  let agree = 0
  try {
    const file = join(t.dir, 'BACKLOG.md')
    const check = (start: string, rows: number, seq: string[]) => {
      writeFileSync(file, board(start, rows))
      let st: any = {scalars: {st: [...STATES, 'other'].indexOf((STATES as readonly string[]).includes(start) ? start : 'other'), rows, notice: 0, refused: 0}, maps: {}}
      const trail: string[] = []
      for (const to of seq) {
        const res = run(['bash', SH, 'set', 'BK-1', to], {env: {BACKLOG_FILE: file}})
        st = step({}, st, r.encodeInput({to: to as never}))
        const m = r.decode(st) as {st: string, rows: number, notice: string, refused: boolean}
        const got = read(file)
        const notice = res.err.includes('reopens from terminal') ? 'reopen' : res.err.includes('moves back from') ? 'back' : 'none'
        const bash = {st: got.st, rows: got.rows, notice, refused: res.code !== 0}
        trail.push(to)
        if ((rows > 0 && bash.st !== m.st) || bash.rows !== m.rows || bash.notice !== m.notice || bash.refused !== m.refused)
          return {start, rows, seq: trail, bash, rule: m, stderr: res.err.trim()}
        if (!readFileSync(file, 'utf8').includes('| BK-10 | decoy | n | queued |')) return {start, rows, seq: trail, error: 'decoy touched'}
        agree++
      }
      return null
    }
    for (const s of [...STATES, 'wip']) for (const to of TARGETS) { const d = check(s, 1, [to]); if (d) return {agree, diverge: d} }
    for (const rows of [0, 2]) for (const to of ['shipped', 'queued', 'bogus']) { const d = check('claimed', rows, [to]); if (d) return {agree, diverge: d} }
    const rand = seeded(417)
    for (let i = 0; i < 30; i++) {
      const seq = Array.from({length: 2 + rand(4)}, () => TARGETS[rand(TARGETS.length)])
      const d = check(STATES[rand(STATES.length)], rand(8) === 0 ? 2 : 1, seq); if (d) return {agree, diverge: d}
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

// The refuted brief promise on the real bash: queued -> shipped skips the whole declared path, silently.
export async function confirm() {
  const t = tmp('board-set-cx')
  try {
    const file = join(t.dir, 'BACKLOG.md'); writeFileSync(file, board('queued', 1))
    const res = run(['bash', SH, 'set', 'BK-1', 'shipped'], {env: {BACKLOG_FILE: file}})
    return [{law: 'a move off the declared next path is announced', repro: 'BACKLOG_FILE=b.md bash lib/board/backlog.sh set BK-1 shipped  (row BK-1 queued)',
      reproduced: res.code === 0 && read(file).st === 'shipped' && res.err.trim() === '', exit: res.code, stderr: res.err.trim()}]
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge(), confirm: await confirm()}, null, 1))
