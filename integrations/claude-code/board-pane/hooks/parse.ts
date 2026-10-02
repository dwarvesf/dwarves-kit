import type { BoardItem, BoardNext, BoardRepo, BoardRow, BoardTasks, BoardTone } from '../types'

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

// Multi-repo board: registry, `bin/board all board` output, and what each view draws.

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

// Worktree staleness: a worktree is stale when its branch is merged into the default branch
// or its tip is older than STALE_DAYS. A detached worktree counts by its HEAD commit age only.
// The main checkout (the first porcelain entry) is never counted.

export const STALE_DAYS = 14
export type Worktree = { path: string; head?: string; branch?: string }

export const parseWorktrees = (porcelain: string): Worktree[] =>
  porcelain
    .split(/\n\s*\n/)
    .map(block => block.split('\n'))
    .flatMap((lines): Worktree[] => {
      const path = lines.find(line => line.startsWith('worktree '))?.slice('worktree '.length)
      if (path === undefined || lines.includes('bare')) return []
      const head = lines.find(line => line.startsWith('HEAD '))?.slice('HEAD '.length)
      const branch = lines.find(line => line.startsWith('branch '))?.slice('branch '.length).replace(/^refs\/heads\//, '')
      return [{ path, head, branch }]
    })

// Linked worktrees on a detached HEAD: the shas whose commit age the caller must look up.
export const detachedHeads = (porcelain: string): string[] =>
  parseWorktrees(porcelain)
    .slice(1)
    .flatMap(worktree => (worktree.branch === undefined && worktree.head ? [worktree.head] : []))

// `origin/main` becomes `main`; empty or unusable output is undefined so the caller falls back.
export const parseDefaultBranch = (output: string): string | undefined => {
  const name = output.trim().replace(/^origin\//, '')
  return name === '' || name === 'HEAD' ? undefined : name
}

export const parseRefList = (output: string): string[] => output.split('\n').map(line => line.trim()).filter(Boolean)

// `<branch> <unix seconds>` per line.
export const parseRefAges = (output: string): Map<string, number> => {
  const ages = new Map<string, number>()
  for (const line of output.split('\n')) {
    const found = /^(\S+)\s+(\d+)$/.exec(line.trim())
    if (found?.[1] && found[2]) ages.set(found[1], Number(found[2]))
  }
  return ages
}

export const countStaleWorktrees = (
  porcelain: string,
  merged: readonly string[],
  tipAges: ReadonlyMap<string, number>,
  detachedAges: ReadonlyMap<string, number>,
  nowMs: number,
  // The default branch tip: a worktree sitting exactly on it was just created, not finished.
  baseHead?: string,
): number => {
  const cutoff = nowMs / 1000 - STALE_DAYS * 86_400
  return parseWorktrees(porcelain)
    .slice(1)
    .filter(worktree => {
      if (worktree.branch !== undefined) {
        const tip = tipAges.get(worktree.branch)
        const isMergedWork = merged.includes(worktree.branch) && worktree.head !== baseHead
        return isMergedWork || (tip !== undefined && tip < cutoff)
      }
      const age = worktree.head ? detachedAges.get(worktree.head) : undefined
      return age !== undefined && age < cutoff
    }).length
}

// NEXT: the ranked picks from `bin/board all priority overview`.

export const NEXT_MAX = 5
const NEXT_SECTIONS: { pattern: RegExp; kind: BoardNext['kind'] | undefined }[] = [
  { pattern: /^DO NOW\b/, kind: 'now' },
  { pattern: /^URGENT, HARDER\b/, kind: 'urgent' },
  { pattern: /^QUICK WINS\b/, kind: 'quick' },
  { pattern: /^(IN FLIGHT|THE REST)\b/, kind: undefined },
]
const NEXT_GLYPH: Record<BoardNext['kind'], string> = { now: '!', urgent: '▲', quick: '+' }
const NEXT_ORDER: BoardNext['kind'][] = ['now', 'urgent', 'quick']

const cleanTitle = (title: string) => title.replace(/\[deadline\]/g, '').replace(/#[a-z][a-z0-9-]*/g, '').replace(/\s+/g, ' ').trim()

export const parseNext = (output: string): BoardNext[] => {
  const rows: BoardNext[] = []
  let repo = ''
  let kind: BoardNext['kind'] | undefined
  for (const line of stripAnsi(output).split('\n')) {
    const header = /^=== (\S+?)(?: \[STALE: \d+ behind upstream\])? ===$/.exec(line)
    if (header?.[1]) {
      repo = header[1]
      kind = undefined
      continue
    }
    const section = NEXT_SECTIONS.find(candidate => candidate.pattern.test(line))
    if (section) {
      kind = section.kind
      continue
    }
    const item = new RegExp(`^\\s+(${ITEM_ID.source})\\s+(.*)$`).exec(line)
    if (item?.[1] && kind && repo) rows.push({ kind, id: item[1], title: cleanTitle(item[2] ?? ''), repo })
  }
  return rows
}

// DO NOW first, then URGENT, then QUICK WINS, registry order inside each, at most NEXT_MAX rows.
export const rankNext = (rows: readonly BoardNext[], filter: string): BoardNext[] =>
  NEXT_ORDER.flatMap(kind => rows.filter(row => row.kind === kind))
    .filter(row => matches(`${row.id} ${row.title} ${row.repo}`, filter))
    .slice(0, NEXT_MAX)

export const nextLabel = (row: BoardNext) => `${NEXT_GLYPH[row.kind]} ${row.id} ${row.title}  ${row.repo}`

export const nextPrompt = (row: BoardNext, repos: readonly BoardRepo[]) =>
  repos.find(repo => repo.name === row.repo)?.isCurrent ? `Work on ${row.id}` : `Work on ${row.id} in ${row.repo}`
