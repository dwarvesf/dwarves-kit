import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { BoardRepo, BoardState, BoardSummary } from '../types'
import {
  QUEUED_SHOWN,
  WIDE_COLUMNS,
  buildOverview,
  clockText,
  countPrs,
  countTasks,
  countWorktrees,
  expandHome,
  filterItems,
  fit,
  inFlightItems,
  isIdle,
  itemLabel,
  itemTone,
  mergeRepos,
  parseAllBoard,
  parseRegistry,
  parseRepoRows,
  parseSingleBoard,
  promptFor,
  queuedItems,
  repoLabel,
  stripAnsi,
  totals,
} from './parse'

const PANE = 'board'
const REFRESH_MS = 60_000
const PR_TTL_MS = 5 * 60_000
const initial: BoardState = { repos: [], filter: '', isExpanded: false, isFallback: false, errorLines: [], refreshedAt: '' }
const state = atom({ plugin: 'board-pane', key: 'state' } as const, initial)
const emptySummary: BoardSummary = {}
const summary = atom({ plugin: 'board-pane', key: 'summary' } as const, emptySummary)

// Same resolution the kit's other wrappers use: $DWARVES_KIT, else the bash-install path.
const resolveBoard = async ($: EngineInterface) => {
  const kit = await $.env.get('DWARVES_KIT')
  if (kit) return `${kit}/bin/board`
  const home = await $.env.get('HOME')
  return `${home ?? '~'}/.claude/dwarves-kit/bin/board`
}

// `board` needs an explicit --backlog-file; this is the single-repo form `bin/board --help` documents.
const singleArgv = (board: string, cwd: string) => [board, 'board', '--backlog-file', `${cwd}/_meta/BACKLOG.md`]

const lastSegment = (path: string) => path.split('/').filter(Boolean).pop() ?? 'repo'

type Loaded = Pick<BoardState, 'repos' | 'isFallback' | 'errorLines'>

// One call feeds both views: `all board` over the registry. Anything short of a clean answer
// falls back to the session repo alone, so the pane is never empty for want of a registry.
const loadRepos = async ($: EngineInterface, cwd: string): Promise<Loaded> => {
  const board = await resolveBoard($)
  const home = await $.env.get('HOME')
  const registryFile = expandHome((await $.env.get('BOARD_REGISTRY')) || `${cwd}/_meta/boards.txt`, home)
  try {
    const registry = parseRegistry(await $.fs.read(registryFile), home)
    const run = await $.process.run([board, 'all', 'board', '--registry', registryFile, '--repo-root', cwd], { env: { NO_COLOR: '1' } })
    const parsed = run.exitCode === 0 ? parseAllBoard(run.stdout) : []
    if (parsed.length > 0) return { repos: mergeRepos(parsed, registry, cwd), isFallback: false, errorLines: [] }
  } catch {
    // no readable registry: fall through to the single-repo view
  }
  try {
    const run = await $.process.run(singleArgv(board, cwd), { env: { NO_COLOR: '1' } })
    if (run.exitCode !== 0) return { repos: [], isFallback: true, errorLines: stripAnsi(run.stderr || `board exited ${run.exitCode}`).trimEnd().split('\n') }
    const repo: BoardRepo = { ...parseSingleBoard(run.stdout, lastSegment(cwd)), isCurrent: true }
    return { repos: [repo], isFallback: true, errorLines: [] }
  } catch (err) {
    return { repos: [], isFallback: true, errorLines: [`board could not start: ${String(err)}`] }
  }
}

const refresh = async ($: EngineInterface) => {
  const loaded = await loadRepos($, await $.session.cwd())
  const refreshedAt = clockText(await $.clock.now())
  await update($, state, prev => ({ ...prev, ...loaded, refreshedAt }))
}

// One timer per module load. Each tick re-checks the pane, so a closed pane ends the timer.
let timer: Timer | undefined
const autoRefresh = ($: EngineInterface) => {
  timer?.cancel()
  timer = $.clock.every(REFRESH_MS, async () => {
    const isOpen = (await $.ui.panes()).some(pane => pane.id === PANE)
    if (!isOpen) {
      timer?.cancel()
      timer = undefined
      return
    }
    await refresh($)
  })
}

type Target = { kind: 'overview' } | { kind: 'here' } | { kind: 'repo'; name: string }

const openBoard = async ($: EngineInterface, target: Target) => {
  await refresh($)
  const { repos, isFallback } = await read($, state)
  const named = target.kind === 'repo' ? repos.find(repo => repo.name === target.name) : undefined
  const here = repos.find(repo => repo.isCurrent)
  const repo = isFallback ? here : target.kind === 'here' ? here : named
  await update($, state, prev => ({ ...prev, repo: repo?.name, filter: '', isExpanded: false }))
  await $.ui.open({ id: PANE, title: 'Board' })
  autoRefresh($)
}

// The band's tasks button: a second press closes the pane, a first opens the current repo's view.
const toggleBoard = async ($: EngineInterface) => {
  const isOpen = (await $.ui.panes()).some(pane => pane.id === PANE)
  if (isOpen) await $.ui.close({ id: PANE })
  else await openBoard($, { kind: 'here' })
}

// Each source is independent: a failing one drops its own segment and nothing else.
const taskCounts = async ($: EngineInterface, cwd: string) => {
  try {
    const run = await $.process.run(singleArgv(await resolveBoard($), cwd), { env: { NO_COLOR: '1' } })
    return run.exitCode === 0 ? countTasks(parseRepoRows(stripAnsi(run.stdout).trimEnd().split('\n'))) : undefined
  } catch {
    return undefined
  }
}

const handoffCount = async ($: EngineInterface, cwd: string) => {
  try {
    const entries = await $.fs.list(`${cwd}/.claude/handoffs`)
    return entries.filter(entry => entry.kind === 'file' && entry.name.endsWith('.md')).length
  } catch {
    return undefined
  }
}

const worktreeCount = async ($: EngineInterface, cwd: string) => {
  try {
    const run = await $.process.run(['git', '-C', cwd, 'worktree', 'list', '--porcelain'])
    return run.exitCode === 0 ? countWorktrees(run.stdout) : undefined
  } catch {
    return undefined
  }
}

// gh takes about a second, so the answer, failure included, is reused for PR_TTL_MS.
const openPrCount = async ($: EngineInterface) => {
  try {
    const run = await $.process.run(['gh', 'pr', 'list', '--author', '@me', '--state', 'open', '--json', 'number'])
    return run.exitCode === 0 ? countPrs(run.stdout) : undefined
  } catch {
    return undefined
  }
}

const refreshSummary = async ($: EngineInterface) => {
  const cwd = await $.session.cwd()
  const now = await $.clock.now()
  const previous = await read($, summary)
  const isPrStale = previous.prsAt === undefined || now - previous.prsAt >= PR_TTL_MS
  const [tasks, handoffs, worktrees] = await Promise.all([taskCounts($, cwd), handoffCount($, cwd), worktreeCount($, cwd)])
  const prs = isPrStale ? await openPrCount($) : previous.prs
  await update($, summary, () => ({ tasks, handoffs, worktrees, prs, prsAt: isPrStale ? now : previous.prsAt }))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'board', description: 'Open the kit board in a pane (/board here or /board <repo> for one repo)' })
    await refreshSummary($)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) await refreshSummary($)
    return next(e)
  })

  on('command.run', { command: 'board' }, async ($, e) => {
    const arg = e.args.trim()
    const target: Target =
      arg === '' || arg === 'all' ? { kind: 'overview' } : arg === 'here' ? { kind: 'here' } : { kind: 'repo', name: arg }
    await openBoard($, target)
    return { text: 'Board pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const ui = $.ui.resolve(e)
    const { Box, Text, Button } = ui
    // Not every surface draws an Input; where it is missing the filter is skipped.
    const Input = 'Input' in ui ? ui.Input : undefined
    const board = await read($, state)
    const { repos, filter, isExpanded, isFallback, errorLines, refreshedAt } = board
    const isWide = e.props.bodyColumns >= WIDE_COLUMNS
    // The hotkey label and a tone bullet take about 6 cells; the rest is the row.
    const room = Math.max(12, e.props.bodyColumns - 6)
    const open = repos.find(repo => repo.name === board.repo)
    const back = () => update($, state, prev => ({ ...prev, repo: undefined, filter: '', isExpanded: false }))
    const setFilter = (value: string) => update($, state, prev => ({ ...prev, filter: value }))

    const controls = (
      <Box flexDirection="row">
        {open && !isFallback && <Button key="back" label="‹ back" hotkey="b" onPress={back} />}
        <Button key="refresh" label="Refresh" hotkey="r" onPress={() => refresh($)} />
        <Button key="close" label="Close" hotkey="q" role="dismiss" onPress={() => $.ui.close({ id: PANE })} />
      </Box>
    )
    const filterInput = Input && (
      <Input key="filter" placeholder="filter repos, IDs, titles" value={filter} onInput={setFilter} onSubmit={setFilter} />
    )
    const notes = (
      <Box flexDirection="column">
        {isFallback && <Text dimColor>no registry: set BOARD_REGISTRY for the cross-repo view</Text>}
        {errorLines.map(line => (
          <Text dimColor wrap="truncate-end">
            {line}
          </Text>
        ))}
      </Box>
    )
    const stamp = refreshedAt ? ` · ${refreshedAt}` : ''

    if (open) {
      const flying = filterItems(inFlightItems(open), filter)
      const queued = filterItems(queuedItems(open), filter)
      const shown = isExpanded ? queued : queued.slice(0, QUEUED_SHOWN)
      let itemNo = 0
      const row = (item: BoardRepo['items'][number]) => {
        itemNo += 1
        const tone = itemTone(item.state)
        // Button has no color prop, so the state tone rides on a bullet beside it.
        // A press fills the prompt instead of submitting: a stray key must never start a turn.
        return (
          <Box flexDirection="row">
            {tone && <Text color={tone}>* </Text>}
            <Button
              key={`item-${itemNo}`}
              plain
              label={itemLabel(item, room, isWide)}
              hotkey={itemNo <= 9 ? String(itemNo) : undefined}
              onPress={() => $.prompt.fill({ text: promptFor(item, open) })}
            />
          </Box>
        )
      }
      return (
        <Box flexDirection="column">
          {controls}
          <Box key="repo-title" flexDirection="row">
            <Text bold>{open.name}</Text>
            {open.behind > 0 && <Text dimColor>{`   ↓${open.behind} behind upstream`}</Text>}
          </Box>
          {filterInput}
          {notes}
          {flying.length > 0 && <Text bold>{`IN FLIGHT ${flying.length}`}</Text>}
          {flying.map(row)}
          {queued.length > 0 && <Text bold>{`QUEUED ${queued.length}`}</Text>}
          {shown.map(row)}
          {!isExpanded && queued.length > shown.length && (
            <Button
              key="more"
              plain
              dimColor
              label={`+ ${queued.length - shown.length} more`}
              onPress={() => update($, state, prev => ({ ...prev, isExpanded: true }))}
            />
          )}
          <Text dimColor>{`press an item to put it in the prompt · Esc back${stamp}`}</Text>
        </Box>
      )
    }

    const sum = totals(repos)
    const overview = buildOverview(repos, filter)
    const nameWidth = Math.min(16, Math.max(0, ...repos.map(repo => repo.name.length)))
    let repoNo = 0
    return (
      <Box flexDirection="column">
        {controls}
        <Box key="header" flexDirection="row">
          <Text bold>{`Board · ${sum.repos} repos · ${sum.active} in flight · ${sum.queued} queued`}</Text>
        </Box>
        {filterInput}
        {notes}
        {overview.groups.map(group => (
          <Box key={`rail-${group.rail}`} flexDirection="column">
            <Text dimColor>{group.rail}</Text>
            {group.repos.map(repo => {
              repoNo += 1
              return (
                <Button
                  key={`repo-${repo.name}`}
                  plain
                  label={fit(repoLabel(repo, nameWidth, isWide), room)}
                  hotkey={repoNo <= 9 ? String(repoNo) : undefined}
                  onPress={() => update($, state, prev => ({ ...prev, repo: repo.name, filter: '', isExpanded: false }))}
                />
              )
            })}
          </Box>
        ))}
        {overview.idle.length > 0 && (
          <Box key="idle" flexDirection="row">
            <Text dimColor wrap="truncate-end">{`idle  ${overview.idle.join(' · ')}`}</Text>
          </Box>
        )}
        <Text dimColor>{`press a repo to open it · Esc back${stamp}`}</Text>
      </Box>
    )
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    if (e.props.hasSurvey) return next(e)
    const { tasks, handoffs, worktrees, prs } = await read($, summary)
    const { Box, Text, Button } = $.ui.resolve(e)
    const segments = []
    if (tasks) {
      segments.push(
        <Box key="seg-tasks" flexDirection="row">
          <Button key="band-tasks" plain dimColor label="tasks" hotkey="b" onPress={() => toggleBoard($)} />
          <Text color="cyan"> {tasks.queued}</Text>
          <Text dimColor>q </Text>
          <Text color={tasks.executing > 0 ? 'yellow' : undefined}>{tasks.executing}</Text>
          <Text dimColor>act</Text>
        </Box>,
      )
    }
    if (handoffs !== undefined) {
      segments.push(
        <Box key="seg-handoffs" flexDirection="row">
          <Text>{handoffs}</Text>
          <Text dimColor>ho</Text>
        </Box>,
      )
    }
    if (worktrees !== undefined) {
      segments.push(
        <Box key="seg-worktrees" flexDirection="row">
          <Text>{worktrees}</Text>
          <Text dimColor>wt</Text>
        </Box>,
      )
    }
    if (prs !== undefined) {
      segments.push(
        <Box key="seg-prs" flexDirection="row">
          <Text>{prs}</Text>
          <Text dimColor>pr</Text>
        </Box>,
      )
    }
    if (segments.length === 0) return next(e)
    return (
      <Box flexDirection="row">
        {segments.flatMap((segment, index) => (index === 0 ? [segment] : [<Text dimColor>{' · '}</Text>, segment]))}
      </Box>
    )
  })
}
