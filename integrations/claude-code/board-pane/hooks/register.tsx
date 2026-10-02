import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { BoardMode, BoardRow, BoardState, BoardSummary } from '../types'
import { clockText, countPrs, countTasks, countWorktrees, errorRows, parseRepoRows, parseRows, promptFor, stripAnsi } from './parse'

const PANE = 'board'
const REFRESH_MS = 60_000
const PR_TTL_MS = 5 * 60_000
const initial: BoardState = { rows: [], mode: 'repo', refreshedAt: '' }
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

// Argv forms are the ones documented in `bin/board --help`: `board` needs an explicit
// --backlog-file, `all next` takes --repo-root and reads the consumer's boards.txt.
const argvFor = (board: string, mode: BoardMode, cwd: string) =>
  mode === 'all'
    ? [board, 'all', 'next', '--repo-root', cwd]
    : [board, 'board', '--backlog-file', `${cwd}/_meta/BACKLOG.md`]

const fit = (text: string, width: number) => (text.length <= width ? text : `${text.slice(0, width - 1)}…`)

const refresh = async ($: EngineInterface, mode: BoardMode) => {
  const cwd = await $.session.cwd()
  const board = await resolveBoard($)
  let rows: BoardRow[]
  try {
    const run = await $.process.run(argvFor(board, mode, cwd), { env: { NO_COLOR: '1' } })
    rows = run.exitCode === 0 ? parseRows(mode, run.stdout) : errorRows(run.stderr || `board exited ${run.exitCode}`)
  } catch (err) {
    rows = errorRows(`board could not start: ${String(err)}`)
  }
  const refreshedAt = clockText(await $.clock.now())
  await update($, state, () => ({ rows, mode, refreshedAt }))
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
    await refresh($, (await read($, state)).mode)
  })
}

const openBoard = async ($: EngineInterface, mode: BoardMode) => {
  await refresh($, mode)
  await $.ui.open({ id: PANE, title: mode === 'all' ? 'Board: all repos' : 'Board' })
  autoRefresh($)
}

// Each source is independent: a failing one drops its own segment and nothing else.
const taskCounts = async ($: EngineInterface, cwd: string) => {
  try {
    const run = await $.process.run(argvFor(await resolveBoard($), 'repo', cwd), { env: { NO_COLOR: '1' } })
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
    await $.command.register({ name: 'board', description: 'Open the kit board in a pane (/board all for the cross-repo view)' })
    await refreshSummary($)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) await refreshSummary($)
    return next(e)
  })

  on('command.run', { command: 'board' }, async ($, e) => {
    const mode: BoardMode = e.args.trim() === 'all' ? 'all' : 'repo'
    await openBoard($, mode)
    return { text: 'Board pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const { rows, mode, refreshedAt } = await read($, state)
    // Digit label and bullet take about 6 cells; the rest is the row.
    const room = Math.max(12, e.props.bodyColumns - 6)
    let itemNo = 0
    return (
      <Box flexDirection="column">
        {/* Controls first: a narrow pane must not scroll them out of reach. */}
        <Box flexDirection="row">
          <Button key="refresh" label="Refresh" hotkey="r" onPress={() => refresh($, mode)} />
          <Button key="close" label="Close" hotkey="q" role="dismiss" onPress={() => $.ui.close({ id: PANE })} />
        </Box>
        <Text dimColor>{`press an item to put it in the prompt · Esc back${refreshedAt ? ` · ${refreshedAt}` : ''}`}</Text>
        {rows.map(row => {
          if (row.kind === 'text') {
            return (
              <Text bold={row.isBold} dimColor={row.isDim} wrap="truncate-end">
                {row.text}
              </Text>
            )
          }
          itemNo += 1
          // Button has no color prop, so the state tone rides on a bullet beside it.
          // A press fills the prompt instead of submitting: a stray key must never start a turn.
          return (
            <Box flexDirection="row">
              {row.tone && <Text color={row.tone}>* </Text>}
              <Button
                key={`item-${itemNo}`}
                plain
                label={fit(row.text, room)}
                hotkey={itemNo <= 9 ? String(itemNo) : undefined}
                dimColor={row.isDim}
                onPress={() => $.prompt.fill({ text: promptFor(row) })}
              />
            </Box>
          )
        })}
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
          <Button key="band-tasks" plain dimColor label="tasks" onPress={() => openBoard($, 'repo')} />
          <Text color="cyan"> {tasks.queued}</Text>
          <Text dimColor> queued · </Text>
          <Text color={tasks.executing > 0 ? 'yellow' : undefined}>{tasks.executing}</Text>
          <Text dimColor> executing</Text>
        </Box>,
      )
    }
    if (handoffs !== undefined) {
      segments.push(
        <Box key="seg-handoffs" flexDirection="row">
          <Text>{handoffs}</Text>
          <Text dimColor> handoffs</Text>
        </Box>,
      )
    }
    if (worktrees !== undefined) {
      segments.push(
        <Box key="seg-worktrees" flexDirection="row">
          <Text>{worktrees}</Text>
          <Text dimColor> worktrees</Text>
        </Box>,
      )
    }
    if (prs !== undefined) {
      segments.push(
        <Box key="seg-prs" flexDirection="row">
          <Text>{prs}</Text>
          <Text dimColor>{prs === 1 ? ' PR open' : ' PRs open'}</Text>
        </Box>,
      )
    }
    if (segments.length === 0) return next(e)
    return (
      <Box flexDirection="row">
        {segments.flatMap((segment, index) => (index === 0 ? [segment] : [<Text dimColor>{'  ·  '}</Text>, segment]))}
      </Box>
    )
  })
}
