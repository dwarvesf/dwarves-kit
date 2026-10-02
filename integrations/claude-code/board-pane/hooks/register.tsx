import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { BoardMode } from '../types'

const PANE = 'board'
const state = atom(
  { plugin: 'board-pane', key: 'state' } as const,
  { lines: [] as string[], mode: 'repo' as BoardMode, isError: false },
)

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

const stripAnsi = (text: string) => text.replace(/\x1b\[[0-9;]*m/g, '')

const refresh = async ($: EngineInterface, mode: BoardMode) => {
  const cwd = await $.session.cwd()
  const board = await resolveBoard($)
  let text: string
  let isError = false
  try {
    const run = await $.process.run(argvFor(board, mode, cwd), { env: { NO_COLOR: '1' } })
    isError = run.exitCode !== 0
    text = isError ? run.stderr || `board exited ${run.exitCode}` : run.stdout
  } catch (err) {
    isError = true
    text = `board could not start: ${String(err)}`
  }
  const lines = stripAnsi(text).trimEnd().split('\n')
  await update($, state, () => ({ lines, mode, isError }))
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
    return { text: 'Board pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const { lines, mode, isError } = await read($, state)
    return (
      <Box flexDirection="column">
        {lines.map(row => (
          <Text dimColor={isError}>{row}</Text>
        ))}
        <Button key="refresh" label="Refresh" onPress={() => refresh($, mode)} />
      </Box>
    )
  })
}
