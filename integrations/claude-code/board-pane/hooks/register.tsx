import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { BoardMode, BoardRow, BoardState } from '../types'
import { clockText, errorRows, parseRows, promptFor } from './parse'

const PANE = 'board'
const REFRESH_MS = 60_000
const initial: BoardState = { rows: [], mode: 'repo', refreshedAt: '' }
const state = atom({ plugin: 'board-pane', key: 'state' } as const, initial)

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

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'board', description: 'Open the kit board in a pane (/board all for the cross-repo view)' })
    return next(e)
  })

  on('command.run', { command: 'board' }, async ($, e) => {
    const mode: BoardMode = e.args.trim() === 'all' ? 'all' : 'repo'
    await refresh($, mode)
    await $.ui.open({ id: PANE, title: mode === 'all' ? 'Board: all repos' : 'Board' })
    autoRefresh($)
    return { text: 'Board pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const { rows, mode, refreshedAt } = await read($, state)
    let itemNo = 0
    return (
      <Box flexDirection="column">
        {refreshedAt && <Text dimColor>refreshed {refreshedAt}</Text>}
        {rows.map(row => {
          if (row.kind === 'text') {
            return (
              <Text bold={row.isBold} dimColor={row.isDim}>
                {row.text}
              </Text>
            )
          }
          itemNo += 1
          // Button has no color prop, so the state tone rides on a bullet beside it.
          return (
            <Box flexDirection="row">
              {row.tone && <Text color={row.tone}>* </Text>}
              <Button
                key={`item-${itemNo}`}
                plain
                label={row.text}
                hotkey={itemNo <= 9 ? String(itemNo) : undefined}
                dimColor={row.isDim}
                onPress={() => $.prompt.submit({ text: promptFor(row) })}
              />
            </Box>
          )
        })}
        <Button key="refresh" label="Refresh" hotkey="r" onPress={() => refresh($, mode)} />
        <Button key="close" label="Close" hotkey="q" role="dismiss" onPress={() => $.ui.close({ id: PANE })} />
      </Box>
    )
  })
}
