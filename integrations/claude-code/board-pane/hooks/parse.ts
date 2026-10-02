import type { BoardItem, BoardRepo, BoardRow, BoardTasks, BoardTone } from '../types'

const ITEM_ID = /[A-Z]+-\d+/
const STATE_TONE: Record<string, BoardTone> = { executing: 'cyan', claimed: 'yellow', speccing: 'magenta', validated: 'magenta' }

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

export const fit = (value: string, width: number) => (value.length <= width ? value : `${value.slice(0, Math.max(0, width - 1))}…`)

// ---------------------------------------------------------------------------
// Multi-repo board: registry, `bin/board all board` output, and what each view draws.
// ---------------------------------------------------------------------------

// In-flight states in the order the repo view lists them.
export const IN_FLIGHT = ['executing', 'validated', 'speccing', 'claimed'] as const
const STATE_GLYPH: Record<string, string> = { executing: '▶', validated: '◆', speccing: '◆', claimed: '●' }
export const WIDE_COLUMNS = 70
export const QUEUED_SHOWN = 8

export type RegistryEntry = { name: string; path: string; rail?: string }
export type ParsedRepo = { name: string; behind: number; items: BoardItem[] }

export const expandHome = (path: string, home: string | undefined) =>
  path.startsWith('~') && home ? `${home}${path.slice(1)}` : path

// `<name> <BACKLOG path> [...]`, with an optional `rail=<x>` token in any column.
export const parseRegistry = (source: string, home?: string): RegistryEntry[] =>
  source.split('\n').flatMap((line): RegistryEntry[] => {
    const tokens = line.trim().split(/\s+/)
    const name = tokens[0]
    const path = tokens[1]
    if (!name || !path || name.startsWith('#')) return []
    const rail = tokens.map(token => /^rail=(.+)$/.exec(token)?.[1]).find(found => found !== undefined)
    return [{ name, path: expandHome(path, home), rail }]
  })

const parseItems = (lines: readonly string[]): BoardItem[] => {
  const items: BoardItem[] = []
  let state = ''
  for (const line of lines) {
    const header = /^([a-z]+):\s*$/.exec(line)
    if (header?.[1]) {
      state = header[1]
      continue
    }
    const item = new RegExp(`^\\s+(${ITEM_ID.source})\\s+(.*)$`).exec(line)
    if (item?.[1] && state) items.push({ id: item[1], title: (item[2] ?? '').trim(), state })
  }
  return items
}

// `bin/board all board`: `=== <name> [STALE: N behind upstream] ===`, then each repo's board.
export const parseAllBoard = (output: string): ParsedRepo[] => {
  const repos: ParsedRepo[] = []
  let current: { name: string; behind: number; lines: string[] } | undefined
  const close = () => {
    if (current) repos.push({ name: current.name, behind: current.behind, items: parseItems(current.lines) })
  }
  for (const line of stripAnsi(output).split('\n')) {
    const header = /^=== (\S+?)(?: \[STALE: (\d+) behind upstream\])? ===$/.exec(line)
    if (header?.[1]) {
      close()
      current = { name: header[1], behind: Number(header[2] ?? 0), lines: [] }
    } else if (current) {
      current.lines.push(line)
    }
  }
  close()
  return repos
}

export const parseSingleBoard = (output: string, name: string): ParsedRepo => ({
  name,
  behind: 0,
  items: parseItems(stripAnsi(output).split('\n')),
})

export const isCurrentRepo = (backlogPath: string | undefined, cwd: string) =>
  backlogPath !== undefined &&
  (backlogPath.startsWith(`${cwd}/`) || backlogPath.replace(/\/_meta\/BACKLOG\.md$/, '') === cwd)

export const mergeRepos = (parsed: readonly ParsedRepo[], registry: readonly RegistryEntry[], cwd: string): BoardRepo[] =>
  parsed.map(repo => {
    const entry = registry.find(candidate => candidate.name === repo.name)
    return { ...repo, rail: entry?.rail, isCurrent: isCurrentRepo(entry?.path, cwd) }
  })

export const inFlightItems = (repo: BoardRepo) => IN_FLIGHT.flatMap(state => repo.items.filter(item => item.state === state))
export const queuedItems = (repo: BoardRepo) => repo.items.filter(item => item.state === 'queued')
export const isIdle = (repo: BoardRepo) => inFlightItems(repo).length === 0 && queuedItems(repo).length === 0

const matches = (value: string, filter: string) => value.toLowerCase().includes(filter.trim().toLowerCase())

export const filterItems = (items: readonly BoardItem[], filter: string) =>
  items.filter(item => matches(`${item.id} ${item.title}`, filter))

const isRepoVisible = (repo: BoardRepo, filter: string) =>
  filter.trim() === '' ||
  matches(repo.name, filter) ||
  matches(repo.rail ?? '', filter) ||
  filterItems([...inFlightItems(repo), ...queuedItems(repo)], filter).length > 0

export const totals = (repos: readonly BoardRepo[]) => ({
  repos: repos.length,
  active: repos.reduce((sum, repo) => sum + inFlightItems(repo).length, 0),
  queued: repos.reduce((sum, repo) => sum + queuedItems(repo).length, 0),
})

export type RailGroup = { rail: string; repos: BoardRepo[] }
export type Overview = { groups: RailGroup[]; idle: string[] }

// Groups by rail in registry order of first appearance; the current repo leads its group.
export const buildOverview = (repos: readonly BoardRepo[], filter: string): Overview => {
  const visible = repos.filter(repo => isRepoVisible(repo, filter))
  const busy = visible.filter(repo => !isIdle(repo))
  const rails = [...new Set(busy.map(repo => (repo.rail ?? 'other').toUpperCase()))]
  const groups = rails.map(rail => {
    const members = busy.filter(repo => (repo.rail ?? 'other').toUpperCase() === rail)
    return { rail, repos: [...members.filter(repo => repo.isCurrent), ...members.filter(repo => !repo.isCurrent)] }
  })
  return { groups, idle: visible.filter(isIdle).map(repo => repo.name) }
}

export const repoLabel = (repo: BoardRepo, nameWidth: number, isWide: boolean) => {
  const flying = inFlightItems(repo)
  const queued = queuedItems(repo)
  const next = flying[0] ?? queued[0]
  const parts = [
    `${repo.isCurrent ? '◉' : ' '} ${repo.name.padEnd(nameWidth)}`,
    `${flying.length} active`,
    `${queued.length} queued`,
  ]
  if (repo.behind > 0) parts.push(`↓${repo.behind}`)
  if (isWide && next) parts.push(`${next.id} ${next.title}`)
  return parts.join('  ')
}

export const itemGlyph = (state: string) => STATE_GLYPH[state] ?? '○'
export const itemTone = (state: string) => STATE_TONE[state]

// `<glyph> <ID>  <title>`, the state word at the right edge when the pane is wide enough.
export const itemLabel = (item: BoardItem, room: number, isWide: boolean) => {
  const body = `${itemGlyph(item.state)} ${item.id}  ${item.title}`
  if (!isWide || item.state === 'queued') return fit(body, room)
  const tail = `  ${item.state}`
  return `${fit(body, room - tail.length).padEnd(room - tail.length)}${tail}`
}

export const promptFor = (item: BoardItem, repo: BoardRepo) =>
  repo.isCurrent ? `Work on ${item.id}` : `Work on ${item.id} in ${repo.name}`
