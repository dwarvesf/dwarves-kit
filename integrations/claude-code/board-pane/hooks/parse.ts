import type { BoardMode, BoardRow, BoardTasks, BoardTone } from '../types'

const ITEM_ID = /[A-Z]+-\d+/
const STALE_TAG = /\s*\[STALE: \d+ behind upstream\]/
const STATE_TONE: Record<string, BoardTone> = { executing: 'cyan', claimed: 'yellow' }

export const stripAnsi = (text: string) => text.replace(/\x1b\[[0-9;]*m/g, '')

const text = (value: string, isDim = false, isBold = false): BoardRow => ({ kind: 'text', text: value, isDim, isBold })

// Repo mode: `queued:` style headers, then `  ID-1  title` rows under each.
export const parseRepoRows = (lines: readonly string[]): BoardRow[] => {
  let tone: BoardTone | undefined
  return lines.map((line): BoardRow => {
    const header = /^([a-z]+):\s*$/.exec(line)
    if (header?.[1]) {
      tone = STATE_TONE[header[1]]
      return text(line, false, true)
    }
    const item = /^\s+(\S*?)(\s|$)/.exec(line)
    const id = item?.[1]
    if (id && new RegExp(`^${ITEM_ID.source}$`).test(id)) return { kind: 'item', id, text: line.trim(), tone, isDim: false }
    return text(line)
  })
}

// All mode: `<repo>  <ID> [STALE: N behind upstream]`, `<repo>  (no queued items)`, and a
// trailing `STALE CHECKOUTS` summary the per-row tags already say. Idle repos fold into one row.
export const parseAllRows = (lines: readonly string[]): BoardRow[] => {
  const rows: BoardRow[] = []
  const idle: string[] = []
  for (const line of lines) {
    if (line.trim() === '' || line.startsWith('STALE CHECKOUTS')) continue
    const isStale = STALE_TAG.test(line)
    const body = line.replace(STALE_TAG, '').trim()
    const parts = /^(\S+)\s+(.*)$/.exec(body)
    const repo = parts?.[1]
    const rest = parts?.[2]
    if (repo && rest && new RegExp(`^${ITEM_ID.source}$`).test(rest)) {
      rows.push({ kind: 'item', id: rest, repo, text: `${repo}  ${rest}${isStale ? ' ?' : ''}`, isDim: isStale })
    } else if (repo && rest && /^\(.*\)$/.test(rest)) {
      idle.push(repo)
    } else {
      rows.push(text(line))
    }
  }
  if (idle.length > 0) rows.push(text(`+${idle.length} idle: ${idle.join(', ')}`, true))
  return rows
}

export const parseRows = (mode: BoardMode, output: string): BoardRow[] => {
  const lines = stripAnsi(output).trimEnd().split('\n')
  return mode === 'all' ? parseAllRows(lines) : parseRepoRows(lines)
}

export const errorRows = (message: string): BoardRow[] =>
  stripAnsi(message).trimEnd().split('\n').map(line => text(line, true))

export const promptFor = (row: Extract<BoardRow, { kind: 'item' }>) =>
  row.repo ? `Work on ${row.id} in ${row.repo}` : `Work on ${row.id}`

export const clockText = (ms: number) => {
  const at = new Date(ms)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${pad(at.getHours())}:${pad(at.getMinutes())}`
}

// Counts the item rows under the `queued:` and `executing:` headers of parseRepoRows output.
export const countTasks = (rows: readonly BoardRow[]): BoardTasks => {
  const tasks: BoardTasks = { queued: 0, executing: 0 }
  let section = ''
  for (const row of rows) {
    if (row.kind === 'text' && row.isBold) section = row.text.replace(/:\s*$/, '')
    else if (row.kind === 'item' && (section === 'queued' || section === 'executing')) tasks[section] += 1
  }
  return tasks
}

export const countWorktrees = (porcelain: string) =>
  Math.max(0, porcelain.split('\n').filter(line => line.startsWith('worktree ')).length - 1)

export const countPrs = (json: string): number | undefined => {
  try {
    const parsed: unknown = JSON.parse(json)
    return Array.isArray(parsed) ? parsed.length : undefined
  } catch {
    return undefined
  }
}
