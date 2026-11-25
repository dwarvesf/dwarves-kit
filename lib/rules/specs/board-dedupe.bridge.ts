// Bridge: boards holding two or three copies of BK-1 (each copy's Notes cell names it) in every mix of leading
// keywords (seeded), run the real `backlog.sh dedupe BK-1` and `backlog.sh dedupe-all <file>` on fresh copies, and
// compare the surviving copy with the rule's decision (board-dedupe.ts).
import {readFileSync, writeFileSync} from 'node:fs'
import {join} from 'node:path'
import {LEADS, boardDedupe} from './board-dedupe.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/board/backlog.sh')
const word = (l: string) => l === 'other' ? 'wip' : l

function board(copies: string[]) {
  return ['# Backlog', '', '| ID | Title | Notes | Status |', '|---|---|---|---|', '| BK-2 | other row | x | queued |',
    ...copies.map((c, i) => `| BK-1 | row one | copy-${i} | ${word(c)} [n] |`), ''].join('\n')
}
const survivor = (file: string) => {
  const rows = readFileSync(file, 'utf8').split('\n').filter(l => /^\| *BK-1 *\|/.test(l))
  return rows.length === 1 ? Number(/copy-(\d)/.exec(rows[0])![1]) : -rows.length
}

export async function bridge(): Promise<BridgeResult> {
  const f = boardDedupe()
  const t = tmp('board-dedupe')
  let agree = 0
  try {
    const rand = seeded(308)
    const cases: string[][] = []
    for (const a of LEADS) for (const b of LEADS) cases.push([a, b])
    for (let i = 0; i < 60; i++) cases.push([LEADS[rand(LEADS.length)], LEADS[rand(LEADS.length)], LEADS[rand(LEADS.length)]])
    for (const copies of cases) {
      const a = join(t.dir, 'a.md'), b = join(t.dir, 'b.md')
      writeFileSync(a, board(copies)); writeFileSync(b, board(copies))
      run(['bash', SH, 'dedupe', 'BK-1'], {env: {BACKLOG_FILE: a}})
      run(['bash', SH, 'dedupe-all', b], {env: {BACKLOG_FILE: b}})
      const m = f.run({c0: copies[0], c1: copies[1], c2: copies[2] ?? 'queued', three: copies.length === 3} as never) as {keep: number, keepAll: number}
      const bash = {keep: survivor(a), keepAll: survivor(b)}
      if (bash.keep !== m.keep || bash.keepAll !== m.keepAll) return {agree, diverge: {copies, bash, rule: m}}
      if (!readFileSync(a, 'utf8').includes('| BK-2 | other row | x | queued |')) return {agree, diverge: {copies, error: 'another row was dropped'}}
      agree++
    }
    return {agree, diverge: null}
  } finally { t.done() }
}

// The refuted reviewer law on the real bash: [claimed, queued] -> dedupe keeps the queued copy, dedupe-all the claimed.
export async function confirm() {
  const t = tmp('board-dedupe-cx')
  try {
    const a = join(t.dir, 'a.md'), b = join(t.dir, 'b.md')
    writeFileSync(a, board(['claimed', 'queued'])); writeFileSync(b, board(['claimed', 'queued']))
    run(['bash', SH, 'dedupe', 'BK-1'], {env: {BACKLOG_FILE: a}}); run(['bash', SH, 'dedupe-all', b], {env: {BACKLOG_FILE: b}})
    return [{law: 'dedupe never drops a flipped (non-queued) copy to keep a queued one',
      repro: 'two BK-1 rows, `claimed` then `queued`; BACKLOG_FILE=b.md bash lib/board/backlog.sh dedupe BK-1',
      reproduced: survivor(a) === 1 && survivor(b) === 0, dedupeKeeps: survivor(a) === 1 ? 'queued' : 'claimed', dedupeAllKeeps: survivor(b) === 0 ? 'claimed' : 'queued'}]
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge(), confirm: await confirm()}, null, 1))
