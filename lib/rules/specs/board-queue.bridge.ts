// Bridge: one temp board with many rows, each a queued or claimed row with a #queue{} tag built from random repo=
// and pointer= values (traversals, absolute paths, metacharacters, sibling dirs, `.` and `//` parts, missing files),
// run through the real lib/board/parse-board.sh `queue-rows`; each row's gate verdicts are judged here on the
// lexically canonical path (no symlinks, as _canon_path), and whether the bash emitted the row is compared with
// the rule's decision (board-queue.ts).
import {mkdirSync, statSync, writeFileSync} from 'node:fs'
import {dirname, join, posix} from 'node:path'
import {GATES, boardQueue, type Variant} from './board-queue.ts'
import {KIT, run, seeded, tmp, type BridgeResult} from './util.ts'

const SH = join(KIT, 'lib/board/parse-board.sh')
const SEGS = ['_meta', 'megagoals', '.claude', 'goals', 'm', 'ROADMAP.md', 'g.md', '..', '.', '', 'x.md', 'megagoals-evil', 'a$b', 'other']
const CURATED = ['_meta/megagoals/m/ROADMAP.md', '.claude/goals/g.md', './_meta//megagoals/x.md', '_meta/megagoals-evil/x.md',
  '_meta/megagoals/../megagoals/x.md', '/etc/passwd', '.claude/goals/missing.md', '_meta/megagoals/', 'x.md', 'other/x.md', '_meta/megagoals/m']
const isFile = (p: string) => { try { return statSync(p).isFile() } catch { return false } }

export async function bridge(variant: Variant = 'shipped'): Promise<BridgeResult> {
  const f = boardQueue(variant)
  const t = tmp('board-queue')
  try {
    const root = join(t.dir, 'repo')
    for (const p of ['_meta/megagoals/m/ROADMAP.md', '_meta/megagoals/x.md', '.claude/goals/g.md', '_meta/megagoals-evil/x.md', 'other/x.md', 'x.md']) {
      mkdirSync(dirname(join(root, p)), {recursive: true}); writeFileSync(join(root, p), 'x\n')
    }
    const rand = seeded(4)
    const rows: {id: string, line: string, gates: Record<string, boolean>}[] = []
    for (let i = 0; i < 160; i++) {
      const pointer = i < CURATED.length * 2 ? CURATED[i % CURATED.length]
        : (rand(6) === 0 ? '/' : '') + Array.from({length: 1 + rand(5)}, () => SEGS[rand(SEGS.length)]).join('/')
      const repo = i < CURATED.length ? 'myrepo' : ['myrepo', 'myrepo', 'other', 'my;repo', ''][rand(5)]
      const queued = i < CURATED.length * 2 ? true : rand(4) > 0, tag = rand(10) > 0, withRepo = rand(10) > 0, withPtr = rand(10) > 0
      const kv = [withRepo && `repo=${repo}`, withPtr && `pointer=${pointer}`, 'extra=1'].filter(Boolean).join(',')
      const id = `QQ-${i + 1}`
      const line = `| ${id} | item ${i} | ${tag ? `#queue{${kv}}` : 'no tag'} | ${queued ? 'queued [n]' : 'claimed'} |`
      const canon = posix.normalize(`${root}/${pointer}`).replace(/(.)\/$/, '$1')
      const gates = {
        queued, tag, keys: withRepo && withPtr && repo !== '' && pointer !== '',
        repoChars: /^[A-Za-z0-9_-]+$/.test(repo), ptrChars: /^[A-Za-z0-9_./-]+$/.test(pointer), relative: !pointer.startsWith('/'),
        noDotDot: !`/${pointer}/`.includes('/../'), ownRepo: repo === 'myrepo',
        inside: canon.startsWith(`${root}/_meta/megagoals/`) || canon.startsWith(`${root}/.claude/goals/`), exists: isFile(canon),
      }
      rows.push({id, line, gates})
    }
    const board = join(t.dir, 'BACKLOG.md')
    writeFileSync(board, ['| ID | Item | Notes | Status |', '|---|---|---|---|', ...rows.map(r => r.line), ''].join('\n'))
    const res = run(['bash', SH, 'queue-rows', board, 'myrepo', root])
    const emitted = new Set(res.out.split('\n').filter(Boolean).map(l => l.split('\t')[0]))
    let agree = 0
    for (const r of rows) {
      const m = f.run(r.gates as never) as {emit: boolean}
      if (emitted.has(r.id) !== m.emit) return {agree, diverge: {row: r.line, gates: r.gates, bash: emitted.has(r.id), rule: m.emit}}
      agree++
    }
    void GATES
    return {agree, diverge: null}
  } finally { t.done() }
}

if (import.meta.url === `file://${process.argv[1]}`) console.log(JSON.stringify({bridge: await bridge((process.argv[2] ?? 'shipped') as Variant)}, null, 1))
